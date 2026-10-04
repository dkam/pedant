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
  FIELDS = %w[ name interval timeout retries expect_status tls_verify ] + KINDS
  DEFAULTS = { "interval" => 60, "timeout" => 10, "retries" => 1, "expect_status" => "200-299", "tls_verify" => true }.freeze
  MIN_INTERVAL = 20

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
        monitor.next_check_at ||= Time.current
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

          if entries.key?(key)
            errors_found << "#{file}: #{key} is already defined in #{entries[key].last}"
          elsif problems.any?
            errors_found << "#{file}: #{key}: #{problems.to_sentence}"
            unreadable[:keys] << key
          else
            entries[key] = [ definition, file ]
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
      problems = []
      return [ nil, [ "not a valid key (lowercase letters, digits, - and _)" ] ] unless key.match?(KEY)
      return [ nil, [ "should be a map of settings" ] ] unless entry.is_a?(Hash)

      entry = entry.transform_keys(&:to_s)
      unknown = entry.keys - FIELDS
      problems << "unknown #{"field".pluralize(unknown.size)} #{unknown.join(", ")}" if unknown.any?

      settings = DEFAULTS.merge(entry)
      kinds = KINDS & entry.keys
      problems << "needs one of #{KINDS.join(", ")}" if kinds.size != 1
      kind = kinds.first
      target = entry[kind].to_s

      problems << "http must be an http:// or https:// URL" if kind == "http" && !web_url?(target)
      %w[ interval timeout retries ].each do |field|
        problems << "#{field} must be a whole number" unless settings[field].is_a?(Integer) && settings[field] >= 0
      end
      if problems.none?
        problems << "interval must be at least #{MIN_INTERVAL} seconds" if settings["interval"] < MIN_INTERVAL
        problems << "timeout must be at least 1 second and less than the interval" unless settings["timeout"].between?(1, settings["interval"] - 1)
      end
      problems << "expect_status must look like 200-299, 401" unless settings["expect_status"].to_s.match?(/\A\s*\d{3}(-\d{3})?(\s*,\s*\d{3}(-\d{3})?)*\s*\z/)
      problems << "tls_verify must be true or false" unless [ true, false ].include?(settings["tls_verify"])

      definition = {
        name: entry["name"].presence&.to_s || key.titleize,
        kind: kind, target: target,
        interval: settings["interval"], timeout: settings["timeout"], retries: settings["retries"],
        options: settings.slice("expect_status", "tls_verify")
      }
      [ definition, problems ]
    end

    def web_url?(target)
      uri = URI.parse(target)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end
end
