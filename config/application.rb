require_relative "boot"

require "rails/all"

# Pedant::VERSION, before the gems load. See config/version.rb.
require_relative "version"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Pedant
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets middleware tasks])

    # Push tokens are taken out of the path before the request is logged.
    require_relative "../lib/middleware/push_token_filter"
    config.middleware.insert_before Rails::Rack::Logger, PushTokenFilter

    # The client's address (ADR 0027). Every request comes through Caddy, which
    # sets X-Forwarded-For to the client, then Thruster, which appends Docker's
    # gateway. remote_ip skips trusted proxies to reach the client.
    #
    # - With the spoofing check on, a request whose Client-IP header disagrees
    #   with X-Forwarded-For is a 500 from the request logger. With it off,
    #   X-Forwarded-For wins and a forged Client-IP is ignored.
    # - Rails trusts fc00::/7 as proxies, and Tailscale's IPv6 addresses are in
    #   it, so they'd be skipped and a forged Client-IP behind them believed.
    config.action_dispatch.ip_spoofing_check = false
    config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES.reject { |range| range.include?(IPAddr.new("fd7a:115c:a1e0::1")) }

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
