# Receives push monitors' reports, on Kuma's URL shape (ADR 0012):
# /api/push/<token>?status=up|down&msg=…&ping=…
#
# The token is the credential. It arrives through PushTokenFilter, so it's
# never in the logged path; the monitor is found by the token's SHA-256
# digest, which is all monitors.yml holds. No session or CSRF: the callers are
# curl lines in scripts.
class PushesController < ActionController::API
  # Per token, in this process. Pedant is one process (ADR 0008).
  RATE_LIMITS = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 30, within: 1.minute, by: -> { token_digest }, store: RATE_LIMITS,
    with: -> { render json: { ok: false, msg: "Too many pushes" }, status: :too_many_requests }

  def create
    monitor = Uptime::Monitor.active.find_by(kind: "push", target: token_digest)
    return render json: { ok: false, msg: "Monitor not found or not active." }, status: :not_found unless monitor

    # As in Kuma: no status is up, and anything but up is down.
    status = params.fetch(:status, "up") == "up" ? "up" : "down"
    monitor.record_push(Uptime::Result.new(status: status, message: params[:msg].presence&.truncate(255), latency_ms: ping))
    Turbo::StreamsChannel.broadcast_refresh_to(:monitors)

    render json: { ok: true }
  end

  private
    def token_digest
      @token_digest ||= "sha256:#{Digest::SHA256.hexdigest(request.env[PushTokenFilter::ENV_KEY].to_s)}"
    end

    def ping
      Float(params[:ping]).round if params[:ping].present?
    rescue ArgumentError
      nil
    end
end
