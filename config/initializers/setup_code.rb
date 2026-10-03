# While setup is open, booting the server prints the setup code: the only
# credential that exists before the owner does. See Setup.
#
# Only the server, not every boot: rake tasks such as assets:precompile run in
# the image build, where there's no database to ask whether setup is open.
# `bin/rails pedant:setup_code` prints it on demand.
Rails.application.config.after_initialize do
  Setup.announce if defined?(Rails::Server)
end
