# frozen_string_literal: true

# The commit this build came from, so "which revision is running?" doesn't need
# guessing. Pedant reads this label on every other app, so it carries it too.
#
# The Dockerfile writes VERSION at build time from --build-arg GIT_SHA. Outside
# a container there's no such file, so in development fall back to asking git.
# A deployed container shouldn't shell out at boot, and it has the file anyway.
Rails.application.config.x.revision = begin
  version_file = Rails.root.join("VERSION")
  from_file = version_file.exist? ? version_file.read.strip.presence : nil

  from_git =
    if from_file.nil? && Rails.env.development?
      `git rev-parse --short HEAD 2>/dev/null`.strip.presence
    end

  from_file || from_git || ENV["GIT_SHA"].presence || "unknown"
end
