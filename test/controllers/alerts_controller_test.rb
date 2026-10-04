require "test_helper"

# The alerts page: channel settings, a test button per channel, and the log
# of what was sent (ADR 0013).
class AlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_password_owner
  end

  test "the alerts page needs a login" do
    get alerts_url

    assert_redirected_to login_url
  end

  test "saving ntfy keeps the token encrypted and never shows it again" do
    sign_in_with_password

    patch alert_channel_url("ntfy"), params: { alert_channel: { url: AlertChannels::NTFY_URL, secret: "tk_live_secret", enabled: "1" } }

    assert_redirected_to alerts_url
    channel = AlertChannel::Ntfy.sole
    assert_equal [ AlertChannels::NTFY_URL, "tk_live_secret", true ], [ channel.url, channel.secret, channel.enabled ]
    assert_not_includes AlertChannel.connection.select_value("SELECT secret FROM alert_channels"), "tk_live_secret"
    assert_equal "http://www.example.com", channel.settings["link_base"]

    get alerts_url
    assert_not_includes response.body, "tk_live_secret"
  end

  test "a blank secret keeps the saved one" do
    sign_in_with_password
    ntfy_channel!(token: "keep-me")

    patch alert_channel_url("ntfy"), params: { alert_channel: { url: "https://ntfy.example.test/other", secret: "" } }

    assert_equal [ "https://ntfy.example.test/other", "keep-me" ], AlertChannel::Ntfy.sole.values_at(:url, :secret)
  end

  test "ntfy needs an http(s) topic URL" do
    sign_in_with_password

    patch alert_channel_url("ntfy"), params: { alert_channel: { url: "ntfy.example.test" } }

    assert_response :unprocessable_content
    assert_empty AlertChannel.all
  end

  test "saving email keeps the SMTP password encrypted, and checks the addresses" do
    sign_in_with_password

    patch alert_channel_url("email"), params: { alert_channel: { address: "smtp.example.test", port: "587", user_name: "pedant", secret: "smtp-pw", from: "pedant@example.test", to: "dan@example.com" } }
    assert_redirected_to alerts_url
    assert_equal [ "smtp.example.test", 587, "smtp-pw" ], AlertChannel::Email.sole.values_at(:address, :port, :secret)

    patch alert_channel_url("email"), params: { alert_channel: { to: "dan@example.com, not an address" } }
    assert_response :unprocessable_content
    assert_equal "dan@example.com", AlertChannel::Email.sole.to
  end

  test "the test button sends through that channel now, and says how it went" do
    sign_in_with_password
    ntfy_channel!
    stub_request(:post, AlertChannels::NTFY_URL).to_return(status: 200)

    post test_alert_channel_url("ntfy")

    assert_redirected_to alerts_url
    assert_equal "Test alert sent through ntfy.", flash[:notice]
    assert_equal [ "test", nil ], Alert.sole.values_at(:kind, :monitor_id)
    assert_equal "sent", AlertDelivery.sole.status
  end

  test "a failed test says why" do
    sign_in_with_password
    ntfy_channel!
    stub_request(:post, AlertChannels::NTFY_URL).to_return(status: 403, body: "forbidden")

    post test_alert_channel_url("ntfy")

    assert_redirected_to alerts_url
    assert_match(/ntfy failed: HTTP 403/, flash[:alert])
  end

  test "the page lists recent alerts and how each delivery went" do
    sign_in_with_password
    channel = ntfy_channel!
    alert = Alert.create!(kind: "test", title: "Test alert from Pedant")
    AlertDelivery.create!(alert: alert, channel: channel, status: "failed", error: "HTTP 500", attempted_at: Time.current)

    get alerts_url

    assert_select "[data-alert]", /Test alert from Pedant/
    assert_select "[data-alert] [data-delivery=failed]", /ntfy/
  end

  test "a failing channel shows on the dashboard" do
    sign_in_with_password
    channel = ntfy_channel!
    AlertDelivery.create!(alert: Alert.create!(kind: "test", title: "t"), channel: channel, status: "failed", error: "HTTP 500", attempted_at: Time.current)

    get root_url

    assert_select ".alert", /ntfy.*failing.*HTTP 500/m
  end

  test "a channel that has recovered no longer shows as failing" do
    sign_in_with_password
    channel = ntfy_channel!
    alert = Alert.create!(kind: "test", title: "t")
    AlertDelivery.create!(alert: alert, channel: channel, status: "failed", error: "HTTP 500", attempted_at: 2.minutes.ago)
    AlertDelivery.create!(alert: alert, channel: channel, status: "sent", attempted_at: 1.minute.ago)

    get root_url

    assert_select ".alert", text: /failing/, count: 0
  end
end
