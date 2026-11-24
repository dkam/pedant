# Which commit a source's checkout was at when it was last synced, and whether
# it had local changes (ADR 0030, dkam/pedant#16). Nil when it isn't a git
# checkout.
class AddCommitToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :commit_sha, :string
    add_column :sources, :dirty, :boolean
  end
end
