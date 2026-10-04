# One attempt to send an alert through a channel.
class AlertDelivery < ApplicationRecord
  belongs_to :alert
  belongs_to :channel, class_name: "AlertChannel"

  validates :status, inclusion: { in: %w[ sent failed ] }
end
