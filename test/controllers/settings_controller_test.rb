require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_password_owner
    @provider = FakeOidcProvider.new.stub!
  end

  test "settings need a login" do
    get settings_url

    assert_redirected_to login_url
  end

  test "changing the password needs the current one" do
    sign_in_with_password

    patch settings_password_url, params: { current_password: "wrong wrong wrong", user: new_password }

    assert_response :unprocessable_content
    assert @owner.reload.authenticate("a long enough password")
  end

  test "changing the password keeps this session and ends every other" do
    other = open_session
    other.post login_url, params: { email: "dan@example.com", password: "a long enough password" }

    sign_in_with_password
    patch settings_password_url, params: { current_password: "a long enough password", user: new_password }

    assert_redirected_to settings_url
    assert @owner.reload.authenticate("an even longer password")
    get root_url
    assert_response :success

    other.get root_url
    assert_equal login_url, other.response.location
  end

  test "changing the email needs the current password" do
    sign_in_with_password

    patch settings_email_url, params: { current_password: "wrong wrong wrong", user: { email: "new@example.com" } }
    assert_response :unprocessable_content
    assert_equal "dan@example.com", @owner.reload.email

    patch settings_email_url, params: { current_password: "a long enough password", user: { email: "New@Example.com" } }
    assert_redirected_to settings_url
    assert_equal "new@example.com", @owner.reload.email
  end

  test "an invalid email isn't saved" do
    sign_in_with_password

    patch settings_email_url, params: { current_password: "a long enough password", user: { email: "nope" } }

    assert_response :unprocessable_content
    assert_equal "dan@example.com", @owner.reload.email
  end

  test "switching to OIDC needs the current password" do
    sign_in_with_password

    assert_no_difference -> { OidcProvider.count } do
      post settings_oidc_url, params: { current_password: "wrong wrong wrong", oidc_provider: @provider.provider_attributes }
    end

    assert_response :unprocessable_content
  end

  test "switching to OIDC links the identity to this owner and removes the password" do
    sign_in_with_password
    post settings_oidc_url, params: { current_password: "a long enough password", oidc_provider: @provider.provider_attributes }
    assert_redirected_to login_start_url

    assert_no_difference -> { User.count } do
      log_in(sub: "owner-sub")
    end

    @owner.reload
    assert_equal [ FakeOidcProvider::ISSUER, "owner-sub" ], [ @owner.oidc_issuer, @owner.oidc_sub ]
    assert_nil @owner.password_digest
    assert_equal :oidc, SignInMethod.current
  end

  test "after switching, the old password no longer signs in and OIDC does" do
    sign_in_with_password
    post settings_oidc_url, params: { current_password: "a long enough password", oidc_provider: @provider.provider_attributes }
    log_in(sub: "owner-sub")
    delete logout_url

    sign_in_with_password
    get root_url
    assert_redirected_to login_url

    log_in(sub: "owner-sub")
    get root_url
    assert_response :success
  end

  test "an abandoned switch leaves the password working" do
    sign_in_with_password
    post settings_oidc_url, params: { current_password: "a long enough password", oidc_provider: @provider.provider_attributes }
    delete logout_url

    sign_in_with_password

    get root_url
    assert_response :success
  end

  test "a stranger can't use a pending switch to get in" do
    sign_in_with_password
    post settings_oidc_url, params: { current_password: "a long enough password", oidc_provider: @provider.provider_attributes }
    delete logout_url

    assert_no_difference -> { User.count } do
      log_in(sub: "stranger")
    end

    get root_url
    assert_redirected_to login_url
    assert @owner.reload.password_digest.present?
  end

  test "a pending switch dies with the session that started it" do
    sign_in_with_password
    post settings_oidc_url, params: { current_password: "a long enough password", oidc_provider: @provider.provider_attributes }
    @owner.reset_password! # the console ends every session mid-switch

    assert_no_difference -> { User.count } do
      log_in(sub: "stranger")
    end

    assert_nil @owner.reload.oidc_sub
    assert_redirected_to login_url
  end

  test "a switch not finished within the window links nothing" do
    sign_in_with_password
    post settings_oidc_url, params: { current_password: "a long enough password", oidc_provider: @provider.provider_attributes }

    travel 16.minutes do
      log_in(sub: "owner-sub")
    end

    assert_nil @owner.reload.oidc_sub
    assert @owner.password_digest.present?
  end

  test "an OIDC owner sees how to switch back, and can't change a password they don't have" do
    @owner.update_columns(password_digest: nil, oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "owner-sub")
    OidcProvider.create!(@provider.provider_attributes)
    log_in(sub: "owner-sub")

    get settings_url
    assert_response :success
    assert_includes response.body, "pedant:reset_oidc"
    assert_select "form[action=?]", settings_password_path, count: 0

    patch settings_password_url, params: { current_password: "", user: new_password }
    assert_response :not_found
  end

  private
    def new_password
      { password: "an even longer password", password_confirmation: "an even longer password" }
    end
end
