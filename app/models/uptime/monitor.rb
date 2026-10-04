# One monitor. Its definition is copied from monitors.yml on each sync (ADR
# 0016); everything else is observed.
#
# States:
# - pending: no conclusive result yet.
# - up / down: down only once failures in a row exceed `retries`. While
#   retrying it stays up (#retrying?), so a blip isn't counted as a flap.
# - warn: a pushed value is past its warn limit. Not a failure, not a flap.
# - unknown: Pedant couldn't tell, because its own connection was down. It
#   neither counts as a failure nor clears one.
#
# Push monitors' own behaviour (values, runs, schedules) is in Uptime::Monitor::Push.
class Uptime::Monitor < ApplicationRecord
  include Push, Outages

  STATES = %w[ pending up warn down unknown ].freeze
  KINDS = %w[ http tcp push ].freeze

  belongs_to :source
  has_many :checks, dependent: :delete_all
  has_many :state_changes, dependent: :delete_all

  scope :active, -> { where(retired_at: nil) }
  # Down first, then unknown, warn and pending, then up; alphabetical within each.
  scope :by_urgency, -> { in_order_of(:state, %w[ down unknown warn pending up ]).order(:name) }

  validates :state, inclusion: { in: STATES }
  validates :kind, inclusion: { in: KINDS }

  def retired? = retired_at.present?
  def retrying? = state == "up" && consecutive_failures.positive?

  def record(result)
    now = Time.current

    transaction do
      checks.create!(status: result.status, latency_ms: result.latency_ms, message: result.message,
        value: result.value, duration_ms: result.duration_ms, checked_at: now)

      self.consecutive_failures = case result.status
      when "up", "warn" then 0
      when "down" then consecutive_failures + 1
      else consecutive_failures
      end

      previous_state = state
      change_state_to next_state(result), message: result.message, at: now
      track_outage previous_state, state, now, result.message
      self.last_value = result.value unless result.value.nil?
      update!(last_checked_at: now, next_check_at: next_due_from(now), last_latency_ms: result.latency_ms, last_message: result.message)
    end
  end

  # When it's next due: an active check one interval on (or now, for a new
  # one). Push monitors work it out from their interval or schedule.
  def next_due_from(time, first: false)
    if push? then next_push_due_from(time)
    elsif first then time
    else time + interval
    end
  end

  def push? = kind == "push"

  # Marks a due monitor as queued, by pushing next_check_at past the time its
  # check could take (the timeout plus LEASE). Only one of two racing callers
  # wins. Recording the result sets the real next time; if the check is lost,
  # the lease runs out and it's claimed again.
  LEASE = 60.seconds

  def claim_for_check(now = Time.current)
    leased_until = now + timeout + LEASE
    claimed = self.class.where(id: id, next_check_at: next_check_at).update_all(next_check_at: leased_until) == 1
    self.next_check_at = leased_until if claimed
    claimed
  end

  # How many times it went down in the window: the "how often does it flap"
  # half of the liveness model.
  def flaps(within: 24.hours)
    state_changes.where(to_state: "down", changed_at: within.ago..).count
  end

  # An active check asks the target. A push monitor is only checked once it's
  # overdue, so its check is the miss.
  def check
    case kind
    when "http" then Uptime::HttpCheck.new(target: target, timeout: timeout, options: options).call
    when "tcp" then Uptime::TcpCheck.new(target: target, timeout: timeout).call
    when "push" then missed_push
    end
  end

  private
    def next_state(result)
      case result.status
      when "down" then consecutive_failures > retries ? "down" : state
      else result.status
      end
    end

    def change_state_to(new_state, message:, at:)
      return if new_state == state

      state_changes.create!(from_state: state, to_state: new_state, message: message, changed_at: at)
      self.state = new_state
      self.state_changed_at = at
    end
end
