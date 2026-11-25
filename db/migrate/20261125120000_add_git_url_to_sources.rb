# A source can be a git URL and a branch that Pedant clones and fetches itself
# (ADR 0037), so a path is no longer required. An ssh source has its own deploy
# key, encrypted, and the host keys pinned when it was added.
class AddGitUrlToSources < ActiveRecord::Migration[8.1]
  def change
    change_column_null :sources, :path, true
    add_column :sources, :url, :string
    add_column :sources, :branch, :string
    add_column :sources, :deploy_key, :text
    add_column :sources, :deploy_public_key, :string
    add_column :sources, :host_keys, :text
  end
end
