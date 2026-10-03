require "test_helper"

class OidcAuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    configure_provider
    @owner = User.create!(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "owner-sub", email: "dan@example.com")
  end

  test "pages need a login" do
    get root_url

    assert_redirected_to login_url
  end

  test "the login page offers the provider by name" do
    get login_url

    assert_response :success
    assert_select "a[href=?]", login_start_path, text: /Clinch/
  end

  test "an unconfigured instance's login page points at setup" do
    OidcProvider.delete_all

    get login_url

    assert_select "a[href=?]", setup_path
  end

  test "login starts with state and a PKCE challenge, and the verifier goes to the token endpoint" do
    get login_start_url

    query = Rack::Utils.parse_query(URI(response.location).query)
    assert response.location.start_with?("#{FakeOidcProvider::ISSUER}/authorize")
    assert_equal "S256", query["code_challenge_method"]
    assert query["code_challenge"].present?
    assert query["state"].present?

    get auth_callback_url, params: { code: "auth-code", state: query["state"] }

    verifier = Rack::Utils.parse_query(@provider.token_requests.sole.body)["code_verifier"]
    assert_equal query["code_challenge"],
      Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
  end

  test "a known user signs in and lands where they were going" do
    get root_url
    log_in(sub: "owner-sub", email: "dan@example.com")

    assert_redirected_to root_url
    get root_url
    assert_response :success
  end

  test "a stranger with a perfectly good login is refused" do
    assert_no_difference -> { User.count } do
      log_in(sub: "stranger", email: "stranger@example.com")
    end

    assert_redirected_to login_url
    follow_redirect!
    assert_select ".alert", /isn't a Pedant user/

    get root_url
    assert_redirected_to login_url
  end

  test "the same subject from another issuer is a different person" do
    other = FakeOidcProvider.new(issuer: "https://other.example.test").stub!
    OidcProvider.sole.update_columns(issuer: "https://other.example.test")
    @provider = other

    log_in(sub: "owner-sub")

    get root_url
    assert_redirected_to login_url
  end

  test "a forged state is refused" do
    get login_start_url
    get auth_callback_url, params: { code: "auth-code", state: "forged" }

    assert_redirected_to login_url
    assert_empty @provider.token_requests
  end

  test "an ID token signed by someone else is refused" do
    impostor = OpenSSL::PKey::RSA.new(2048)
    token = JWT.encode({ "iss" => FakeOidcProvider::ISSUER, "aud" => FakeOidcProvider::CLIENT_ID,
      "sub" => "owner-sub", "iat" => Time.now.to_i, "exp" => Time.now.to_i + 300 }, impostor, "RS256", kid: "test-key")
    @provider.define_singleton_method(:id_token) { |_claims| token }

    log_in

    get root_url
    assert_redirected_to login_url
  end

  test "an ID token for another client is refused" do
    log_in(sub: "owner-sub", aud: "someone-else")

    get root_url
    assert_redirected_to login_url
  end

  test "an expired ID token is refused" do
    log_in(sub: "owner-sub", exp: 1.minute.ago.to_i)

    get root_url
    assert_redirected_to login_url
  end

  test "a token with no subject is refused" do
    log_in(sub: nil)

    get root_url
    assert_redirected_to login_url
  end

  test "signing in updates the email and name the provider reports" do
    log_in(sub: "owner-sub", email: "new@example.com", name: "Daniel")

    assert_equal [ "new@example.com", "Daniel" ], [ @owner.reload.email, @owner.name ]
  end

  test "logging out ends the session" do
    log_in(sub: "owner-sub")
    delete logout_url

    get root_url
    assert_redirected_to login_url
  end

  test "backchannel logout by sid ends that session" do
    log_in(sub: "owner-sub", sid: "provider-session")

    post oidc_logout_url, params: { logout_token: @provider.logout_token(sid: "provider-session") }
    assert_response :success

    get root_url
    assert_redirected_to login_url
  end

  test "backchannel logout by subject ends that user's sessions" do
    log_in(sub: "owner-sub", sid: "provider-session")

    post oidc_logout_url, params: { logout_token: @provider.logout_token(sub: "owner-sub") }
    assert_response :success

    get root_url
    assert_redirected_to login_url
  end

  test "a replayed logout token is refused" do
    token = @provider.logout_token(sid: "provider-session", jti: "once")

    with_memory_cache do
      post oidc_logout_url, params: { logout_token: token }
      assert_response :success

      post oidc_logout_url, params: { logout_token: token }
      assert_response :bad_request
    end
  end

  test "a logout token signed by someone else is refused" do
    log_in(sub: "owner-sub", sid: "provider-session")
    token = JWT.encode({ "iss" => FakeOidcProvider::ISSUER, "aud" => FakeOidcProvider::CLIENT_ID,
      "iat" => Time.now.to_i, "jti" => "x", "sid" => "provider-session",
      "events" => { "http://schemas.openid.net/event/backchannel-logout" => {} } },
      OpenSSL::PKey::RSA.new(2048), "RS256", kid: "test-key")

    post oidc_logout_url, params: { logout_token: token }
    assert_response :bad_request

    get root_url
    assert_response :success
  end

  private
    def with_memory_cache
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = original
    end
end
