require "test_helper"

class OidcProviderTest < ActiveSupport::TestCase
  setup do
    @fake = FakeOidcProvider.new.stub!
  end

  test "the client secret is encrypted at rest" do
    provider = OidcProvider.create!(@fake.provider_attributes)

    stored = OidcProvider.connection.select_value("SELECT client_secret FROM oidc_providers WHERE id = #{provider.id}")

    assert_not_includes stored, FakeOidcProvider::CLIENT_SECRET
    assert_equal FakeOidcProvider::CLIENT_SECRET, provider.reload.client_secret
  end

  test "the client secret never appears in inspect output" do
    provider = OidcProvider.new(@fake.provider_attributes)

    assert_not_includes provider.inspect, FakeOidcProvider::CLIENT_SECRET
  end

  test "a provider whose discovery document can't be fetched is refused when saved" do
    stub_request(:get, "https://nowhere.example.test/.well-known/openid-configuration").to_return(status: 404)

    provider = OidcProvider.new(@fake.provider_attributes.merge(issuer: "https://nowhere.example.test"))

    assert_not provider.save
    assert_match(/discovery document/i, provider.errors[:issuer].to_sentence)
  end

  test "a discovery document missing an endpoint is refused" do
    stub_request(:get, "https://half.example.test/.well-known/openid-configuration")
      .to_return(body: { issuer: "https://half.example.test" }.to_json)

    provider = OidcProvider.new(@fake.provider_attributes.merge(issuer: "https://half.example.test"))

    assert_not provider.save
    assert_match(/authorization_endpoint/, provider.errors[:issuer].to_sentence)
  end

  test "the issuer may be given with or without the well-known path or a trailing slash" do
    [ "#{FakeOidcProvider::ISSUER}/", "#{FakeOidcProvider::ISSUER}/.well-known/openid-configuration" ].each do |given|
      provider = OidcProvider.new(@fake.provider_attributes.merge(issuer: given))

      assert provider.valid?, provider.errors.full_messages.to_sentence
      assert_equal FakeOidcProvider::ISSUER, provider.issuer
    end
  end

  test "a plain http issuer is refused, except on localhost" do
    provider = OidcProvider.new(@fake.provider_attributes.merge(issuer: "http://id.example.test"))
    assert_not provider.valid?
    assert_match(/https/, provider.errors[:issuer].to_sentence)

    stub_request(:get, "http://localhost:3035/.well-known/openid-configuration")
      .to_return(body: @fake.discovery.to_json)
    assert OidcProvider.new(@fake.provider_attributes.merge(issuer: "http://localhost:3035")).valid?
  end

  test "there is only ever one provider" do
    OidcProvider.create!(@fake.provider_attributes)

    assert_not OidcProvider.new(@fake.provider_attributes).valid?
  end
end
