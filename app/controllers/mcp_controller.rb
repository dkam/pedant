# The HTTP edge of the read-only MCP server (ADR 0025): check the bearer
# token, hand the JSON-RPC frame to the `mcp` gem, return its answer. The
# tools are in app/mcp.
#
# ActionController::API, not ApplicationController: the token is the only way
# in. With no session, a signed-in browser can't reach this by accident.
#
# Not the gem's StreamableHTTPTransport, for spool's reason: with no events
# to stream, it would add per-session state and Host/Origin allow-lists (a 403
# waiting to happen behind Caddy). handle_json is the whole protocol.
#
# The token travels only in the Authorization header, which Rails doesn't log.
class McpController < ActionController::API
  # /mcp is on the internet. Guessing a ~250-bit token is hopeless, but an
  # address that keeps getting refused is turned away for a while, so noise
  # costs it a 429 rather than a token lookup each time. Counted in this
  # process, as pushes are: Pedant is one process (ADR 0008). Behind Caddy,
  # remote_ip is the client's, from X-Forwarded-For.
  REFUSALS = ActiveSupport::Cache::MemoryStore.new
  MAX_REFUSALS = 20
  REFUSAL_WINDOW = 10.minutes

  before_action :turn_away_after_refusals, :authenticate, only: :create

  def create
    answer = PedantMcp.server.handle_json(request.raw_post)

    # nil is a notification: there's nothing to answer, and answering anyway
    # breaks the protocol.
    answer.nil? ? head(:accepted) : render(json: answer)
  end

  # A Streamable HTTP client may open a GET for server-sent events, and
  # DELETE its session on the way out. There are neither here, and 405 is what
  # the spec says to answer.
  def method_not_allowed
    response.headers["Allow"] = "POST"
    head :method_not_allowed
  end

  private
    def turn_away_after_refusals
      return if REFUSALS.read(refusal_key).to_i < MAX_REFUSALS

      response.headers["Retry-After"] = REFUSAL_WINDOW.to_i.to_s
      rpc_error :too_many_requests, "Too many refused requests from this address. Try again in #{REFUSAL_WINDOW.inspect}."
    end

    def authenticate
      return if ApiToken.authenticate(bearer_token)

      REFUSALS.increment(refusal_key, 1, expires_in: REFUSAL_WINDOW)
      # A client shows this to its human, so it says where tokens come from,
      # and nothing about why this one failed.
      response.headers["WWW-Authenticate"] = %(Bearer realm="Pedant")
      rpc_error :unauthorized, "Unauthorized: missing, unknown or revoked token. Make one in Pedant's settings, at #{settings_url}."
    end

    def bearer_token
      request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1]
    end

    def refusal_key = "refusals:#{request.remote_ip}"

    def rpc_error(status, message)
      render status: status, json: { jsonrpc: "2.0", id: nil, error: { code: -32001, message: message } }
    end
end
