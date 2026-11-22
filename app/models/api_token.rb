# A bearer token for the read-only MCP server (ADR 0025). The owner makes one
# per client on the settings page, and it's shown once: only its SHA-256
# digest is stored, as with push tokens. It never expires; revoking it is how
# it stops.
class ApiToken < ApplicationRecord
  # Recognisable in a config file or a paste. The rest is 43 base58
  # characters, about 250 bits.
  PREFIX = "pedant_"

  # last_used_at answers "is anything still using this?". It isn't worth a
  # write on every call.
  TOUCH_AFTER = 5.minutes

  validates :name, presence: true, length: { maximum: 100 }
  validates :token_digest, presence: true, uniqueness: true

  # Makes a token and returns [record, token]. The token isn't kept, so the
  # caller shows it once and forgets it.
  def self.issue!(name:)
    token = PREFIX + SecureRandom.base58(43)
    [ create!(name: name, token_digest: digest(token)), token ]
  end

  # The token for a presented bearer value, or nil. A caller that isn't let in
  # is told nothing about why.
  def self.authenticate(presented)
    return if presented.blank?

    token = find_by(token_digest: digest(presented))
    token&.touch_last_used!
    token
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)

  def touch_last_used!(now = Time.current)
    return if last_used_at && last_used_at > now - TOUCH_AFTER

    update_column(:last_used_at, now)
  end
end
