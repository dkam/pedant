require "net/http"

# The one OIDC provider people sign in with. Entered in /setup and kept here,
# not in env variables (ADR 0011). The client secret is encrypted at rest and
# filtered from logs and inspect.
#
# Saving fetches the provider's discovery document, so a wrong URL is reported
# on the form rather than at the first login.
class OidcProvider < ApplicationRecord
  WELL_KNOWN = "/.well-known/openid-configuration".freeze
  REQUIRED_ENDPOINTS = %w[issuer authorization_endpoint token_endpoint jwks_uri].freeze
  TIMEOUT_SECONDS = 5

  encrypts :client_secret

  normalizes :issuer, with: ->(url) { url.strip.delete_suffix("/").delete_suffix(WELL_KNOWN).delete_suffix("/") }

  validates :issuer, :client_id, :client_secret, :name, presence: true
  validate :only_one, on: :create
  validate :issuer_is_https
  validate :discoverable, if: -> { issuer.present? && errors[:issuer].none? }

  def self.current
    first
  end

  def self.configured?
    exists?
  end

  # Fetched once per instance; a request builds a fresh one.
  def discovery
    @discovery ||= fetch_json(issuer + WELL_KNOWN)
  end

  # The issuer the provider declares, which is what ID tokens carry. It can
  # differ from the URL entered (a path suffix, a proxy), so prefer it.
  def expected_issuer
    discovery["issuer"].presence || issuer
  end

  def jwks
    @jwks ||= JWT::JWK::Set.new(fetch_json(discovery.fetch("jwks_uri")).fetch("keys"))
  end

  def client(redirect_uri:)
    OpenIDConnect::Client.new(
      identifier: client_id,
      secret: client_secret,
      redirect_uri: redirect_uri,
      authorization_endpoint: discovery.fetch("authorization_endpoint"),
      token_endpoint: discovery.fetch("token_endpoint"),
      userinfo_endpoint: discovery["userinfo_endpoint"]
    )
  end

  private
    def only_one
      errors.add(:base, "There is already a provider") if OidcProvider.exists?
    end

    # The client secret travels to the token endpoint, so plain http only
    # where it never leaves the machine.
    def issuer_is_https
      uri = URI.parse(issuer.to_s)
      return if uri.scheme == "https"
      return if uri.scheme == "http" && %w[localhost 127.0.0.1 ::1].include?(uri.host)

      errors.add(:issuer, "must be an https URL")
    rescue URI::InvalidURIError
      errors.add(:issuer, "isn't a URL")
    end

    def discoverable
      @discovery = nil
      missing = REQUIRED_ENDPOINTS.reject { |key| discovery[key].present? }
      errors.add(:issuer, "has a discovery document without #{missing.to_sentence}") if missing.any?
    rescue StandardError => e
      errors.add(:issuer, "didn't return a discovery document at #{issuer + WELL_KNOWN} (#{e.message})")
    end

    def fetch_json(url)
      uri = URI.parse(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) { |http| http.get(uri.request_uri) }
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
end
