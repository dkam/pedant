# A stacks checkout that monitors.yml files are read from (ADR 0016). In
# milestone 1 it's a local directory the owner keeps up to date.
#
# Syncing copies each entry's definition onto its monitor. Nothing a broken
# file says is applied: a file that doesn't parse changes none of its monitors
# and retires none, and an invalid entry keeps its last good definition. The
# errors are kept for the dashboard.
class Uptime::Source < ApplicationRecord
  FILES = [ "monitors.yml", "*/monitors.yml" ].freeze
  KEY = /\A[a-z0-9][a-z0-9_-]*\z/
  KINDS = Uptime::Monitor::KINDS
  FIELDS = {
    "http" => %w[ name interval timeout retries expect_status expect_body expect_json tls_verify remind_every ],
    "tcp" => %w[ name interval timeout retries remind_every ],
    "push" => %w[ name interval schedule timezone grace max_runtime value remind_every ]
  }.freeze
  DEFAULTS = {
    "http" => { "interval" => 60, "timeout" => 10, "retries" => 1, "expect_status" => "200-299", "tls_verify" => true, "remind_every" => 86_400 },
    "tcp" => { "interval" => 60, "timeout" => 10, "retries" => 1, "remind_every" => 86_400 },
    "push" => { "grace" => 60, "remind_every" => 86_400 }
  }.freeze
  MIN_INTERVAL = 20
  DIGEST = /\Asha256:[0-9a-f]{64}\z/
  # host:port, or [v6 address]:port.
  # Keys and array indexes joined with dots: queues.fetch.paused, workers.0.alive.
  JSON_PATH = /\A[^.]+(\.[^.]+)*\z/
  HOST_PORT = /\A(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]):(\d+)\z/
  VALUE_FIELDS = %w[ label unit warn_above warn_below down_above down_below forecast ].freeze
  FORECAST_FIELDS = %w[ reaches down_within warn_within ].freeze
  # 30s, 5m, 3h, 1d, or plain seconds.
  DURATION = /\A(\d+)\s*(s|m|h|d)\z/
  DURATION_UNITS = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400 }.freeze

  has_many :monitors, dependent: :restrict_with_error

  normalizes :path, with: ->(path) { path.strip.delete_suffix("/").presence || path.strip }

  validates :name, presence: true
  validate :path_is_a_directory, if: :will_save_change_to_path?

  def sync_error_list = sync_errors.to_s.lines(chomp: true)

  def sync!
    errors_found = []
    entries, unreadable = read_entries(errors_found)

    transaction do
      entries.each do |key, (definition, file)|
        monitor = monitors.find_or_initialize_by(key: key)
        monitor.assign_attributes(definition.merge(defined_in: file, retired_at: nil))
        monitor.next_check_at ||= monitor.next_due_from(Time.current, first: true)
        monitor.save!
      end

      # Retire only what's gone from a file that was read cleanly.
      monitors.active.where.not(key: entries.keys + unreadable[:keys]).where.not(defined_in: unreadable[:files]).find_each do |monitor|
        monitor.update!(retired_at: Time.current)
      end unless unreadable[:all]

      update!(synced_at: Time.current, sync_errors: errors_found.join("\n").presence)
    end
  end

  private
    def path_is_a_directory
      if path.blank? || !path.start_with?("/")
        errors.add(:path, "must be an absolute path")
      elsif !File.directory?(path)
        errors.add(:path, "isn't a directory Pedant can read")
      end
    end

    # Returns { key => [definition, file] }, and what couldn't be read: whole
    # files, keys whose entries were invalid, or everything.
    def read_entries(errors_found)
      entries = {}
      tokens = {}
      unreadable = { all: false, files: [], keys: [] }

      unless File.directory?(path)
        errors_found << "Can't read #{path}: no such directory"
        unreadable[:all] = true
        return [ entries, unreadable ]
      end

      FILES.flat_map { |pattern| Dir.glob(pattern, base: path).sort }.each do |file|
        monitors_in(file, errors_found, unreadable)&.each do |key, entry|
          key = key.to_s
          definition, problems = definition_for(key, entry)
          problems += token_problems(definition, tokens) if problems.none? && definition[:kind] == "push"

          if entries.key?(key)
            errors_found << "#{file}: #{key} is already defined in #{entries[key].last}"
          elsif problems.any?
            errors_found << "#{file}: #{key}: #{problems.to_sentence}"
            unreadable[:keys] << key
          else
            entries[key] = [ definition, file ]
            tokens[definition[:target]] = key if definition[:kind] == "push"
          end
        end
      end

      [ entries, unreadable ]
    end

    def monitors_in(file, errors_found, unreadable)
      document = YAML.safe_load_file(File.join(path, file)) || {}
      found = document.is_a?(Hash) ? (document["monitors"] || {}) : nil
      raise Psych::Exception, "expected a 'monitors:' map at the top" unless found.is_a?(Hash)
      found
    rescue Psych::Exception, SystemCallError => error
      errors_found << "#{file}: #{error.message}"
      unreadable[:files] << file
      nil
    end

    def definition_for(key, entry)
      return [ nil, [ "not a valid key (lowercase letters, digits, - and _)" ] ] unless key.match?(KEY)
      return [ nil, [ "should be a map of settings" ] ] unless entry.is_a?(Hash)

      entry = entry.transform_keys(&:to_s)
      kinds = KINDS & entry.keys
      return [ nil, [ "needs one of #{KINDS.join(", ")}" ] ] if kinds.size != 1

      kind = kinds.first
      problems = []
      unknown = entry.keys - FIELDS.fetch(kind) - [ kind ]
      problems << "unknown #{"field".pluralize(unknown.size)} for a #{kind} monitor: #{unknown.join(", ")}" if unknown.any?

      settings = DEFAULTS.fetch(kind).merge(entry)
      %w[ interval timeout grace max_runtime remind_every ].each { |field| settings[field] = seconds(settings[field]) if settings.key?(field) }
      settings["remind_every"] = nil if entry["remind_every"] == "never"
      settings["value"] = with_forecast_in_seconds(settings["value"]) if settings.key?("value")
      target = entry[kind].to_s
      problems.concat case kind
      when "http" then http_problems(target, settings)
      when "tcp" then tcp_problems(target, settings)
      when "push" then push_problems(target, entry, settings)
      end
      problems << "remind_every must be a duration of at least 5 minutes, or never" unless settings["remind_every"].nil? || (settings["remind_every"].is_a?(Integer) && settings["remind_every"] >= 300)

      definition = {
        name: entry["name"].presence&.to_s || key.titleize,
        kind: kind, target: target,
        interval: settings["interval"],
        timeout: settings.fetch("timeout", 0), retries: settings.fetch("retries", 0), grace: settings.fetch("grace", 0),
        options: settings.slice("expect_status", "expect_body", "expect_json", "tls_verify", "schedule", "timezone", "max_runtime", "value", "remind_every")
      }
      [ definition, problems ]
    end

    def http_problems(target, settings)
      problems = []
      problems << "http must be an http:// or https:// URL" unless web_url?(target)
      problems.concat timing_problems(settings)
      problems << "expect_status must look like 200-299, 401" unless settings["expect_status"].to_s.match?(/\A\s*\d{3}(-\d{3})?(\s*,\s*\d{3}(-\d{3})?)*\s*\z/)
      problems << "tls_verify must be true or false" unless [ true, false ].include?(settings["tls_verify"])
      problems << "expect_body must be the text to find" if settings.key?("expect_body") && !(settings["expect_body"].is_a?(String) && settings["expect_body"].present?)
      problems.concat expect_json_problems(settings["expect_json"]) if settings.key?("expect_json")
      problems
    end

    def expect_json_problems(expected)
      return [ "expect_json should be a map of paths to values, such as queue_status: healthy" ] unless expected.is_a?(Hash) && expected.any?

      expected.filter_map do |path, value|
        if !path.to_s.match?(JSON_PATH)
          "expect_json path #{path.to_s.inspect} should be keys joined with dots, such as queues.fetch.paused"
        elsif !(value.nil? || value.is_a?(String) || value.is_a?(Numeric) || [ true, false ].include?(value))
          "expect_json #{path} should be a single value; write a nested key as #{path}.<key>"
        end
      end
    end

    def tcp_problems(target, settings)
      problems = []
      if (match = HOST_PORT.match(target))
        problems << "tcp port must be between 1 and 65535" unless match[1].to_i.between?(1, 65_535)
      else
        problems << "tcp must be host:port, such as pg01:5432"
      end
      problems + timing_problems(settings)
    end

    # The interval, timeout and retries of an active check.
    def timing_problems(settings)
      problems = whole_numbers(settings, %w[ interval timeout retries ])
      if problems.none?
        problems << "interval must be at least #{MIN_INTERVAL} seconds" if settings["interval"] < MIN_INTERVAL
        problems << "timeout must be at least 1 second and less than the interval" unless settings["timeout"].between?(1, settings["interval"] - 1)
      end
      problems
    end

    # The token is a credential, so the file holds only its digest (ADR 0016).
    def push_problems(target, entry, settings)
      problems = []
      problems << "push must be the token's digest, sha256: and 64 hex digits, not the token (bin/rails pedant:push_token makes both)" unless target.match?(DIGEST)

      if entry.key?("interval") == entry.key?("schedule")
        problems << "push needs an interval or a schedule, not both: when a push is expected"
      elsif entry.key?("schedule")
        problems.concat schedule_problems(settings["schedule"], settings["timezone"])
      else
        problems << "timezone only goes with a schedule" if entry.key?("timezone")
        problems.concat whole_numbers(settings, %w[ interval ])
        problems << "interval must be at least #{MIN_INTERVAL} seconds" if problems.none? && settings["interval"] < MIN_INTERVAL
      end

      problems.concat whole_numbers(settings, %w[ grace ])
      problems.concat whole_numbers(settings, %w[ max_runtime ]) if settings.key?("max_runtime")
      problems.concat value_problems(settings["value"]) if settings.key?("value")
      problems
    end

    def schedule_problems(schedule, timezone)
      return [ "a schedule needs a timezone, such as Australia/Sydney" ] if timezone.blank?
      return [ "timezone #{timezone} isn't a time zone Pedant knows" ] unless TZInfo::Timezone.all_identifiers.include?(timezone.to_s)
      return [ "schedule #{schedule.inspect} isn't a cron schedule (minute hour day month weekday)" ] unless Fugit.parse_cron("#{schedule} #{timezone}").is_a?(Fugit::Cron)
      []
    end

    def value_problems(value)
      return [ "value should be a map (label, unit, and limits)" ] unless value.is_a?(Hash)

      problems = []
      unknown = value.keys.map(&:to_s) - VALUE_FIELDS
      problems << "value has an unknown #{"setting".pluralize(unknown.size)} #{unknown.join(", ")}" if unknown.any?
      limits = value.slice(*VALUE_FIELDS.grep(/_/))
      limits.each { |name, limit| problems << "value #{name} must be a number" unless limit.is_a?(Numeric) }
      return problems if problems.any?

      problems.concat forecast_problems(value["forecast"]) if value.key?("forecast")
      problems << "value warn_above must be below down_above" if limits["warn_above"] && limits["down_above"] && limits["warn_above"] >= limits["down_above"]
      problems << "value warn_below must be above down_below" if limits["warn_below"] && limits["down_below"] && limits["warn_below"] <= limits["down_below"]
      problems
    end

    # A forecast (ADR 0023): the level the value heads for, and how soon
    # getting there is down or warn.
    def forecast_problems(forecast)
      return [ "value forecast should be a map (reaches, down_within, warn_within)" ] unless forecast.is_a?(Hash)

      problems = []
      unknown = forecast.keys.map(&:to_s) - FORECAST_FIELDS
      problems << "value forecast has an unknown #{"setting".pluralize(unknown.size)} #{unknown.join(", ")}" if unknown.any?
      if !forecast.key?("reaches") then problems << "value forecast needs reaches: the level it heads for, such as 0"
      elsif !forecast["reaches"].is_a?(Numeric) then problems << "value forecast reaches must be a number"
      end

      withins = forecast.slice("down_within", "warn_within")
      problems << "value forecast needs down_within or warn_within" if withins.empty?
      withins.each { |name, within| problems << "value forecast #{name} must be a duration, such as 3d" unless within.is_a?(Integer) && within.positive? }
      if problems.none? && withins.size == 2 && withins["warn_within"] <= withins["down_within"]
        problems << "value forecast warn_within must be longer than down_within"
      end
      problems
    end

    def with_forecast_in_seconds(value)
      return value unless value.is_a?(Hash) && value["forecast"].is_a?(Hash)

      forecast = value["forecast"].to_h { |name, setting| [ name, name.end_with?("_within") ? seconds(setting) : setting ] }
      value.merge("forecast" => forecast)
    end

    # A token must name one monitor, in this repo or any other source.
    def token_problems(definition, tokens)
      if (other = tokens[definition[:target]])
        [ "uses the same push token as #{other}" ]
      elsif (other = Uptime::Monitor.active.where(kind: "push", target: definition[:target]).where.not(source_id: id).includes(:source).first)
        [ "uses the same push token as #{other.key} in #{other.source.name}" ]
      else
        []
      end
    end

    # A duration as seconds, or the original (for the error) if it isn't one.
    def seconds(duration)
      match = DURATION.match(duration.to_s.strip) if duration.is_a?(String)
      match ? match[1].to_i * DURATION_UNITS.fetch(match[2]) : duration
    end

    def whole_numbers(settings, fields)
      fields.filter_map { |field| "#{field} must be a whole number" unless settings[field].is_a?(Integer) && settings[field] >= 0 }
    end

    def web_url?(target)
      uri = URI.parse(target)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end
end
