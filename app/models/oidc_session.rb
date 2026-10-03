# Maps the provider's session id (`sid`) to ours, so a backchannel logout from
# the provider can end the matching session here. Ported from spool.
class OidcSession < ApplicationRecord
  belongs_to :user

  validates :oidc_sid, presence: true, uniqueness: true
  validates :session_id, :expires_at, presence: true

  scope :live, -> { where(expires_at: Time.current..) }

  def self.find_live(sid)
    live.find_by(oidc_sid: sid)
  end

  def self.cleanup_expired
    where(expires_at: ...Time.current).delete_all
  end

  # Expire rather than delete: a later request reads the row to discover its
  # session was revoked elsewhere, so it has to outlive the logout.
  def invalidate!
    update!(expires_at: 1.minute.ago)
  end
end
