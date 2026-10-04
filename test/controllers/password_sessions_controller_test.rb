require "test_helper"

class PasswordSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_password_owner
  end

  test "the login page asks for the password, and offers no provider" do
    get login_url

    assert_select "input[type=password][name=password]"
    assert_select "a[href=?]", login_start_path, count: 0
  end

  test "the right password signs in and lands where they were going" do
    get root_url
    sign_in_with_password

    assert_redirected_to root_url
    get root_url
    assert_response :success
  end

  test "a wrong password is refused" do
    sign_in_with_password("not the right password")

    assert_response :unprocessable_content
    assert_select ".alert", /didn't match/

    get root_url
    assert_redirected_to login_url
  end

  test "resetting the password from the console ends existing sessions" do
    sign_in_with_password

    @owner.reset_password! # what rake pedant:reset_password does

    get root_url
    assert_redirected_to login_url
  end

  test "with OIDC in use, password sign-in is off, even for a user with a password" do
    provider = FakeOidcProvider.new.stub!
    OidcProvider.create!(provider.provider_attributes)
    User.create!(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "someone")

    sign_in_with_password

    get root_url
    assert_redirected_to login_url
  end

  test "with no owner yet, password sign-in is off" do
    User.delete_all

    sign_in_with_password

    assert_redirected_to login_url
    get root_url
    assert_redirected_to login_url
  end
end
