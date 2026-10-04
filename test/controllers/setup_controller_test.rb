require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    @provider = FakeOidcProvider.new.stub!
  end

  test "an empty instance offers setup, and shows the redirect URI to register" do
    get setup_url

    assert_response :success
    assert_select "h1", "Set up Pedant"
    assert_includes response.body, "http://www.example.com/auth/callback"
    assert_no_match Setup.code, response.body, "the code is shown on the console, never on the page"
  end

  test "the right code saves the provider and sends the browser to it" do
    assert_difference -> { OidcProvider.count }, 1 do
      post setup_url, params: setup_params
    end

    assert_redirected_to login_start_url
    assert_equal "pedant-test", OidcProvider.sole.client_id
  end

  test "a wrong code saves nothing and says so" do
    assert_no_difference -> { OidcProvider.count } do
      post setup_url, params: setup_params(code: "ZZZZ-ZZZZ-ZZZZ")
    end

    assert_response :unprocessable_content
    assert_select ".alert", /doesn't match the one on the server's console/
  end

  test "a wrong code hands back what was typed, except the secret" do
    post setup_url, params: setup_params(code: "ZZZZ-ZZZZ-ZZZZ")

    assert_select "input[name=?][value=?]", "oidc_provider[client_id]", "pedant-test"
    assert_select "input[name=?]:not([value])", "oidc_provider[client_secret]"
  end

  test "a provider that can't be discovered is reported on the form" do
    stub_request(:get, "https://nowhere.example.test/.well-known/openid-configuration").to_return(status: 404)

    assert_no_difference -> { OidcProvider.count } do
      post setup_url, params: setup_params(provider: { issuer: "https://nowhere.example.test" })
    end

    assert_response :unprocessable_content
    assert_select ".alert", /discovery document/i
  end

  test "re-entering setup before anyone has signed in replaces the provider" do
    post setup_url, params: setup_params
    post setup_url, params: setup_params(provider: { client_id: "second-try" })

    assert_equal "second-try", OidcProvider.sole.client_id
  end

  test "a blank secret keeps the one already saved, which the form never shows" do
    post setup_url, params: setup_params
    get setup_url
    assert_no_match FakeOidcProvider::CLIENT_SECRET, response.body
    assert_select "input[name=?]:not([value])", "oidc_provider[client_secret]"

    post setup_url, params: setup_params(provider: { client_id: "second-try", client_secret: "" })

    assert_equal FakeOidcProvider::CLIENT_SECRET, OidcProvider.sole.client_secret
  end

  test "the code, then the provider's login, makes that identity the owner" do
    post setup_url, params: setup_params

    assert_difference -> { User.count }, 1 do
      log_in(sub: "owner-sub", email: "dan@example.com", name: "Dan")
    end

    assert_redirected_to root_url
    owner = User.sole
    assert_equal [ FakeOidcProvider::ISSUER, "owner-sub" ], [ owner.oidc_issuer, owner.oidc_sub ]

    get root_url
    assert_response :success
  end

  test "setup closes behind the owner" do
    post setup_url, params: setup_params
    log_in

    get setup_url
    assert_response :not_found

    assert_no_difference -> { OidcProvider.count } do
      post setup_url, params: setup_params(provider: { client_id: "hijack" })
    end
    assert_response :not_found
    assert_equal "pedant-test", OidcProvider.sole.client_id
  end

  # 404, not 403: the same status as a route that never existed, so a stranger
  # can't learn whether this instance has been claimed.
  test "a closed setup looks exactly like a page that isn't there" do
    post setup_url, params: setup_params
    log_in

    get setup_url
    closed = response.status
    get "/no-such-page-at-all"

    assert_equal response.status, closed
  end

  test "a login without the code claims nothing, even while setup is open" do
    OidcProvider.create!(@provider.provider_attributes)

    assert_no_difference -> { User.count } do
      log_in(sub: "stranger")
    end

    assert_redirected_to login_url
  end

  test "the code is good for one claim only" do
    post setup_url, params: setup_params
    log_in(sub: "owner-sub")
    delete logout_url

    assert_no_difference -> { User.count } do
      log_in(sub: "second-person")
    end
  end

  test "a code entered long ago no longer claims" do
    post setup_url, params: setup_params

    travel 16.minutes do
      assert_no_difference -> { User.count } do
        log_in
      end
    end
  end

  test "after the console resets OIDC, the code and a login get back in" do
    post setup_url, params: setup_params
    log_in(sub: "owner-sub")
    delete logout_url

    OidcProvider.delete_all # what rake pedant:reset_oidc does
    get setup_url
    assert_response :success

    post setup_url, params: setup_params
    assert_no_difference -> { User.count }, "the same identity signs back in as the same user" do
      log_in(sub: "owner-sub")
    end
    assert_redirected_to root_url
  end

  test "the setup page offers a password and OIDC" do
    get setup_url

    assert_select "form[action=?]", setup_password_path
    assert_select "form[action=?]", setup_path
  end

  test "the right code and a good password make the owner and sign them in" do
    assert_difference -> { User.count }, 1 do
      post setup_password_url, params: password_params
    end

    assert_redirected_to root_url
    assert User.sole.authenticate("a long enough password")
    assert_equal :password, SignInMethod.current

    get root_url
    assert_response :success
  end

  test "a password owner needs a valid email" do
    post setup_password_url, params: password_params(email: "")
    assert_response :unprocessable_content

    post setup_password_url, params: password_params(email: "not an email")
    assert_response :unprocessable_content

    assert_equal 0, User.count
  end

  test "the password owner's email is what they sign in with" do
    post setup_password_url, params: password_params(email: "Dan@Example.com")
    delete logout_url

    post login_url, params: { email: "dan@example.com", password: "a long enough password" }

    assert_redirected_to root_url
  end

  test "after resetting OIDC, the password form starts with the email the provider gave" do
    post setup_url, params: setup_params
    log_in(sub: "owner-sub", email: "dan@example.com")
    delete logout_url
    OidcProvider.delete_all

    get setup_url

    assert_select "input[name=?][value=?]", "user[email]", "dan@example.com"
  end

  test "setup closes behind a password owner" do
    post setup_password_url, params: password_params

    get setup_url
    assert_response :not_found

    assert_no_difference -> { User.count } do
      post setup_password_url, params: password_params(password: "another long password")
    end
    assert_response :not_found
  end

  test "a wrong code sets no password" do
    assert_no_difference -> { User.count } do
      post setup_password_url, params: password_params(code: "ZZZZ-ZZZZ-ZZZZ")
    end

    assert_response :unprocessable_content
    assert_select ".alert", /doesn't match the one on the server's console/
  end

  test "a short or mismatched password sets nothing" do
    post setup_password_url, params: password_params(password: "short", confirmation: "short")
    assert_response :unprocessable_content

    post setup_password_url, params: password_params(confirmation: "not the same at all")
    assert_response :unprocessable_content

    post setup_password_url, params: password_params(password: "", confirmation: "")
    assert_response :unprocessable_content

    assert_equal 0, User.count
  end

  test "after resetting OIDC, choosing a password keeps the same owner" do
    post setup_url, params: setup_params
    log_in(sub: "owner-sub")
    delete logout_url
    OidcProvider.delete_all # what rake pedant:reset_oidc does

    assert_no_difference -> { User.count } do
      post setup_password_url, params: password_params
    end

    assert User.sole.authenticate("a long enough password")
    assert_equal :password, SignInMethod.current
  end

  test "after resetting OIDC, a blank password doesn't leave the owner without one" do
    post setup_url, params: setup_params
    log_in(sub: "owner-sub")
    delete logout_url
    OidcProvider.delete_all

    post setup_password_url, params: password_params(password: "", confirmation: "")

    assert_response :unprocessable_content
    assert_nil User.sole.password_digest
    assert Setup.open?
  end

  test "a wrong setup code keeps the email that was typed" do
    post setup_password_url, params: password_params(code: "WRONGCODE", email: "dan@example.com")

    assert_response :unprocessable_content
    assert_select "input[name='user[email]'][value=?]", "dan@example.com"
    assert_not User.exists?
  end

  private
    def password_params(code: Setup.code, email: "dan@example.com", password: "a long enough password", confirmation: password)
      { code: code, user: { email: email, password: password, password_confirmation: confirmation } }
    end

    def setup_params(code: Setup.code, provider: {})
      { code: code, oidc_provider: @provider.provider_attributes.merge(provider) }
    end
end
