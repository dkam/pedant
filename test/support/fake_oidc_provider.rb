# A stand-in OIDC provider, stubbed over HTTP with WebMock: discovery, JWKS
# and the token endpoint. Tests choose who the provider says is logging in,
# then drive the real login flow against it.
class FakeOidcProvider
  include WebMock::API

  ISSUER = "https://id.example.test"
  CLIENT_ID = "pedant-test"
  CLIENT_SECRET = "test-client-secret"

  attr_reader :token_requests

  def initialize(issuer: ISSUER)
    @issuer = issuer
    @key = OpenSSL::PKey::RSA.new(2048)
    @jwk = JWT::JWK.new(@key, kid: "test-key")
    @token_requests = []
    @identity = { "sub" => "owner-sub", "email" => "dan@example.com", "name" => "Dan" }
  end

  def stub!
    stub_request(:get, "#{@issuer}/.well-known/openid-configuration")
      .to_return(json(discovery))
    stub_request(:get, "#{@issuer}/jwks")
      .to_return(json(keys: [ @jwk.export ]))
    stub_request(:post, "#{@issuer}/token").to_return do |request|
      @token_requests << request
      json(access_token: "access", token_type: "Bearer", expires_in: 300, id_token: id_token(@identity))
    end
    self
  end

  def discovery
    {
      issuer: @issuer,
      authorization_endpoint: "#{@issuer}/authorize",
      token_endpoint: "#{@issuer}/token",
      jwks_uri: "#{@issuer}/jwks",
      userinfo_endpoint: "#{@issuer}/userinfo"
    }
  end

  # Who the next login comes back as. Anything in claims overrides the
  # defaults, including iss, aud and exp, so tests can send a bad token.
  def logs_in_as(**claims)
    @identity = claims.transform_keys(&:to_s)
  end

  def id_token(claims)
    now = Time.now.to_i
    payload = { "iss" => @issuer, "aud" => CLIENT_ID, "iat" => now, "exp" => now + 300 }.merge(claims)
    JWT.encode(payload.compact, @key, "RS256", kid: "test-key")
  end

  def logout_token(sub: nil, sid: nil, jti: SecureRandom.uuid)
    now = Time.now.to_i
    JWT.encode({
      "iss" => @issuer, "aud" => CLIENT_ID, "iat" => now, "jti" => jti, "sub" => sub, "sid" => sid,
      "events" => { "http://schemas.openid.net/event/backchannel-logout" => {} }
    }.compact, @key, "RS256", kid: "test-key")
  end

  def provider_attributes
    { issuer: @issuer, client_id: CLIENT_ID, client_secret: CLIENT_SECRET, name: "Clinch" }
  end

  private
    def json(body)
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end
end
