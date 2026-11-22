require "test_helper"

# The theme is this browser's choice, kept in localStorage, so the server only
# renders the picker and the script that applies a stored choice before the
# first paint (ADR 0028).
class ThemeTest < ActionDispatch::IntegrationTest
  test "signed out, the page offers system, light and dark" do
    get login_url

    assert_response :success
    assert_theme_picker
  end

  test "signed in, the page offers system, light and dark" do
    create_password_owner
    sign_in_with_password

    get root_url

    assert_response :success
    assert_theme_picker
  end

  private
    def assert_theme_picker
      assert_select "meta[name=color-scheme][content='light dark']"
      assert_select "head script", text: /pedant:theme/
      assert_select "#theme[data-turbo-permanent][data-controller=theme]" do
        assert_select "button[data-theme-value-param]", 3
        %w[system light dark].each { |value| assert_select "button[data-theme-value-param=#{value}]" }
      end
    end
end
