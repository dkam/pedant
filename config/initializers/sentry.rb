# Pedant's own errors go to Splat over the Sentry protocol (ADR 0035): an
# exception in a request, in a job, or in Solid Queue's own threads. Only
# when SENTRY_DSN is set, so development and test send nothing.
#
# Pedant holds credentials that spool and clinch don't: push tokens in URL
# paths, API tokens in headers, and alert channels' secrets. So it sends the
# least it can. The tests in test/integration/error_tracking_test.rb check
# that no credential reaches an event, and that no site Pedant checks hears
# from Sentry.
module Pedant
  module ErrorTracking
    def self.configure(config, dsn:)
      config.dsn = dsn
      config.environment = Rails.env

      # "0.9.0+b74ec04…": the release, and the commit it was built from.
      config.release = "#{Pedant::VERSION}+#{Rails.application.config.x.revision}"

      # Sentry's Net::HTTP patch adds sentry-trace and baggage headers to every
      # outgoing request, even with tracing off. Pedant's requests go to the
      # sites it checks and to ntfy, and the baggage carries the release, the
      # environment and the DSN's public key: the versions that ADR 0029 keeps
      # off the public website. The patch also records outgoing URLs, and an
      # ntfy topic's URL is its secret. So the patch is off, and so is
      # propagation, in case another patch would add the headers.
      config.enabled_patches.delete(:http)
      config.propagate_traces = false
      config.trace_propagation_targets = []

      # No breadcrumbs: SQL and outgoing requests are where a secret would
      # be. A stack trace and the request line are enough to find a bug in an
      # app this size.
      config.breadcrumbs_logger = []

      # What sentry-ruby sends without send_default_pii, set out here because
      # 7.x deprecates that switch. No IP, cookies, query strings or bodies.
      # Headers named like auth, token, session or cookie are always filtered,
      # and so are the ones that carry a client's address.
      data = config.data_collection
      data.user_info = false
      data.cookies = false
      data.http_headers.request.terms = Sentry::DataCollection::PII_HEADER_SNIPPETS
      data.http_headers.response.terms = Sentry::DataCollection::PII_HEADER_SNIPPETS
      data.http_bodies = []
      data.url_query_params = false
      data.database_query_data = false
      data.queues = false

      # Release health is a Sentry feature Splat doesn't have. Left on, each
      # process sends an envelope a minute that Splat drops.
      config.auto_session_tracking = false

      # Errors Rails reports itself, including Solid Queue's: a dispatcher or
      # scheduler thread that fails never raises into a request or a job.
      config.rails.register_error_subscriber = true
    end
  end
end

Sentry.init { |config| Pedant::ErrorTracking.configure(config, dsn: ENV["SENTRY_DSN"]) } if ENV["SENTRY_DSN"].present?
