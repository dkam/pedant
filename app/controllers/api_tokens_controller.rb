# Making and revoking API tokens for /mcp (ADR 0025), from the settings page.
class ApiTokensController < ApplicationController
  # The token is shown once. Only its digest is stored, so the redirect
  # carries it to the settings page in the flash, which is in the encrypted
  # session cookie and gone after that one request. Rendering it from this
  # POST instead would make a reload issue another token.
  def create
    token, plaintext = ApiToken.issue!(name: params.expect(api_token: [ :name ])[:name])
    flash[:api_token] = { "name" => token.name, "token" => plaintext }
    redirect_to settings_path(anchor: "api-tokens"), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to settings_path(anchor: "api-tokens"), status: :see_other, alert: "Token not made: #{error.record.errors.full_messages.to_sentence}."
  end

  def destroy
    token = ApiToken.find(params[:id])
    token.destroy!
    redirect_to settings_path(anchor: "api-tokens"), status: :see_other, notice: "#{token.name} revoked. Anything still using it is refused from now on."
  end
end
