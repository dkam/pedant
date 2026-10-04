namespace :pedant do
  desc "Print the setup code, if setup is open"
  task setup_code: :environment do
    abort "Setup is closed: the owner can sign in." unless Setup.open?

    puts Setup.banner
  end

  desc "Remove the owner's password and sign them out; without OIDC this reopens /setup (ADR 0015)"
  task reset_password: :environment do
    users = User.with_password
    abort "No user has a password." if users.none?

    users.find_each(&:reset_password!)
    puts "Password removed, and every session signed out."
    puts Setup.open? ? Setup.banner : "OIDC is in use, so setup stays closed."
  end

  desc "Clear the OIDC provider and reopen /setup (ADR 0011). Users are kept."
  task reset_oidc: :environment do
    OidcProvider.delete_all
    OidcSession.delete_all
    User.find_each(&:rotate_session_token!)

    puts "OIDC settings cleared, and every session signed out. The owner is kept:"
    puts "sign back in with the same identity, or choose a password at setup."
    puts Setup.banner if Setup.open?
  end
end
