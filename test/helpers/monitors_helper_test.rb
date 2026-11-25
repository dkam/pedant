require "test_helper"

class MonitorsHelperTest < ActionView::TestCase
  # A push interval of 31d was "1 month, 13 hours, 30 minutes, and 54
  # seconds": ActiveSupport's month is 2,629,746 seconds (#18).
  test "intervals are told in days at most, as monitors.yml writes them" do
    assert_equal "31 days", seconds_in_words(31 * 86_400)
    assert_equal "7 days", seconds_in_words(7 * 86_400)
    assert_equal "1 day and 30 minutes", seconds_in_words(86_400 + 1800)
    assert_equal "10 minutes", seconds_in_words(600)
  end
end
