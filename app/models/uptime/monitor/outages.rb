# Alerts from state changes (ADR 0013). An outage opens when a monitor goes
# down and closes when it's up (or warn) again; unknown neither opens nor
# closes one, so down → unknown → down alerts once.
#
# An outage can be hidden (ADR 0033): no reminders, and out of the way on the
# dashboard, until the monitor's next run or for a day. Recovering ends it. If
# it ends while the monitor is still down, a reminder goes out at once, since
# the hide held them back.
module Uptime::Monitor::Outages
  extend ActiveSupport::Concern

  HIDE_FOR = 24.hours

  def remind_if_due(now = Time.current)
    return unless state == "down" && outage_started_at

    if hidden_until
      end_hide(now) if hidden_until <= now
      return
    end

    every = options["remind_every"]
    remind(now) if every && (reminded_at || outage_started_at) <= now - every
  end

  # Hides the current outage for a day, or for a push monitor until its next
  # push: the time it counts as missed, or sooner if a push comes. False if
  # it isn't down, or isn't a push monitor and was asked to wait for a run.
  def hide!(until_next_run: false, now: Time.current)
    return false unless state == "down" && outage_started_at && (push? || !until_next_run)

    update!(hidden_at: now, hidden_until: until_next_run ? next_check_at : now + HIDE_FOR, hidden_until_next_push: until_next_run)
  end

  def hidden?(now = Time.current) = state == "down" && hidden_until.present? && hidden_until > now

  # Reminders carry on as if it had never been hidden.
  def show_again!
    update!(hidden_at: nil, hidden_until: nil, hidden_until_next_push: false)
  end

  private
    def track_outage(from, to, at, message)
      return if from == to

      if to == "down" && outage_started_at.nil?
        self.outage_started_at = at
        self.reminded_at = nil
        clear_hide
        Alert.create!(monitor: self, kind: "down", title: "#{name} is down", message: [ message, target_line ].compact.join("\n"))
      elsif %w[ up warn ].include?(to) && outage_started_at
        Alert.create!(monitor: self, kind: "recovered", title: "#{name} is back up",
          message: "Down for #{to_the_minute(at - outage_started_at)}")
        self.outage_started_at = nil
        self.reminded_at = nil
        clear_hide
      end
    end

    # A hide ran out, or the push it waited for came, and it's still down.
    def end_hide(now)
      transaction do
        clear_hide
        options["remind_every"] ? remind(now) : save!
      end
    end

    def remind(now)
      transaction do
        update!(reminded_at: now)
        Alert.create!(monitor: self, kind: "reminder", title: "#{name} is still down",
          message: "Down for #{to_the_minute(now - outage_started_at)}: #{last_message || "no message"}\n#{target_line}")
      end
    end

    def clear_hide
      self.hidden_at = nil
      self.hidden_until = nil
      self.hidden_until_next_push = false
    end

    def target_line = push? ? "Push monitor #{key}" : target

    # "1 hour and 10 minutes"
    def to_the_minute(seconds)
      Uptime.duration_in_words((seconds / 60).round * 60)
    end
end
