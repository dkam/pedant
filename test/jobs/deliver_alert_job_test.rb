require "test_helper"

# Delivery: one job per alert and channel, on the alerts queue, with retries.
# Every attempt is recorded (ADR 0013).
class DeliverAlertJobTest < ActiveJob::TestCase
  setup do
    source = monitor_source("monitors.yml" => { "splat" => { "name" => "Splat", "http" => "http://splat.local:3030/up" } })
    source.sync!
    @monitor = source.monitors.sole
    @alert = Alert.create!(monitor: @monitor, kind: "down", title: "Splat is down", message: "HTTP 503\nhttp://splat.local:3030/up")
  end

  test "ntfy gets splat's request shape: a POST to the topic, with title, priority, tags, a link and the token" do
    channel = ntfy_channel!
    request = stub_request(:post, AlertChannels::NTFY_URL).with(
      body: @alert.message,
      headers: { "Title" => "Splat is down", "Priority" => "high", "Tags" => "red_circle",
                 "Click" => "http://pedant.test/monitors/#{@monitor.id}", "Authorization" => "Bearer ntfy-secret-token" }
    ).to_return(status: 200)

    DeliverAlertJob.perform_now(@alert, channel)

    assert_requested request
    assert_equal [ "sent", nil, 1 ], channel.deliveries.sole.values_at(:status, :error, :attempt)
  end

  test "recovery and reminders get their own priority and tags" do
    channel = ntfy_channel!
    recovered = Alert.create!(monitor: @monitor, kind: "recovered", title: "Splat is back up", message: "Down for 3 minutes")
    request = stub_request(:post, AlertChannels::NTFY_URL).with(headers: { "Priority" => "default", "Tags" => "green_circle" })

    DeliverAlertJob.perform_now(recovered, channel)

    assert_requested request
  end

  test "an ntfy failure is recorded and retried" do
    channel = ntfy_channel!
    stub_request(:post, AlertChannels::NTFY_URL).to_return(status: 500, body: "boom")

    assert_enqueued_with(job: DeliverAlertJob) do
      DeliverAlertJob.perform_now(@alert, channel)
    end

    delivery = channel.deliveries.sole
    assert_equal "failed", delivery.status
    assert_match "HTTP 500", delivery.error
  end

  test "a timeout is recorded as a failure too" do
    channel = ntfy_channel!
    stub_request(:post, AlertChannels::NTFY_URL).to_timeout

    DeliverAlertJob.perform_now(@alert, channel)

    assert_match(/timed out/i, channel.deliveries.sole.error)
  end

  test "the attempt number is recorded across retries" do
    channel = ntfy_channel!
    stub_request(:post, AlertChannels::NTFY_URL).to_return(status: 500).then.to_return(status: 200)

    perform_enqueued_jobs { DeliverAlertJob.perform_later(@alert, channel) }

    assert_equal [ [ 1, "failed" ], [ 2, "sent" ] ], channel.deliveries.order(:id).pluck(:attempt, :status)
  end

  test "email goes to every recipient, through the channel's SMTP server" do
    channel = email_channel!

    DeliverAlertJob.perform_now(@alert, channel)

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "dan@example.com", "ops@example.com" ], mail.to
    assert_equal [ "pedant@example.test" ], mail.from
    assert_equal "Splat is down", mail.subject
    assert_match "HTTP 503", mail.text_part.body.to_s
    assert_match "http://pedant.test/monitors/#{@monitor.id}", mail.text_part.body.to_s
    assert_match "http://pedant.test/monitors/#{@monitor.id}", mail.html_part.body.to_s
    settings = mail.delivery_method.settings
    assert_equal [ "smtp.example.test", 587, "pedant", "smtp-password" ], settings.values_at(:address, :port, :user_name, :password)
    assert_equal "sent", channel.deliveries.sole.status
  end

  # A delivery method that refuses, as an SMTP server with bad credentials would.
  class RefusingDelivery
    def initialize(*) = nil
    def deliver!(*) = raise(Net::SMTPAuthenticationError.new("535 bad credentials"))
  end

  test "an email failure is recorded and retried" do
    channel = email_channel!
    ActionMailer::Base.add_delivery_method :refusing, RefusingDelivery
    previous, ActionMailer::Base.delivery_method = ActionMailer::Base.delivery_method, :refusing

    assert_enqueued_with(job: DeliverAlertJob) { DeliverAlertJob.perform_now(@alert, channel) }
    assert_match "535", channel.deliveries.sole.error
  ensure
    ActionMailer::Base.delivery_method = previous
  end

  test "deliveries run on the alerts queue" do
    assert_equal "alerts", DeliverAlertJob.new.queue_name
  end
end
