namespace :pedant do
  desc "Print the setup code, if setup is open"
  task setup_code: :environment do
    abort "Setup is closed: a provider is configured and somebody has signed in." unless Setup.open?

    puts Setup.banner
  end

  desc "Clear the OIDC provider and reopen /setup (ADR 0011). Users are kept."
  task reset_oidc: :environment do
    OidcProvider.delete_all
    OidcSession.delete_all

    puts "OIDC settings cleared. Existing users sign back in once the provider is set up again."
    puts Setup.banner
  end
end
