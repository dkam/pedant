# Something Pedant told someone (ADR 0013): a monitor went down, is still
# down, or recovered; or a test from the alerts page. Once committed, it's
# queued for every enabled channel. A test is sent straight away instead,
# through the one channel being tested.
class Alert < ApplicationRecord
  KINDS = %w[ down reminder recovered test ].freeze

  belongs_to :monitor, class_name: "Uptime::Monitor", optional: true
  has_many :deliveries, class_name: "AlertDelivery", dependent: :delete_all

  validates :kind, inclusion: { in: KINDS }

  after_create_commit :deliver_later, unless: -> { kind == "test" }

  def deliver_later
    AlertChannel.enabled.find_each { |channel| DeliverAlertJob.perform_later(self, channel) }
  end
end
