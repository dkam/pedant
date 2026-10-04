# One monitor. Its definition is copied from monitors.yml on each sync (ADR
# 0016); everything else is observed.
#
# States:
# - pending: no conclusive result yet.
# - up / down: down only once failures in a row exceed `retries`. While
#   retrying it stays up (#retrying?), so a blip isn't counted as a flap.
# - unknown: Pedant couldn't tell, because its own connection was down. It
#   neither counts as a failure nor clears one.
class Uptime::Monitor < ApplicationRecord
  STATES = %w[ pending up down unknown ].freeze
  KINDS = %w[ http ].freeze

  belongs_to :source
  has_many :checks, dependent: :delete_all
  has_many :state_changes, dependent: :delete_all

  scope :active, -> { where(retired_at: nil) }
  # Down first, then unknown and pending, then up; alphabetical within each.
  scope :by_urgency, -> { in_order_of(:state, %w[ down unknown pending up ]).order(:name) }

  validates :state, inclusion: { in: STATES }
  validates :kind, inclusion: { in: KINDS }

  def retired? = retired_at.present?
  def retrying? = state == "up" && consecutive_failures.positive?

  def record(result)
    now = Time.current

    transaction do
      checks.create!(status: result.status, latency_ms: result.latency_ms, message: result.message, checked_at: now)

      self.consecutive_failures = case result.status
      when "up" then 0
      when "down" then consecutive_failures + 1
      else consecutive_failures
      end

      change_state_to next_state(result), message: result.message, at: now
      update!(last_checked_at: now, next_check_at: now + interval, last_latency_ms: result.latency_ms, last_message: result.message)
    end
  end

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

  def check
    case kind
    when "http" then Uptime::HttpCheck.new(target: target, timeout: timeout, options: options).call
    end
  end

  private
    def next_state(result)
      case result.status
      when "up" then "up"
      when "unknown" then "unknown"
      when "down" then consecutive_failures > retries ? "down" : state
      end
    end

    def change_state_to(new_state, message:, at:)
      return if new_state == state

      state_changes.create!(from_state: state, to_state: new_state, message: message, changed_at: at)
      self.state = new_state
      self.state_changed_at = at
    end
end
