Super neat string interpolation library for replacing placeholders in strings, kinda like how
`git log --pretty=format:'%H %s'` works.

You create an interpolator by doing something like:

    i = StringInterpolator.new

To add placeholders, use the add method:

    i.add(n: 'Bob', w: 'nice') # keys can also be strings

And now you're ready to actually use your interpolator:

    result = i.interpolate("Hello, %n. The weather's %w today") # returns "Hello, Bob. The weather's nice today"

You can mark placeholders as being required:

    i = StringInterpolator.new
    i.add(n: 'Bob', w: 'nice')
    i.require(:n)
    i.interpolate("Hello, the weather's %w today") # this raises an exception...
    i.interpolate("Hello, %n.") # ...but this works

Both add and require return the interpolator itself, so you can chain them together:

    result = StringInterpolator.new.add(n: 'Bob').require(:n).interpolate('Hello, %n.')

Interpolators use % as the character that signals the start of a placeholder by default. If you'd like to use a
different character as the herald, you can do that with:

    i = StringInterpolator.new('$')
    i.add(n: 'Bob', w: 'nice')
    i.interpolate("Hello, $n. The weather's $w today")

Heralds can be multi-character strings, if you like:

    i = StringInterpolator.new('!!!')
    i.add(n: 'Bob', w: 'nice')
    i.interpolate("Hello, !!!n. The weather's !!!w today")

Placeholders can also be multi-character strings:

    i = StringInterpolator.new
    i.add(name: 'Bob', weather: 'nice')
    i.require(:name)
    i.interpolate("Hello, %name. The weather's %weather today")

Two percent signs (or two of whatever herald you've chosen) in a row can be used to insert a literal copy of the
herald:

    i = StringInterpolator.new
    i.add(n: 'Bob')
    i.interpolate("Hello, %n. Humidity's right about 60%% today") # "Hello, Bob. Humidity's right about 60% today"

You can turn off the double herald literal mechanism and add your own, if you like:

    i = StringInterpolator.new(literal: false)
    i.add(percent: '%')
    i.interpolate('%percent') # '%'
    i.interpolate('%%') # raises an exception

Ambiguous placeholders cause an exception to be raised:

    i = StringInterpolator.new
    i.add(foo: 'one', foobar: 'two') # raises an exception - should "%foobarbaz" be "onebarbaz" or "twobaz"?

And that's about it.

Internally the whole thing is implemented using a prefix tree of all of the placeholders that have been added and a
scanning parser that descends through the tree whenever it hits a herald to find a match. It's therefore super fast
even on long strings and with lots of placeholders, and it doesn't get confused by things like '%%foo' or '%%%foo'
(which should respectively output '%foo' and '%bar' if foo is a placeholder for 'bar', but a lot of other
interpolation libraries that boil down to a bunch of `gsub`s screw one of those two up). The only downside of the
current implementation is that it recurses for each character in a placeholder, so placeholders are limited to a few
hundred characters in length (but their replacements aren't). I'll rewrite it as a bunch of loops if that ever
actually becomes a problem for anyone (but I'll probably question your sanity for using such long placeholders
first).
