class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    # Bearer tokens for /mcp (ADR 0025), one per client. Only a SHA-256 digest
    # is stored: the token is shown once, and a copy of the database holds
    # nothing that can be presented.
    create_table :api_tokens do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :api_tokens, :token_digest, unique: true
  end
end
