require "open3"

# Read-only git on a source's checkout: which commit it's at, whether it has
# local changes, and the files at a commit. The deployments side reads at the
# commit a sync recorded, never the working tree, so a hand edit on grab01 isn't
# taken as intent (ADR 0032). Reading through git also keeps every path inside
# the repo: a `../` in a deploy file can't reach anything outside it.
class Source::Checkout
  # The checkout is the owner's own, but on grab01 it belongs to another user
  # and is mounted read-only, so git would refuse it as "dubious ownership" and
  # couldn't take its optional index lock. Pedant only reads it. fsmonitor off,
  # so a status never starts a daemon.
  GIT = %w[ git --no-optional-locks -c safe.directory=* -c core.fsmonitor=false ].freeze

  def initialize(path)
    @path = path
  end

  # The commit HEAD is at. Nil when it isn't a git checkout, or git can't read it.
  def head = git("rev-parse", "--verify", "HEAD")&.strip

  # Whether anything differs from HEAD, tracked or not. Nil if git can't tell.
  def dirty?
    status = git("status", "--porcelain")
    status.present? unless status.nil?
  end

  # Every file in the commit's tree, as paths from the top of the repo. Nil if
  # the commit isn't in the checkout.
  def files(commit)
    git("ls-tree", "-r", "-z", "--name-only", commit)&.split("\0")
  end

  # A file's content at the commit, or nil if it isn't there.
  def read(commit, file)
    git("cat-file", "blob", "#{commit}:#{file}")
  end

  private
    def git(*args)
      output, _errors, status = Open3.capture3(*GIT, "-C", @path, *args)
      output if status.success?
    rescue SystemCallError
      nil
    end
end
