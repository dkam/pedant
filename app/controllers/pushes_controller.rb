# Receives push monitors' reports, on Kuma's URL shape (ADR 0012):
# /api/push/<token>?status=up|down&msg=…&ping=…, plus Pedant's own
# value=… (judged against the limits in monitors.yml) and status=start (the
# start of a run). See Uptime::Monitor::Push. The dashboards refresh on the
# scheduler's next tick (Uptime::ScheduleChecksJob).
#
# The token is the credential. It arrives through PushTokenFilter, so it's
# never in the logged path; the monitor is found by the token's SHA-256
# digest, which is all monitors.yml holds. No session or CSRF: the callers are
# curl lines in scripts.
#
# A monitor takes pushes only from the tailnet, or from what its from: says
# (ADR 0027). Caddy passes the client's address in X-Forwarded-For, and
# remote_ip reads it. A push from anywhere else gets the unknown token's 404,
# so it doesn't learn that the token is real.
class PushesController < ActionController::API
  # Per token and address, in this process. Pedant is one process (ADR 0008).
  # Keyed by address too, so pushes refused from elsewhere can't use up the
  # real caller's allowance.
  RATE_LIMITS = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 30, within: 1.minute, by: -> { "#{token_digest} #{request.remote_ip}" }, store: RATE_LIMITS,
    with: -> { render json: { ok: false, msg: "Too many pushes" }, status: :too_many_requests }

  def create
    monitor = Uptime::Monitor.active.find_by(kind: "push", target: token_digest)
    return not_found unless monitor&.accepts_push_from?(request.remote_ip)

    if params[:status] == "start"
      monitor.start_run!
    else
      # As in Kuma: no status is up, and anything but up is down.
      status = params.fetch(:status, "up") == "up" ? "up" : "down"
      monitor.record_push monitor.push_result(status: status, value: params[:value], message: params[:msg].presence&.truncate(255), latency_ms: ping)
    end

    render json: { ok: true }
  end

  private
    def not_found
      render json: { ok: false, msg: "Monitor not found or not active." }, status: :not_found
    end

    def token_digest
      @token_digest ||= "sha256:#{Digest::SHA256.hexdigest(request.env[PushTokenFilter::ENV_KEY].to_s)}"
    end

    def ping
      Float(params[:ping]).round if params[:ping].present?
    rescue ArgumentError
      nil
    end
end
