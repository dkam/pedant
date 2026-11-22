require "test_helper"

# Dark mode works by giving each colour role a light and a dark value in
# app/assets/tailwind/application.css (ADR 0028). A palette colour written
# straight into a view, such as text-stone-600, is the same in both themes,
# so it would be the one thing left unreadable in dark mode.
class ColourRolesTest < ActiveSupport::TestCase
  PALETTE = %w[slate gray zinc neutral stone red orange amber yellow lime green emerald teal cyan sky blue indigo violet purple fuchsia pink rose white black].join("|")
  PROPERTIES = %w[bg text border divide ring outline stroke fill decoration placeholder accent caret shadow from via to].join("|")
  PALETTE_CLASS = /(?<![\w-])(?:[\w-]+:)*(?:#{PROPERTIES})-(?:#{PALETTE})(?:-\d{2,3})?(?:\/\d+)?(?![\w-])/

  test "views, helpers and controllers use colour roles, not palette colours" do
    files = Dir[Rails.root.join("app/{views,helpers,javascript}/**/*.{erb,rb,js}")]
    found = files.flat_map do |file|
      File.readlines(file).each_with_index.flat_map do |line, index|
        line.scan(PALETTE_CLASS).map { |match| "#{Pathname(file).relative_path_from(Rails.root)}:#{index + 1} #{match}" }
      end
    end

    assert_empty found, "Use a colour role (text-ink, bg-surface, text-bad, …) from app/assets/tailwind/application.css, so dark mode covers it"
  end
end
