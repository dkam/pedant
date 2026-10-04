# Sends one alert through one channel, retrying with backoff. Each attempt is
# recorded by AlertChannel#deliver. A failure never touches the check that
# raised the alert: this runs on its own queue.
class DeliverAlertJob < ApplicationJob
  queue_as :alerts
  retry_on AlertChannel::DeliveryFailed, attempts: 5, wait: :polynomially_longer
  discard_on ActiveJob::DeserializationError

  def perform(alert, channel)
    channel.deliver(alert, attempt: executions)
  end
end
