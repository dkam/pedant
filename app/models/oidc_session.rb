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

  # Records a login's mapping, taking over the sid's old row if it has one.
  # The provider keeps one sid for as long as you're signed in there, so a
  # login after the mapping expired, or after a backchannel logout ended it,
  # brings the same sid back. It has just come with a verified ID token, so
  # the provider holds it live. A second row would fail uniqueness and leave
  # the login untracked, which logs you straight back out (as splat did on
  # 2026-11-01).
  def self.track_login(user:, sid:, session_id:, expires_in: 24.hours)
    mapping = find_or_initialize_by(oidc_sid: sid)
    mapping.update!(user: user, session_id: session_id, expires_at: expires_in.from_now)
    mapping
  rescue ActiveRecord::RecordNotUnique
    # A concurrent login for the same sid inserted first; take its row over.
    retry
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
