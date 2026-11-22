require "test_helper"

# Making and revoking API tokens on the settings page (ADR 0025).
class ApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    create_password_owner
  end

  test "making a token needs a login" do
    post api_tokens_url, params: { api_token: { name: "laptop" } }

    assert_redirected_to login_url
    assert_equal 0, ApiToken.count
  end

  test "a new token is shown once, with the command that uses it" do
    sign_in_with_password

    post api_tokens_url, params: { api_token: { name: "laptop" } }
    assert_redirected_to settings_url(anchor: "api-tokens")
    follow_redirect!

    token = css_select("[data-issued-token] pre").first.text.strip
    assert token.start_with?(ApiToken::PREFIX)
    assert_equal ApiToken.digest(token), ApiToken.sole.token_digest
    assert_select "[data-issued-token]", /claude mcp add --transport http/
    assert_select "[data-issued-token]", /Authorization: Bearer #{token}/
    assert_select "meta[name=turbo-cache-control][content=no-cache]"
    assert_select "[data-api-token=?]", ApiToken.sole.id.to_s, /laptop.*never used/m

    get settings_url

    assert_select "[data-issued-token]", 0
    assert_not_includes response.body, token
  end

  test "a token needs a name" do
    sign_in_with_password

    post api_tokens_url, params: { api_token: { name: " " } }

    assert_equal 0, ApiToken.count
    follow_redirect!
    assert_select ".alert", /Name can't be blank/
  end

  test "revoking a token stops it at once" do
    record, token = ApiToken.issue!(name: "laptop")
    sign_in_with_password

    delete api_token_url(record)

    assert_redirected_to settings_url(anchor: "api-tokens")
    assert_nil ApiToken.authenticate(token)
  end

  test "revoking needs a login" do
    record, _token = ApiToken.issue!(name: "laptop")

    delete api_token_url(record)

    assert_redirected_to login_url
    assert ApiToken.exists?(record.id)
  end

  test "the token never reaches the log" do
    sign_in_with_password
    log = StringIO.new
    previous = [ Rails.logger, ActionController::Base.logger, ActionView::Base.logger ]
    Rails.logger = ActionController::Base.logger = ActionView::Base.logger = ActiveSupport::Logger.new(log)

    post api_tokens_url, params: { api_token: { name: "laptop" } }
    follow_redirect!
    token = css_select("[data-issued-token] pre").first.text.strip

    assert_includes log.string, "api_tokens"
    assert_not_includes log.string, token
  ensure
    Rails.logger, ActionController::Base.logger, ActionView::Base.logger = previous
  end
end
