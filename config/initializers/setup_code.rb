# While setup is open, every boot prints the setup code: the only credential
# that exists before the owner does. See Setup.
#
# after_initialize rather than at load: the database has to be there to know
# whether setup is open, and Setup.announce stays quiet if it isn't.
Rails.application.config.after_initialize do
  Setup.announce unless Rails.env.test?
end
