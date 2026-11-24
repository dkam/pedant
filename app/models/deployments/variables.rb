# The variables a compose file's ${NAME} is filled in from, as doco-cd fills
# them (Deploy-Settings.md): the deploy file's env_files in order, a later one
# overriding an earlier one and able to use what came before, then its
# environment, which overrides them all.
#
# Pedant never decrypts (ADR 0007), so what an encrypted file sets is unknown,
# and a reference to it is left as written. A SOPS dotenv file encrypts values,
# not keys, so its keys say what it sets. If they can't be seen, anything could
# have been overridden, so only what's set after it is known.
class Deployments::Variables
  UNKNOWN = Object.new.freeze
  # $$, ${NAME}, ${NAME:-default} and compose's other operators, or $NAME.
  REFERENCE = /\$(?:(?<escaped>\$)|\{(?<braced>[A-Za-z_]\w*)(?:(?<operator>:?[-?+])(?<argument>[^}]*))?\}|(?<bare>[A-Za-z_]\w*))/
  LINE = /\A\s*(?:export\s+)?(?<name>[A-Za-z_][\w.-]*)\s*=\s*(?<value>.*)\z/

  def initialize
    @values = {}
    @all_unknown = false
  end

  def add_plaintext(content)
    content.each_line(chomp: true) do |line|
      next if line.lstrip.start_with?("#")
      match = LINE.match(line) or next
      @values[match[:name]] = dotenv_value(match[:value])
    end
  end

  def add_encrypted(content)
    names = content.each_line(chomp: true).filter_map { |line| LINE.match(line)&.[](:name) }.reject { |name| name.start_with?("sops_") }
    if names.any?
      names.each { |name| @values[name] = UNKNOWN }
    else
      @values.clear
      @all_unknown = true
    end
  end

  def set(name, value)
    @values[name.to_s] = value.to_s
  end

  # The text with its references filled in, and whether every one could be.
  def fill(text)
    resolved = true
    filled = text.gsub(REFERENCE) do
      match = Regexp.last_match
      next "$" if match[:escaped]

      value = lookup(match[:braced] || match[:bare])
      if value.equal?(UNKNOWN)
        resolved = false
        next match[0]
      end

      argument = -> { fill(match[:argument]).tap { |_text, ok| resolved &&= ok }.first }
      set, present = !value.nil?, !value.to_s.empty?
      case match[:operator]
      when ":-" then present ? value : argument.call
      when "-" then set ? value : argument.call
      when ":+" then present ? argument.call : ""
      when "+" then set ? argument.call : ""
      else
        # Plain, or ${NAME:?message}, which compose refuses to deploy without.
        next value if match[:operator] == ":?" ? present : set
        resolved = false
        match[0]
      end
    end
    [ filled, resolved ]
  end

  private
    def lookup(name)
      @values.fetch(name) { @all_unknown ? UNKNOWN : nil }
    end

    # Single quotes are literal; double quotes take escapes, and like a bare
    # value can use the variables before them.
    def dotenv_value(raw)
      text = case raw
      when /\A'(?<inner>[^']*)'/ then return $~[:inner]
      when /\A"(?<inner>(?:[^"\\]|\\.)*)"/ then $~[:inner].gsub(/\\(.)/) { $1 == "n" ? "\n" : $1 }
      else raw.sub(/\s+#.*\z/, "").strip
      end
      filled, resolved = fill(text)
      resolved ? filled : UNKNOWN
    end
end
