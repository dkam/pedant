# Active Record encryption keys, derived from secret_key_base as clinch does,
# so there's no second set of keys to keep. The one encrypted column is the
# OIDC client secret (ADR 0011). Changing secret_key_base makes it unreadable;
# `bin/rails pedant:reset_oidc` then reopens /setup to enter it again.
Rails.application.configure do
  generator = Rails.application.key_generator

  config.active_record.encryption.primary_key = generator.generate_key("pedant/active record encryption primary", 32)
  config.active_record.encryption.deterministic_key = generator.generate_key("pedant/active record encryption deterministic", 32)
  config.active_record.encryption.key_derivation_salt = generator.generate_key("pedant/active record encryption salt", 32)
end
