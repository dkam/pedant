require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "a password is at least twelve characters" do
    user = User.new(email: "dan@example.com", password: "elevenchars", password_confirmation: "elevenchars")

    assert_not user.valid?
    assert user.errors[:password].any?
  end

  test "a password must match its confirmation" do
    user = User.new(email: "dan@example.com", password: "a long enough password", password_confirmation: "something else entirely")

    assert_not user.valid?
    assert user.errors[:password_confirmation].any?
  end

  test "a password longer than bcrypt reads is refused rather than silently truncated" do
    long = "x" * 73
    user = User.new(email: "dan@example.com", password: long, password_confirmation: long)

    assert_not user.valid?
  end

  test "the password is stored hashed" do
    user = User.create!(email: "dan@example.com", password: "a long enough password", password_confirmation: "a long enough password")

    assert_not_includes user.password_digest, "a long enough password"
    assert user.authenticate("a long enough password")
    assert_not user.authenticate("the wrong password!!")
  end

  test "a user needs a password or an OIDC identity" do
    assert_not User.new.valid?
    assert User.new(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "sub").valid?
  end

  test "every user gets a session token, and rotating it changes it" do
    user = User.create!(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "sub")
    before = user.session_token

    user.rotate_session_token!

    assert before.present?
    assert_not_equal before, user.reload.session_token
  end

  test "resetting the password removes it and rotates the session token" do
    user = User.create!(email: "dan@example.com", password: "a long enough password", password_confirmation: "a long enough password")
    before = user.session_token

    user.reset_password!

    assert_nil user.reload.password_digest
    assert_not_equal before, user.session_token
  end

  test "a password user needs a valid email" do
    assert_not User.new(password: "a long enough password", password_confirmation: "a long enough password").valid?
    assert_not User.new(email: "not an email", password: "a long enough password", password_confirmation: "a long enough password").valid?
  end

  test "the email is stored trimmed and lowercase" do
    user = User.create!(email: "  Dan@Example.COM ", password: "a long enough password", password_confirmation: "a long enough password")

    assert_equal "dan@example.com", user.email
  end

  test "a user signs in with a password or an OIDC identity, never both" do
    user = User.new(email: "dan@example.com", password: "a long enough password", password_confirmation: "a long enough password",
      oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "owner-sub")

    assert_not user.valid?
  end
end
