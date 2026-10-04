# A push URL carries its token in the path (/api/push/<token>, Kuma's shape),
# and the token is the credential (ADR 0012). Rails logs the path before any
# controller runs, so this takes the token out first: the path becomes
# /api/push/[FILTERED] and PushesController reads the token from the env.
class PushTokenFilter
  PREFIX = "/api/push/"
  ENV_KEY = "pedant.push_token"

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"].to_s
    if path.start_with?(PREFIX)
      token, rest = path.delete_prefix(PREFIX).split("/", 2)
      env[ENV_KEY] = Rack::Utils.unescape_path(token.to_s)
      env["PATH_INFO"] = [ "#{PREFIX}[FILTERED]", rest ].compact.join("/")
      env["REQUEST_URI"] &&= env["REQUEST_URI"].sub(%r{#{Regexp.escape(PREFIX)}[^/?]*}, "#{PREFIX}[FILTERED]")
    end
    @app.call(env)
  end
end
