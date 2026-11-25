require "test_helper"

# A signed-in owner sees which Pedant, Rails and Ruby are running, at the foot
# of every page. Signed out it's left off, because pedant.booko.info is public
# and exact versions tell anyone which advisories to try (ADRs 0029, 0034).
class VersionsFooterTest < ActionDispatch::IntegrationTest
  test "signed in, every page says which Pedant, Rails and Ruby it runs" do
    create_password_owner
    sign_in_with_password

    [ root_url, alerts_url, settings_url ].each do |url|
      get url

      assert_select "footer[data-versions]", 1
      assert_select "footer[data-versions]", text: /Pedant #{Regexp.escape(Pedant::VERSION)}/
      assert_select "footer[data-versions]", text: /Rails #{Regexp.escape(Rails.version)}/
      assert_select "footer[data-versions]", text: /Ruby #{Regexp.escape(RUBY_VERSION)}/
    end
  end

  test "a known revision is shown short, beside Pedant's version" do
    create_password_owner
    sign_in_with_password
    revision = Rails.application.config.x.revision
    Rails.application.config.x.revision = "b74ec04c2b9f1e0a3d6c8e7f5a4b3c2d1e0f9a8b"

    get root_url

    assert_select "footer[data-versions]", text: /Pedant #{Regexp.escape(Pedant::VERSION)} \(b74ec04\) · Rails/
  ensure
    Rails.application.config.x.revision = revision
  end

  test "signed out, no page names a version" do
    get login_url
    assert_no_versions

    create_password_owner
    get root_url
    follow_redirect!
    assert_no_versions
  end

  private
    def assert_no_versions
      assert_response :success
      assert_select "footer[data-versions]", 0
      assert_no_match(/Rails #{Regexp.escape(Rails.version)}|Ruby #{Regexp.escape(RUBY_VERSION)}/, response.body)
    end
end
