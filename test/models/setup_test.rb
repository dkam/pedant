require "test_helper"

class SetupTest < ActiveSupport::TestCase
  test "setup is open on an empty instance" do
    assert Setup.open?
  end

  test "setup stays open until a provider is configured and somebody has signed in" do
    OidcProvider.create!(FakeOidcProvider.new.stub!.provider_attributes)
    assert Setup.open?, "a provider alone, with nobody signed in yet, is a setup half done"

    User.create!(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "owner-sub")
    assert_not Setup.open?
  end

  test "clearing the provider reopens setup, even with users" do
    OidcProvider.create!(FakeOidcProvider.new.stub!.provider_attributes)
    User.create!(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "owner-sub")

    OidcProvider.delete_all

    assert Setup.open?, "nobody can sign in without a provider, so the console must be able to reopen setup"
  end

  test "the code is twelve characters in three groups, from an unambiguous alphabet" do
    assert_match(/\A[#{Setup::ALPHABET}]{4}-[#{Setup::ALPHABET}]{4}-[#{Setup::ALPHABET}]{4}\z/, Setup.code)
    assert_no_match(/[01OI]/, Setup.code)
  end

  test "the code is the same on every call, so every process agrees on it" do
    assert_equal Setup.code, Setup.code
  end

  test "the code is Pedant's own, not kith's, from the same secret" do
    kiths = Rails.application.key_generator.generate_key("kith/setup code", Setup::LENGTH)
      .each_byte.map { |byte| Setup::ALPHABET[byte % Setup::ALPHABET.size] }.join
      .scan(/.{4}/).join("-")

    assert_not_equal kiths, Setup.code
  end

  test "the code is accepted however it was typed" do
    assert Setup.correct?(Setup.code)
    assert Setup.correct?(Setup.code.downcase)
    assert Setup.correct?(Setup.code.delete("-"))
    assert Setup.correct?(" #{Setup.code.tr("-", " ")} ")
  end

  test "anything else is refused" do
    assert_not Setup.correct?(nil)
    assert_not Setup.correct?("")
    assert_not Setup.correct?("----")
    assert_not Setup.correct?("#{Setup.code}X")
    assert_not Setup.correct?(Setup.code.sub(/\A./) { |c| c == "Z" ? "Y" : "Z" })
  end

  test "the banner carries the code, and is announced while setup is open" do
    assert_includes Setup.banner, Setup.code

    announced = StringIO.new
    Setup.announce(announced)
    assert_includes announced.string, Setup.code
  end

  test "nothing is announced once setup is done" do
    OidcProvider.create!(FakeOidcProvider.new.stub!.provider_attributes)
    User.create!(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "owner-sub")

    announced = StringIO.new
    Setup.announce(announced)

    assert_empty announced.string
  end
end
