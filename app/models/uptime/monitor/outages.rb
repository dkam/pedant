# Alerts from state changes (ADR 0013). An outage opens when a monitor goes
# down and closes when it's up (or warn) again; unknown neither opens nor
# closes one, so down → unknown → down alerts once.
module Uptime::Monitor::Outages
  extend ActiveSupport::Concern

  def remind_if_due(now = Time.current)
    every = options["remind_every"]
    return unless every && state == "down" && outage_started_at
    return if (reminded_at || outage_started_at) > now - every

    transaction do
      update!(reminded_at: now)
      Alert.create!(monitor: self, kind: "reminder", title: "#{name} is still down",
        message: "Down for #{to_the_minute(now - outage_started_at).inspect}: #{last_message || "no message"}\n#{target_line}")
    end
  end

  private
    def track_outage(from, to, at, message)
      return if from == to

      if to == "down" && outage_started_at.nil?
        self.outage_started_at = at
        self.reminded_at = nil
        Alert.create!(monitor: self, kind: "down", title: "#{name} is down", message: [ message, target_line ].compact.join("\n"))
      elsif %w[ up warn ].include?(to) && outage_started_at
        Alert.create!(monitor: self, kind: "recovered", title: "#{name} is back up",
          message: "Down for #{to_the_minute(at - outage_started_at).inspect}")
        self.outage_started_at = nil
        self.reminded_at = nil
      end
    end

    def target_line = push? ? "Push monitor #{key}" : target

    # "1 hour and 10 minutes"
    def to_the_minute(seconds)
      ActiveSupport::Duration.build(((seconds / 60).round * 60).to_i)
    end
end
