# Someone who can sign in. There's no sign-up: the owner is created by setup
# (see Setup), and nobody else exists until there's a way to add them.
#
# Identity is the provider's issuer plus subject, never the email: a provider
# can change someone's email, and the same subject from a different provider
# is a different person (ADR 0009).
class User < ApplicationRecord
  has_many :oidc_sessions, dependent: :delete_all

  validates :oidc_issuer, :oidc_sub, presence: true
  validates :oidc_sub, uniqueness: { scope: :oidc_issuer }

  def self.identified_by(claims)
    find_by(oidc_issuer: claims["iss"], oidc_sub: claims["sub"])
  end

  # Keep what the provider says about them current, writing only on a change.
  def refresh_from(claims)
    update!(email: claims["email"].presence || email, name: claims["name"].presence || name)
  end

  def display_name
    name.presence || email.presence || oidc_sub
  end
end
