require "test_helper"
require "rake"

class PedantRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none? { |task| task.name.start_with?("pedant:") }
  end

  test "push_token prints a new token, the digest for monitors.yml, and the push URL" do
    output = run_task("pedant:push_token")

    token = output[%r{/api/push/([A-Za-z0-9_-]{32,})}, 1]
    assert token
    assert_includes output, "push: sha256:#{Digest::SHA256.hexdigest(token)}"
    assert_not_equal token, run_task("pedant:push_token")[%r{/api/push/([A-Za-z0-9_-]{32,})}, 1]
  end

  test "reset_password removes the password, signs out, and reopens setup" do
    owner = User.create!(email: "dan@example.com", password: "a long enough password", password_confirmation: "a long enough password")
    token = owner.session_token

    output = run_task("pedant:reset_password")

    owner.reload
    assert_nil owner.password_digest
    assert_not_equal token, owner.session_token
    assert Setup.open?
    assert_includes output, Setup.code
  end

  test "reset_oidc clears the provider, keeps the owner, signs out, and reopens setup" do
    OidcProvider.create!(FakeOidcProvider.new.stub!.provider_attributes)
    owner = User.create!(oidc_issuer: FakeOidcProvider::ISSUER, oidc_sub: "owner-sub")
    token = owner.session_token

    output = run_task("pedant:reset_oidc")

    assert_not OidcProvider.exists?
    assert_equal owner, User.sole
    assert_not_equal token, owner.reload.session_token
    assert Setup.open?
    assert_includes output, Setup.code
  end

  private
    def run_task(name)
      task = Rake::Task[name]
      task.reenable
      out, _err = capture_io { task.invoke }
      out
    end
end
