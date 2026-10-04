class AddPasswordsToUsers < ActiveRecord::Migration[8.1]
  def change
    # A user signs in with either a password or an OIDC identity (ADR 0015).
    change_column_null :users, :oidc_issuer, true
    change_column_null :users, :oidc_sub, true
    add_column :users, :password_digest, :string

    # Copied into the session at sign-in. Rotating it ends every session, so a
    # password change or a console reset logs everyone out.
    add_column :users, :session_token, :string
  end
end
