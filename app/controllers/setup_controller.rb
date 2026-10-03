# Claiming the instance (ADRs 0009 and 0011). The credential is the setup code
# printed on the server's console. With it, this form saves the OIDC provider
# and sends the browser through the provider's login; the identity that comes
# back becomes the owner. The claim itself happens in OidcAuthController#callback.
#
# This controller exists only while setup is open: see Setup.
class SetupController < ApplicationController
  allow_unauthenticated_access
  before_action :ensure_setup_open
  before_action :set_provider

  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { redirect_to setup_path, alert: "Too many attempts. Try again later." }

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

    def wrong_code
      @provider.errors.add(:base, "That code doesn't match the one on the server's console.")
      render :new, status: :unprocessable_content
    end

    # A blank secret keeps the saved one, which the form never shows.
    def provider_params
      permitted = params.fetch(:oidc_provider, {}).permit(:issuer, :client_id, :client_secret, :name)
      permitted.delete(:client_secret) if permitted[:client_secret].blank? && @provider.persisted?
      permitted
    end
end
