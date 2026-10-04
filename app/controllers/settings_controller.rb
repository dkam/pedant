# The owner's own sign-in settings (ADR 0015), and where monitors are read from.
#
# With a password: change the email or password, or switch to OIDC. Switching saves the provider
# and sends the browser through its login; the identity that comes back is
# linked to this owner and the password removed, in OidcAuthController#callback.
# Until then the password keeps working (see SignInMethod).
#
# With OIDC: nothing to change here. Switching back is a console job
# (`bin/rails pedant:reset_oidc`), like every other way back in.
#
# Each form works on its own copy of the owner, so a rejected change shows its
# errors in its own form and never reaches current_user (the header shows it).
class SettingsController < ApplicationController
  before_action :require_password_method, only: %i[ update_email update_password link_oidc ]
  before_action :set_provider
  before_action :require_current_password, only: %i[ update_email update_password link_oidc ]

  rate_limit to: 10, within: 10.minutes, only: %i[ update_email update_password link_oidc ], with: -> { redirect_to settings_path, alert: "Too many attempts. Try again later." }

  def show
  end

  def update_email
    if @email_user.update(params.expect(user: [ :email ]))
      redirect_to settings_path, notice: "Email changed. Sign in with the new one from now on."
    else
      render :show, status: :unprocessable_content
    end
  end

  def update_password
    new_password = params.fetch(:user, {}).permit(:password, :password_confirmation)
    @password_user.assign_attributes(new_password)
    @password_user.errors.add(:password, "can't be blank") if new_password[:password].blank?

    if @password_user.errors.none? && @password_user.save
      # Every other session ends; this one carries on with the new token.
      @password_user.rotate_session_token!
      start_new_session_for @password_user
      redirect_to settings_path, notice: "Password changed. Other sessions have been signed out."
    else
      render :show, status: :unprocessable_content
    end
  end

  def link_oidc
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

    # Every change here needs the current password. A wrong one is reported in
    # the form it came from.
    def require_current_password
      @email_user = User.find(current_user.id) if action_name == "update_email"
      @password_user = User.find(current_user.id) if action_name == "update_password"
      return if current_user.authenticate(params[:current_password].to_s)

      record = { "update_email" => @email_user, "update_password" => @password_user, "link_oidc" => @provider }.fetch(action_name)
      record.errors.add(:base, "Your current password didn't match.")
      render :show, status: :unprocessable_content
    end
end
