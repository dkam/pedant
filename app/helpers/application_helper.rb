module ApplicationHelper
  # "Pedant 0.9.0 (b74ec04) · Rails 8.1.4.1 · Ruby 4.0.10", for the signed-in
  # owner's footer only (ADR 0034). The revision is left out where it isn't
  # known, as in tests.
  def versions_line
    revision = Rails.application.config.x.revision
    pedant = [ "Pedant #{Pedant::VERSION}", ("(#{revision.first(7)})" unless revision == "unknown") ].compact.join(" ")
    [ pedant, "Rails #{Rails.version}", "Ruby #{RUBY_VERSION}" ].join(" · ")
  end
end
