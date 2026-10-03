class CreateUsersAndOidc < ActiveRecord::Migration[8.1]
  def change
    # The one provider people sign in with, entered in /setup (ADR 0011).
    create_table :oidc_providers do |t|
      t.string :issuer, null: false
      t.string :client_id, null: false
      t.string :client_secret, null: false
      t.string :name, null: false, default: "OIDC"
      t.timestamps
    end

    # Identity is the provider's issuer plus its subject (ADR 0009), never the
    # email, which the provider can change.
    create_table :users do |t|
      t.string :oidc_issuer, null: false
      t.string :oidc_sub, null: false
      t.string :email
      t.string :name
      t.timestamps
    end
    add_index :users, [ :oidc_issuer, :oidc_sub ], unique: true

    # Maps the provider's session id to ours, for backchannel logout.
    create_table :oidc_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :oidc_sid, null: false
      t.string :session_id, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :oidc_sessions, :oidc_sid, unique: true
    add_index :oidc_sessions, :expires_at
  end
end
