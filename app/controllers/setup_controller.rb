# Claiming the instance (ADRs 0009, 0011 and 0015). The credential is the setup
# code printed on the server's console. With it, the owner either:
#
# - chooses a password (create_password), and is signed in, or
# - saves an OIDC provider (create) and is sent through its login; the identity
#   that comes back becomes the owner, in OidcAuthController#callback.
#
# This controller exists only while setup is open: see Setup.
class SetupController < ApplicationController
  allow_unauthenticated_access
  before_action :ensure_setup_open
  before_action :set_provider, :set_owner

  rate_limit to: 10, within: 10.minutes, only: %i[ create create_password ], with: -> { redirect_to setup_path, alert: "Too many attempts. Try again later." }

  def new
  end

  def create
    @provider.assign_attributes(provider_params)
    return wrong_code unless Setup.correct?(params[:code])

    if @provider.save
      # Lets this browser, and only this one, claim the identity it brings back.
      session[:setup_claimed_at] = Time.current.to_i
      redirect_to login_start_path
    else
      render :new, status: :unprocessable_content
    end
  end

  def create_password
    return wrong_code(@owner) unless Setup.correct?(params[:code])

    @owner.assign_attributes(password_params)
    # has_secure_password ignores a blank password rather than failing it, and
    # an owner kept from OIDC would then save with no password at all.
    @owner.errors.add(:password, "can't be blank") if password_params[:password].blank?

    if @owner.errors.none? && @owner.save
      start_new_session_for @owner
      redirect_to root_path, notice: "Pedant is yours. Sign in with this password from now on."
    else
      render :new, status: :unprocessable_content
    end
  end

  private
    # 404 rather than 403: a different status would tell a stranger whether
    # this instance has been claimed.
    def ensure_setup_open
      head :not_found unless Setup.open?
    end

    # Setup can be re-entered until somebody has signed in, so a typo in the
    # provider is fixed by doing it again.
    def set_provider
      @provider = OidcProvider.current || OidcProvider.new(name: "Clinch")
    end

    # The owner kept through a console reset, or a new one.
    def set_owner
      @owner = User.order(:id).first || User.new
    end

    def wrong_code(record = @provider)
      record.errors.add(:base, "That code doesn't match the one on the server's console.")
      render :new, status: :unprocessable_content
    end

    def password_params
      params.fetch(:user, {}).permit(:email, :password, :password_confirmation)
    end

    # A blank secret keeps the saved one, which the form never shows.
    def provider_params
      permitted = params.fetch(:oidc_provider, {}).permit(:issuer, :client_id, :client_secret, :name)
      permitted.delete(:client_secret) if permitted[:client_secret].blank? && @provider.persisted?
      permitted
    end
end
