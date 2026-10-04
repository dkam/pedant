# Signing in with the owner's password (ADR 0015). Only while a password is the
# sign-in method: once OIDC is in use, this refuses even a correct password.
class PasswordSessionsController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to login_path, alert: "Too many attempts. Try again later." }

  def create
    return redirect_to(login_path) unless SignInMethod.password?

    user = User.with_password.order(:id).first
    if user&.authenticate(params[:password].to_s)
      return_to = session.delete(:return_to)
      start_new_session_for user
      redirect_to return_to || root_path
    else
      Rails.logger.warn "Password sign-in refused"
      flash.now[:alert] = "That password didn't match."
      render "oidc_auth/login", status: :unprocessable_content
    end
  end
end
