# OIDC login, ported from spool (docs/auth.md there). The `openid_connect` gem
# is used directly rather than through omniauth, so PKCE, ID token checks and
# backchannel logout are all visible here.
#
# Two differences from spool. The provider comes from the database (ADR 0011),
# not env variables. And nobody is provisioned by logging in: a known identity
# (issuer + subject) signs in, the owner is created once by setup, and anyone
# else is refused (ADR 0009).
class OidcAuthController < ApplicationController
  allow_unauthenticated_access only: %i[ login start callback backchannel_logout ]
  skip_forgery_protection only: :backchannel_logout
  before_action :require_provider, only: %i[ start callback ]

  rate_limit to: 20, within: 10.minutes, only: :callback, with: -> { redirect_to login_path, alert: "Too many attempts. Try again later." }

  # Asymmetric algorithms only. Naming the set is what stops an "alg": "none"
  # token being accepted.
  ALGORITHMS = %w[RS256 RS384 RS512 PS256 PS384 PS512 ES256 ES384 ES512].freeze
  BACKCHANNEL_EVENT = "http://schemas.openid.net/event/backchannel-logout".freeze

  # GET /login
  def login
    return redirect_to(root_path) if authenticated?

    @provider = OidcProvider.current
    render formats: :html
  end

  # GET /login/start
  def start
    session[:auth_state] = SecureRandom.hex(16)
    # PKCE (RFC 7636). Not required for a confidential client, but it closes
    # authorization-code interception for free.
    session[:pkce_verifier] = SecureRandom.urlsafe_base64(64).delete("=")
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(session[:pkce_verifier]), padding: false)

    redirect_to oidc_client.authorization_uri(
      scope: "openid email profile",
      state: session[:auth_state],
      code_challenge: challenge,
      code_challenge_method: "S256"
    ), allow_other_host: true
  end

  # GET /auth/callback
  def callback
    expected_state = session.delete(:auth_state)
    verifier = session.delete(:pkce_verifier)
    setup_claimed_at = session.delete(:setup_claimed_at)

    unless verifier.present? && valid_state?(params[:state], expected_state)
      return refuse("That sign-in didn't match the one we started. Please try again.", log: "OIDC state mismatch")
    end

    oidc_client.authorization_code = params[:code]
    id_token = oidc_client.access_token!(code_verifier: verifier).id_token
    return refuse("The provider sent no ID token.") if id_token.blank?

    claims = verified_claims(id_token)
    return refuse("The provider didn't say who you are.") if claims["sub"].blank?

    user = User.identified_by(claims) || claim_instance(claims, setup_claimed_at)
    unless user
      who = claims["email"].presence || claims["sub"]
      return refuse("#{who} isn't a Pedant user.", log: "Refused unknown identity iss=#{claims["iss"]} sub=#{claims["sub"]}")
    end

    user.refresh_from(claims)
    return_to = session.delete(:return_to)
    start_new_session_for(user, sid: claims["sid"])
    redirect_to return_to || root_path
  rescue OpenIDConnect::Exception, Rack::OAuth2::Client::Error => e
    refuse("Sign-in failed at the provider. Please try again.", log: "OIDC token exchange failed: #{e.class}: #{e.message}")
  rescue JWT::DecodeError => e
    # Signature, issuer, audience and expiry failures all land here.
    refuse("The provider's identity token didn't check out.", log: "OIDC ID token rejected: #{e.class}: #{e.message}")
  end

  # DELETE /logout
  def logout
    terminate_session
    redirect_to login_path, notice: "Signed out."
  end

  # POST /oidc/logout: the provider telling us a session ended there.
  def backchannel_logout
    claims = verified_logout_claims(params[:logout_token].to_s)
    return head(:bad_request) unless claims

    sessions =
      if claims["sid"].present?
        OidcSession.live.where(oidc_sid: claims["sid"]).to_a
      else
        User.find_by(oidc_issuer: claims["iss"], oidc_sub: claims["sub"])&.oidc_sessions&.live.to_a
      end
    sessions.each(&:invalidate!)

    render json: { status: "ok", sessions_terminated: sessions.size }
  end

  private
    def require_provider
      redirect_to login_path, alert: "Pedant has no OIDC provider yet." unless OidcProvider.configured?
    end

    def provider
      @provider ||= OidcProvider.current
    end

    def oidc_client
      @oidc_client ||= provider.client(redirect_uri: auth_callback_url)
    end

    # The owner, created once: only by the browser that entered the setup code,
    # and only within Setup::CLAIM_WINDOW of entering it.
    def claim_instance(claims, setup_claimed_at)
      return unless setup_claimed_at && Time.at(setup_claimed_at) > Setup::CLAIM_WINDOW.ago

      User.create!(oidc_issuer: claims["iss"], oidc_sub: claims["sub"]).tap do |user|
        Rails.logger.info "Pedant claimed by iss=#{user.oidc_issuer} sub=#{user.oidc_sub}"
      end
    end

    def refuse(message, log: message)
      Rails.logger.warn log
      redirect_to login_path, alert: message
    end

    # Constant-time, so the comparison can't be used as an oracle.
    def valid_state?(given, expected)
      given.present? && expected.present? && ActiveSupport::SecurityUtils.secure_compare(given, expected)
    end

    # Verified, not just decoded: the JWKS is one request away, and checking
    # signature, issuer, audience and expiry leaves nothing to argue about.
    def verified_claims(token)
      JWT.decode(token, nil, true,
        algorithms: ALGORITHMS, jwks: provider.jwks,
        iss: provider.expected_issuer, verify_iss: true,
        aud: provider.client_id, verify_aud: true,
        verify_expiration: true, verify_iat: true).first
    end

    # Signature first, then the claims, then replay: an unsigned token mustn't
    # be able to fill the replay cache.
    def verified_logout_claims(token)
      return if token.blank? || provider.nil?

      claims = JWT.decode(token, nil, true,
        algorithms: ALGORITHMS, jwks: provider.jwks,
        iss: provider.expected_issuer, verify_iss: true,
        aud: provider.client_id, verify_aud: true, verify_iat: true).first

      return unless (%w[iss aud iat jti events] - claims.keys).empty?
      return unless claims.dig("events", BACKCHANNEL_EVENT)
      return unless claims["sid"].present? || claims["sub"].present?
      # The spec puts the replay window at 24 hours.
      replay_key = "pedant/logout_token/#{claims["jti"]}"
      return if Rails.cache.exist?(replay_key)

      Rails.cache.write(replay_key, true, expires_in: 24.hours)

      claims
    rescue JWT::DecodeError => e
      Rails.logger.warn "Backchannel logout token rejected: #{e.class}: #{e.message}"
      nil
    end
end
