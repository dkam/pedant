# The owner's own sign-in settings (ADR 0015).
#
# With a password: change the email or password, or switch to OIDC. Switching saves the provider
# and sends the browser through its login; the identity that comes back is
# linked to this owner and the password removed, in OidcAuthController#callback.
# Until then the password keeps working (see SignInMethod).
#
# With OIDC: nothing to change here. Switching back is a console job
# (`bin/rails pedant:reset_oidc`), like every other way back in.
class SettingsController < ApplicationController
  before_action :require_password_method, only: %i[ update_email update_password link_oidc ]
  before_action :set_provider

  rate_limit to: 10, within: 10.minutes, only: %i[ update_email update_password link_oidc ], with: -> { redirect_to settings_path, alert: "Too many attempts. Try again later." }

  def show
  end

  def update_email
    return wrong_password(current_user) unless current_user.authenticate(params[:current_password].to_s)

    if current_user.update(params.fetch(:user, {}).permit(:email))
      redirect_to settings_path, notice: "Email changed. Sign in with the new one from now on."
    else
      render :show, status: :unprocessable_content
    end
  end

  def update_password
    return wrong_password(current_user) unless current_user.authenticate(params[:current_password].to_s)

    new_password = params.fetch(:user, {}).permit(:password, :password_confirmation)
    current_user.assign_attributes(new_password)
    current_user.errors.add(:password, "can't be blank") if new_password[:password].blank?

    if current_user.errors.none? && current_user.save
      # Every other session ends; this one carries on with the new token.
      current_user.rotate_session_token!
      start_new_session_for current_user
      redirect_to settings_path, notice: "Password changed. Other sessions have been signed out."
    else
      render :show, status: :unprocessable_content
    end
  end

  def link_oidc
    return wrong_password(@provider) unless current_user.authenticate(params[:current_password].to_s)

    @provider.assign_attributes(params.fetch(:oidc_provider, {}).permit(:issuer, :client_id, :client_secret, :name))
    if @provider.save
      session[:linking_user_id] = current_user.id
      session[:linking_started_at] = Time.current.to_i
      redirect_to login_start_path
    else
      render :show, status: :unprocessable_content
    end
  end

  private
    def require_password_method
      head :not_found unless SignInMethod.password? && current_user.password_digest.present?
    end

    def set_provider
      @provider = OidcProvider.current || OidcProvider.new(name: "Clinch")
    end

    def wrong_password(record)
      record.errors.add(:base, "Your current password didn't match.")
      render :show, status: :unprocessable_content
    end
end
