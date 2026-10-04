# Sessions, for both sign-in methods (ADR 0015). Ported from spool. A session
# holds the user's id and session token; for OIDC, the provider's `sid` is
# mapped in OidcSession so backchannel logout can end it.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      current_user.present?
    end

    def current_user
      return @current_user if defined?(@current_user)

      @current_user = (session_user if session[:user_id] && oidc_session_valid?)
    end

    # The session carries the user's session token from sign-in. Rotating it
    # (a password change, a console reset) ends every session that has the old one.
    def session_user
      user = User.find_by(id: session[:user_id])
      return user if user&.session_token.present? &&
        ActiveSupport::SecurityUtils.secure_compare(session[:session_token].to_s, user.session_token)

      reset_session
      nil
    end

    def require_authentication
      return if authenticated?

      session[:return_to] = request.fullpath if request.get? && !request.xhr?
      redirect_to login_path
    end

    def start_new_session_for(user, sid: nil)
      # Rotate the session id on login, so a session fixated before it can't
      # be reused after it.
      reset_session
      session[:user_id] = user.id
      session[:session_token] = user.session_token
      session[:oidc_sid] = sid if sid.present?
      @current_user = user

      if sid.present?
        OidcSession.create!(user: user, oidc_sid: sid, session_id: session.id&.to_s.presence || SecureRandom.hex(16), expires_at: 24.hours.from_now)
      end
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Losing the mapping degrades backchannel logout; it mustn't cost the
      # login. Logged, because nothing visible goes wrong.
      Rails.logger.error "Failed to record OIDC session mapping: #{e.message}"
    end

    def terminate_session
      OidcSession.find_by(oidc_sid: session[:oidc_sid])&.destroy if session[:oidc_sid].present?
      reset_session
      @current_user = nil
    end

    # Has the provider ended this session from elsewhere (backchannel logout)?
    # Only meaningful when it issued a sid.
    def oidc_session_valid?
      return true if session[:oidc_sid].blank?
      return true if OidcSession.find_live(session[:oidc_sid])

      Rails.logger.info "OIDC session ended by the provider: sid=#{session[:oidc_sid]}"
      reset_session
      false
    end
end
