require "test_helper"

class SignInMethodTest < ActiveSupport::TestCase
  setup do
    @fake = FakeOidcProvider.new.stub!
  end

  test "an empty instance has no sign-in method, and setup is open" do
    assert_nil SignInMethod.current
    assert Setup.open?
  end

  test "an owner with a password and no provider signs in with the password" do
    User.create!(email: "dan@example.com", password: "a long enough password", password_confirmation: "a long enough password")

    assert_equal :password, SignInMethod.current
    assert_not Setup.open?
  end

  test "a provider with an OIDC user signs in with OIDC" do
    OidcProvider.create!(@fake.provider_attributes)
    User.create!(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "owner-sub")

    assert_equal :oidc, SignInMethod.current
    assert_not Setup.open?
  end

  test "a provider saved during OIDC setup, before anyone signs in, is OIDC with setup still open" do
    OidcProvider.create!(@fake.provider_attributes)

    assert_equal :oidc, SignInMethod.current
    assert Setup.open?
  end

  # Switching from a password to OIDC saves the provider first, then links the
  # identity at the provider's callback. Until that happens the password must
  # keep working, or an abandoned switch locks the owner out.
  test "a provider saved while switching keeps the password working until an identity is linked" do
    User.create!(email: "dan@example.com", password: "a long enough password", password_confirmation: "a long enough password")
    OidcProvider.create!(@fake.provider_attributes)

    assert_equal :password, SignInMethod.current
    assert_not Setup.open?
  end

  test "resetting the password with no provider reopens setup" do
    owner = User.create!(email: "dan@example.com", password: "a long enough password", password_confirmation: "a long enough password")

    owner.reset_password!

    assert_nil SignInMethod.current
    assert Setup.open?
  end
end
