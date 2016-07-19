require 'set'
require 'strscan'

# Super neat string interpolation library for replacing placeholders in strings, kinda like how
# `git log --pretty=format:'%H %s'` works.
#
# You create an interpolator by doing something like:
#
#   i = StringInterpolator.new
#
# To add placeholders, use the add method:
#
#   i.add(n: 'Bob', w: 'nice') # keys can also be strings
#
# And now you're ready to actually use your interpolator:
#
#   result = i.interpolate("Hello, %n. The weather's %w today") # returns "Hello, Bob. The weather's nice today"
#
# You can mark placeholders as being required:
#
#   i = StringInterpolator.new
#   i.add(n: 'Bob', w: 'nice')
#   i.require(:n)
#   i.interpolate("Hello, the weather's %w today") # this raises an exception...
#   i.interpolate("Hello, %n.") # ...but this works
#
# Both add and require return the interpolator itself, so you can chain them together:
#
#   result = StringInterpolator.new.add(n: 'Bob').require(:n).interpolate('Hello, %n.')
#
# Interpolators use % as the character that signals the start of a placeholder by default. If you'd like to use a
# different character as the herald, you can do that with:
#
#   i = StringInterpolator.new('$')
#   i.add(n: 'Bob', w: 'nice')
#   i.interpolate("Hello, $n. The weather's $w today")
#
# Heralds can be multi-character strings, if you like:
#
#   i = StringInterpolator.new('!!!')
#   i.add(n: 'Bob', w: 'nice')
#   i.interpolate("Hello, !!!n. The weather's !!!w today")
#
# Placeholders can also be multi-character strings:
#
#   i = StringInterpolator.new
#   i.add(name: 'Bob', weather: 'nice')
#   i.require(:name)
#   i.interpolate("Hello, %name. The weather's %weather today")
#
# Two percent signs (or two of whatever herald you've chosen) in a row can be used to insert a literal copy of the
# herald:
#
#   i = StringInterpolator.new
#   i.add(n: 'Bob')
#   i.interpolate("Hello, %n. Humidity's right about 60%% today") # "Hello, Bob. Humidity's right about 60% today"
#
# You can turn off the double herald literal mechanism and add your own, if you like:
#
#   i = StringInterpolator.new(literal: false)
#   i.add(percent: '%')
#   i.interpolate('%percent') # '%'
#   i.interpolate('%%') # raises an exception
#
# Ambiguous placeholders cause an exception to be raised:
#
#   i = StringInterpolator.new
#   i.add(foo: 'one', foobar: 'two') # raises an exception - should "%foobarbaz" be "onebarbaz" or "twobaz"?
#
# And that's about it.
#
# Internally the whole thing is implemented using a prefix tree of all of the placeholders that have been added and a
# scanning parser that descends through the tree whenever it hits a herald to find a match. It's therefore super fast
# even on long strings and with lots of placeholders, and it doesn't get confused by things like '%%foo' or '%%%foo'
# (which should respectively output '%foo' and '%bar' if foo is a placeholder for 'bar', but a lot of other
# interpolation libraries that boil down to a bunch of `gsub`s screw one of those two up). The only downside of the
# current implementation is that it recurses for each character in a placeholder, so placeholders are limited to a few
# hundred characters in length (but their replacements aren't). I'll rewrite it as a bunch of loops if that ever
# actually becomes a problem for anyone (but I'll probably question your sanity for using such long placeholders
# first).
class Interpolator
  # Create a new interpolator that uses the specified herald, or '%' if one isn't specified.
  def initialize(herald = '%', literal: true)
    @herald = herald
    # Yes, we're using regexes, but only because StringScanner's pretty dang fast. Don't you dare think I'm naive
    # enough to just gsub all the substitutions or something like that.
    @escaped_herald = Regexp.escape(herald)
    @required = Set.new
    @tree = nil # instead of {} because that preserves the generality of trees and replacements being the same thing.
    # This lets someone do something like Interpolator.new(literal: false).add('' => 'foo').interpolate('a % b')
    # and get back 'a foo b', which is not a thing I expect anyone to actually do, but no reason to stop them from
    # doing it if they really want.

    # Allow two heralds in a row to be used to insert a literal copy of the herald unless we've been told not to
    add(herald => herald) if literal
  end

  # Add new substitutions to this interpolator. The keys of the specified dictionary will be used as the placeholders
  # and the values will be used as the replacements. Keys can be either strings or symbols.
  #
  # Duplicate keys and keys which are prefixes of other keys will cause an exception to be thrown.
  def add(substitutions)
    substitutions.each do |key, replacement|
      # Turn the substitution into a prefix tree. This takes a key like 'foo' and a value like 'bar' and turns it
      # into {'f' => {'o' => {'o' => 'bar'}}}. Also stringify the key in case it's a symbol.
      tree = key.to_s.reverse.chars.reduce(replacement) { |tree, char| {char => tree} }
      # Then merge it with our current tree. Not as efficient as direct insertion, but algorithmically simpler, and
      # I'll eat my hat when someone uses this in a practical application where this bit is the bottleneck.
      @tree = merge(@tree, tree)
    end

    # yay chaining!
    self
  end

  # Mark the specified placeholders as required. Interpolation will fail if the string to be interpolated does not
  # include all placeholders that have been marked as required.
  def require(*placeholders)
    # Stringify keys in case they're symbols
    @required.merge(placeholders.map(&:to_s))

    # yay more chaining!
    self
  end

  # Interpolate the specified string, replacing placeholders that have been added to this interpolator with their
  # replacements.
  def interpolate(string)
    scanner = StringScanner.new(string)
    result = ''
    unused = @required.dup

    until scanner.eos?
      # See if there's a herald at our current position
      if scanner.scan(/#{@escaped_herald}/)
        # There is, so parse a substitution where we're at, mark the key as having been used, and output the
        # replacement.
        key, replacement = parse(scanner)
        unused.delete(key)
        result << replacement
      else
        # No heralds here. Grab everything up to the next herald or end-of-string and output it. The fact that both
        # a group and a negative lookahead assertion are needed to get this right really makes me wonder if I
        # shouldn't just loop through the string character by character after all... And no, I'm not changing it to
        # a negative character class because this was literally the only line that needed to be changed to allow
        # multi-character heralds to work. Now someone go use them already.
        result << scanner.scan(/(?:(?!#{@escaped_herald}).)+/)
      end
    end

    # Blow up if any required interpolations weren't used
    unless unused.empty?
      unused_description = unused.map do |placeholder|
        "#{@herald}#{placeholder}"
      end.join(', ')

      raise Error.new("required placeholders were unused: #{unused_description}")
    end

    result
  end

  private

  # Merge two trees and return the result. Neither tree is modified in the process. Duplicate keys and keys that
  # give rise to ambiguities will result in much yelling and exceptions.
  def merge(first, second, prefix = '')
    if first.nil?
      # Probably because we're merging hashes and the first one didn't have a value for this key. Use the other one.
      second
    elsif second.nil?
      # Ditto
      first
    elsif first.is_a?(Hash) && second.is_a?(Hash)
      # Both are hashes, so recursively merge their values
      first.merge(second) { |k, left, right| merge(left, right, prefix + k) }
    elsif first.is_a?(Hash) || second.is_a?(Hash)
      # One of them's a hash and the other's a substitution, which means that there's a substitution that's a prefix
      # of another one. We'll construct arbitrary placeholders from the two side because we like giving users
      # informative error messages (and note that only one side will be a tree, but our algorithm's nice and general
      # and will give us the right answer for both sides), then raise an exception that includes them.
      first_key = prefix + pick_key(first)
      second_key = prefix + pick_key(second)
      raise Error.new("conflicting placeholders: #{@herald}#{first_key} and #{@herald}#{second_key}")
    else
      # They're both substitutions for the same prefix, so we've got duplicates.
      raise Error.new("duplicate placeholder: #{@herald}#{prefix}")
    end
  end

  # Pick an arbitrary key out of the specified tree. Smart enough to hand back an empty string when given a
  # substitution instead of a tree. Not used in your typical day-to-day operation, only used to produce more
  # informative error messages when the user tries to add conflicting substitutions.
  def pick_key(tree)
    return '' unless tree.is_a? Hash
    key = tree.keys.first
    key + pick_key(tree[key])
  end

  # Parse a single placeholder from the given scanner. The key and the replacement will be returned. If there's no
  # such substitution, an exception will be raised and the scanner will be left at an arbitrary position, so don't
  # try to use it again if that happens. An exception will also be raised if the placeholder runs off the edge of
  # the string.
  def parse(scanner, tree = @tree, prefix = '')
    if tree.is_a? Hash
      # Still more levels down the tree to go before we find the placeholder they're looking for, so grab a character
      # from the scanner...
      char = scanner.getch
      # ...raise if we just hit the end of the string...
      raise Error.new("incomplete placeholder at end of string: #{@herald}#{prefix}") unless char
      # ...and if we didn't, look the character up in the tree and recurse.
      parse(scanner, tree[char], prefix + char)
    elsif tree.nil?
      # Ran off the edge of the tree, so we didn't know about the placeholder we were given.
      raise Error.new("invalid placeholder: #{@herald}#{prefix}")
    else
      # Found a replacement! Return it and the key we built up.
      [prefix, tree]
    end
  end

  class Error < Exception
  end
end
