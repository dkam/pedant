# frozen_string_literal: true

# Pedant's release version: SemVer, bumped by hand. Bumping it on main *is* the
# release. .github/workflows/build.yml publishes ghcr.io/dkam/pedant:vX.Y.Z when
# this file changes, and tags the commit. A pre-release (X.Y.Z-dev) publishes an
# image but never moves :latest or creates a tag.
#
# Lives in its own file, so build scripts can read it without booting Rails:
#   ruby -e "require './config/version'; puts Pedant::VERSION"
#
# This says which release; config/initializers/revision.rb says which commit.
module Pedant
  VERSION = "0.2.0-dev"
end
