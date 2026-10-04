# How the owner signs in: a password or OIDC, never both (ADR 0015).
#
# - :oidc once a provider is configured, unless it was saved while switching
#   from a password and no identity has been linked yet. Until then the
#   password keeps working, so an abandoned switch can't lock the owner out.
# - :password while a user has one.
# - nil before setup, or after a console reset.
module SignInMethod
  def self.current
    provider = OidcProvider.configured?
    password = User.with_password.exists?

    if provider && (User.with_oidc.exists? || !password)
      :oidc
    elsif password
      :password
    end
  end

  def self.password? = current == :password
  def self.oidc? = current == :oidc
end
