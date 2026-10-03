# Claiming an empty instance, ported from kith. Before anybody can sign in
# there's nobody to vouch for the first person, so while setup is open Pedant
# prints a code to the server's console and /setup accepts it. Being able to
# read that console is the only credential that exists before the owner does
# (ADR 0009).
#
# The code is derived from secret_key_base rather than stored, so every
# process agrees on it and it's never written down. Setup is open while
# there's no provider or nobody has signed in; `bin/rails pedant:reset_oidc`
# reopens it by clearing the provider (ADR 0011).
class Setup
  # No 0/O/1/I: this gets read off a terminal and typed. 32 divides 256
  # evenly, so folding a random byte into it stays uniform.
  ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ".freeze
  LENGTH = 12
  GROUP = 4

  # How long a correct code lets that browser claim an identity. Long enough
  # to sign in at the provider, short enough that it isn't a standing pass.
  CLAIM_WINDOW = 15.minutes

  class << self
    def open?
      !OidcProvider.configured? || !User.exists?
    end

    def code
      @code ||= Rails.application.key_generator.generate_key("pedant/setup code", LENGTH)
        .each_byte.map { |byte| ALPHABET[byte % ALPHABET.size] }.join
        .scan(/.{#{GROUP}}/).join("-")
    end

    # Generous about how it was typed (case, spaces, the dashes we printed)
    # and constant-time about whether it was right.
    def correct?(given)
      ActiveSupport::SecurityUtils.secure_compare(normalise(given), normalise(code))
    end

    # Printed at boot while setup is open.
    def announce(io = $stdout)
      io.puts banner if open?
    rescue ActiveRecord::ActiveRecordError
      # No database yet: bin/setup is still running, and it will boot again.
    end

    def banner
      rule = "─" * 52

      <<~BANNER

        #{rule}
          Pedant isn't set up yet.

          Open /setup and enter this code:

              #{code}

          It's printed only while setup is open.
        #{rule}

      BANNER
    end

    private
      def normalise(given)
        given.to_s.upcase.gsub(/[^A-Z0-9]/, "")
      end
  end
end
