require "test_helper"

# build.yml reads Pedant::VERSION to tag the image, and decides whether to move
# :latest by looking for a "-" (pre-release). A malformed version would publish
# a nonsense tag, so pin the shape here.
class VersionTest < ActiveSupport::TestCase
  test "version is SemVer, optionally with a pre-release suffix" do
    assert_match(/\A\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?\z/, Pedant::VERSION)
  end

  test "version is readable without booting Rails, as build.yml does" do
    out = `ruby -e "require './config/version'; puts Pedant::VERSION"`.strip
    assert_equal Pedant::VERSION, out
  end

  test "revision is set" do
    assert Rails.configuration.x.revision.present?
  end
end
