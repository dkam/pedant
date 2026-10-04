# Someone who can sign in: today, only the owner. There's no sign-up; setup
# creates the owner (see Setup).
#
# A user signs in with a password or an OIDC identity (ADR 0015). The identity
# is the provider's issuer plus subject, never the email: a provider can change
# someone's email, and the same subject from another provider is a different
# person (ADR 0009).
class User < ApplicationRecord
  # bcrypt reads only the first 72 bytes; anything longer would be silently
  # truncated, so refuse it instead.
  PASSWORD_LENGTH = 12..72

  has_secure_password validations: false
  has_many :oidc_sessions, dependent: :delete_all

  scope :with_password, -> { where.not(password_digest: nil) }
  scope :with_oidc, -> { where.not(oidc_sub: nil) }

  normalizes :email, with: ->(email) { email.strip.downcase }

  # A password user signs in with their email; an OIDC user's comes from the provider.
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, if: :password_digest?
  validates :password, length: { in: PASSWORD_LENGTH }, confirmation: true, allow_nil: true
  validates :oidc_sub, uniqueness: { scope: :oidc_issuer }, allow_nil: true
  validate :can_sign_in

  before_create { self.session_token ||= self.class.new_session_token }

  def self.identified_by(claims)
    find_by(oidc_issuer: claims["iss"], oidc_sub: claims["sub"]) if claims["iss"].present? && claims["sub"].present?
  end

  def self.new_session_token = SecureRandom.base58(32)

  # Keep what the provider says about them current.
  def refresh_from(claims)
    update!(email: claims["email"].presence || email, name: claims["name"].presence || name)
  end

  # Ends every session, including the one calling it; see Authentication.
  def rotate_session_token!
    update_columns(session_token: self.class.new_session_token, updated_at: Time.current)
  end

  # From the console (pedant:reset_password). Without a provider this reopens
  # setup, so the code sets a new password.
  def reset_password!
    update_columns(password_digest: nil, session_token: self.class.new_session_token, updated_at: Time.current)
  end

  # From the provider's callback while switching from a password to OIDC.
  def link_identity!(claims)
    update!(oidc_issuer: claims["iss"], oidc_sub: claims["sub"], password_digest: nil,
      session_token: self.class.new_session_token)
  end

  def display_name
    name.presence || email.presence || (oidc_sub ? oidc_sub : "Owner")
  end

  private
    # Exactly one way in. Both at once would count the owner as an OIDC user
    # while their password is still the way in (see SignInMethod).
    def can_sign_in
      identity = oidc_issuer.present? && oidc_sub.present?
      if password_digest.present? && identity
        errors.add(:base, "A user signs in with a password or OIDC, not both")
      elsif password_digest.blank? && !identity
        errors.add(:password, "can't be blank")
      end
    end
end
