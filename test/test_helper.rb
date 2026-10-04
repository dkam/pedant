ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

# Tests never reach the network. Capybara's own server is local.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  private
    # A configured provider and a fake one answering for it.
    def configure_provider
      @provider = FakeOidcProvider.new.stub!
      OidcProvider.create!(@provider.provider_attributes)
    end

    def create_password_owner(password = "a long enough password", email: "dan@example.com")
      User.create!(email: email, password: password, password_confirmation: password)
    end

    def sign_in_with_password(password = "a long enough password", email: "dan@example.com")
      post login_url, params: { email: email, password: password }
    end

    # The whole login flow, as the browser would drive it: /login/start sends
    # us to the provider with a state, and the provider sends us back with it.
    def log_in(**claims)
      @provider.logs_in_as(**claims) if claims.any?
      get login_start_url
      state = Rack::Utils.parse_query(URI(response.location).query).fetch("state")
      get auth_callback_url, params: { code: "auth-code", state: state }
    end
end
