# Changelog

## 0.4.0

- **Breaking:** nothing can change a `JsonObject`, all the way down. Every
  object inside one is a `JsonObject` and every list inside refuses changes,
  whichever reader or `raw` it comes out of; `strings` and `objects` give
  lists that refuse changes too.
- **Breaking:** `JsonObject.of` copies its map all the way down, so it is no
  longer `const`: drop the `const` from `const JsonObject.of(...)`.
  `JsonObject.empty` is still a constant. `of`, `parse` and `withFields`
  refuse a value `jsonEncode` couldn't write (a `DateTime`, `NaN`, a key
  that is not a string) with a `JsonFieldException` naming where it is.
- **Breaking:** `frozen()`, `deepFrozen()` and `JsonObject.unmodifiable` are
  gone, since every `JsonObject` is already what they made: drop the call.
- New `integerFieldsAsStrings` on `JsonObject.decode` and
  `decodeJsonRefusingDuplicateKeysAndUnsafeIntegers`. A field named there,
  at any depth, whose value is written as an integer comes back as a string
  of exactly its digits, whatever its size and on every platform. This is
  for an id an API writes as a 64-bit number, such as a GitHub webhook
  delivery id, which a web build would round and the integer check would
  otherwise refuse. Such a field is a string even when it is small.
- New `MutableJsonObject`, a map you can write to for building one field by
  field. It checks and copies each value as it is written, so a bad value
  fails at the line that wrote it. `toJsonObject()` turns it into a
  `JsonObject`, and `JsonObject.toMutable()` goes the other way. It is not a
  `JsonObject`, and compares by identity.
- **Breaking:** `JsonObject` is a final class that is a read-only
  `Map<String, Object?>`, no longer an extension type. A map is never a
  `JsonObject` at runtime: `map as JsonObject` throws a `TypeError` and
  `map is JsonObject` is false, so only the doors make one. Code that cast
  or type-tested a decoded map against `JsonObject` changes behaviour;
  `JsonObject.parse` is the door for that. `jsonEncode` and map patterns
  read a `JsonObject` as before.
- `obj['k']` compiles again, and is unchecked; `obj['k'] = v` compiles and
  throws `UnsupportedError`.
- Two `JsonObject`s are equal when their fields are equal, in any order and
  all the way down, with a hash to match. A `JsonObject` never equals a
  plain map.

## 0.3.0

- **Breaking:** `JsonObject.decode` refuses text in which an object, at any
  depth, names the same key twice. `jsonDecode` keeps the last value and drops
  the other without a word; this is now a `FormatException`
  (`duplicate key "k"`, its `offset` at the second key). Keys are compared
  once unescaped, so a plain `a` and its `\u` escape collide. The same key in
  two different objects is fine. Values decode exactly as `jsonDecode`
  decodes them, on the VM and on the web.
- **Breaking:** `JsonObject.decode` refuses an integer, written without a
  fraction or exponent, whose size is past 2^53 - 1. A web build reads one as
  the nearest double, so `9007199254740993` decoded one less there than on
  the VM. Write a number that size as a string to keep every digit. One
  written with a `.` or exponent is a double, rounded to the nearest one
  (`9007199254740993.0` is `9007199254740992.0`) the same everywhere, and
  passes.
- Add `decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text)`: both
  refusals for wire text of any JSON kind. Replace `JsonObject.parse(jsonDecode(text))`, and a
  `jsonDecode` of a list of objects, with it, since `JsonObject.parse` gets a
  value whose duplicate is already gone.

## 0.2.1

- Add `deepFrozen()`: a copy all the way down that refuses changes. Every
  nested object and list is copied and made unmodifiable, field and list
  order are kept (so `jsonEncode` writes the same bytes), and a nested map
  comes back as a `Map<String, Object?>`. A value `jsonEncode` cannot write
  as it is (a key that is not a string, a `Set`, a `DateTime`, `NaN`) is a
  `JsonFieldException` whose `field` is its path, such as `a.b[2]`. A key is
  never turned into a string.
- `frozen()` and `JsonObject.unmodifiable` are unchanged and stay shallow.

## 0.2.0

- **Breaking:** `JsonObject` no longer implements `Map<String, Object?>`, so
  `obj['k']` and `obj['k'] = v` do not compile. To migrate:

  | 0.1.x | 0.2.0 |
  |---|---|
  | `obj['k']` | a typed reader (`obj.string('k')`, ...), or `obj.raw('k')` for a value read with a pattern or passed on |
  | `JsonObject.of({...obj, 'k': v})` | `obj.withFields({'k': v})` |
  | `JsonObject.of({...a, ...b})` | `JsonObject.merge([a, b])` |
  | `JsonObject.of({...obj}..remove('k'))` | `obj.without({'k'})` |
  | `obj.keys`, `obj.entries` | `obj.keys`, with a reader for each value |
  | `obj.containsKey(k)` | `obj.has(k)` |
  | `JsonObject.unmodifiable(obj)` | `obj.frozen()` |
  | `obj` passed to a parameter declared as a `Map` | `obj.asUncheckedMap()` |
  | `jsonEncode(obj)` | unchanged: it writes a `JsonObject` as it is |

- Add `withFields`, `JsonObject.merge` and `without`, which each make a new
  object from others, and `keys`.
- Add `frozen()`, a copy that refuses changes. Shallow: nested objects and
  lists are shared.
- Add `asUncheckedMap()`, a read-only map view for a parameter declared as a
  `Map`.
- `JsonObject` implements `Object`, so it is never null and an extension on
  `T extends Object` applies to it. (Without `implements Map`, it would
  otherwise be only an `Object?`.)

## 0.1.0

- Add `JsonObject`, an extension type over `Map<String, Object?>` that can
  only be made from raw data through a door that checks it
  (`JsonObject.decode`, `JsonObject.parse`), with typed readers (`string`,
  `integer`, `number`, `boolean`, `object`, `list`, `strings`, `objects`,
  each with an `OrNull` twin) plus `has` and `raw`.
- Add `JsonFieldException`, the `FormatException` a reader throws naming the
  field that is absent or the wrong shape, and the shape it wanted.
- Add `wholeNumber`, which reads `3` or `3.0` as an `int` and refuses
  fractions and doubles of 2^53 or more in size.
- Licensed Apache-2.0.
