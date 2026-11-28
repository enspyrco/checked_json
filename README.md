# checked_json

A JSON object you only get by checking a value. Holding a `JsonObject` means
the value was looked at and found to be a JSON object, so nothing downstream
checks it again. Its fields are read through typed readers that say which
field was wrong and what it should have been.

```dart
import 'package:checked_json/checked_json.dart';

final user = JsonObject.decode('{"name": "Ada", "tags": ["maths"]}');

user.string('name');         // 'Ada'
user.strings('tags');        // ['maths']
user.integerOrNull('born');  // null: absent
user.integer('name');        // throws JsonFieldException: `name` is not an integer
```

## The doors in

The map inside a `JsonObject` is private, so code outside the library cannot
wrap an unchecked value in one. A value becomes one through a door that checks
it:

- `JsonObject.decode(text)` for wire text. A `FormatException` when the text
  is not JSON, is JSON of another kind, has an object that names the same
  key twice, or has an integer past 2^53 - 1 in size, which a web build reads
  inexactly. A number written with a `.` or an exponent is a double and is
  rounded to the nearest one, the same on every platform.

  An API that writes a 64-bit id as a number, as GitHub does for a webhook
  delivery, can't be read exactly as a number on the web, so name the field
  and it comes back as a string of its digits, at any depth and whatever its
  size:

  ```dart
  final deliveries = decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(
    text,
    integerFieldsAsStrings: {'id'},
  );
  // [{'id': '3856380378147192832', ...}] on the VM and on the web
  ```
- `JsonObject.parse(value)` for a value that is already decoded. Null when it
  is not a JSON object. A duplicate's value is already gone from a decoded
  value, and a big integer already rounded on the web, so for wire text of
  any kind decode it with
  `decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text)` rather than
  `jsonDecode`.
- `object(k)` and `objects(k)` for an object nested in another.
- `JsonObject.of(map)` for an object you build yourself, for a `toJson`. It
  copies the map all the way down, and refuses (naming where) any value
  `jsonEncode` couldn't write: a `DateTime`, `NaN`, a key that is not a
  string.
- `MutableJsonObject` for one built up field by field: a map you can write
  to, which checks and copies each value as it is written. `toJsonObject()`
  turns it into a `JsonObject`, and `obj.toMutable()` goes the other way.

## The readers

`string`, `integer`, `number`, `boolean`, `object`, `list`, `strings` and
`objects`. A plain reader requires its field and throws a
`JsonFieldException` naming the field and the shape it wanted. Its `OrNull`
twin takes an absent or null field as null, and still refuses one of the wrong
type. A default for an absent field is the caller's `??`, so the default sits
where it is used. `has(k)` tells a field present with a null value apart from
an absent one, and `raw(k)` gives a field as it was decoded.

## Building one object from others

Each of these gives a new `JsonObject`, so no map has to come out to be
spread:

```dart
final streaming = body.withFields({'stream': true});   // fields laid over
final request = JsonObject.merge([common, if (effort != null) effort]);
                                                        // later parts win
final plain = streaming.without({'stream'});            // fields dropped
```

For an object used as a dictionary, whose keys are data rather than names the
code knows, `keys` gives the names and a reader reads each value:

```dart
final prices = {for (final m in table.keys) m: table.number(m)};
```

`jsonEncode` writes a `JsonObject` as it is, so encoding needs no map. A `JsonObject` is
itself a read-only `Map`, so it can be passed where some other package's API
wants one; `asUncheckedMap()` says at that call that what follows reads it
unchecked.

`JsonFieldException` extends `FormatException`: a bad field is a condition
you're meant to catch, not a programming bug. Code that already catches
`FormatException` still catches it.

## What it guarantees, and what it doesn't yet

- **A map is never a `JsonObject`.** `JsonObject` is a final class, so
  `map as JsonObject` throws a `TypeError` and `map is JsonObject` is false,
  even for `jsonDecode` output: the doors (`decode`, `parse`, `of`, a
  reader) are the only way to get one. A `case final JsonObject o` on a
  decoded value never matches; use `JsonObject.parse`.
- **A `JsonObject` is a read-only `Map<String, Object?>`.** `jsonEncode`, a
  map pattern and a test's map matcher read it as one. `obj['k']` compiles
  and is unchecked, so read a field through a reader. `obj['k'] = v` also
  compiles, and throws `UnsupportedError`.
- **Nothing can change a `JsonObject`, all the way down.** Every object
  inside it is a `JsonObject`, and every list inside it refuses changes,
  whether it came from `list(k)`, `raw(k)` or `obj['k']`. `of`, `parse` and
  `withFields` copy what they're given, so the caller's map can go on
  changing without reaching it. `decode` copies nothing: the map it wraps
  was never seen by anyone else.
- **Two objects are equal when their fields are.** Fields compare in any
  order, all the way down, with `1` equal to `1.0` as in Dart. A
  `JsonObject` never equals a plain map with the same fields. A
  `MutableJsonObject` compares by identity, since it can change after it is
  put in a set.
- **`parse` matches the map's runtime type.** `jsonDecode` always makes a
  string-keyed map, so its output is fine. A `Map<dynamic, dynamic>`, as YAML
  and Flutter platform channels deliver one, gives null even when every key is
  a string: copy it with `Map<String, Object?>.from` first.
- **Whole numbers are exact only below 2^53 in magnitude.** `integer` reads
  `3` or `3.0` (as some writers spell one, and as a web build reads every
  whole number) but never `3.5`. A double is taken only when its size is
  strictly below 2^53, where it stands for one whole number; 2^53 itself is
  refused, because `9007199254740993.0` decodes to it too.
- **Nested values are not deep-checked up front.** A door checks that the
  value is an object; each field is checked when its reader reads it.
- **Nesting stops at 512 levels.** An object holds at most
  `jsonObjectNestingLimit` objects and lists one inside another, counting
  itself, and every door refuses deeper input with a `FormatException`, as
  `decodeJsonRefusingDuplicateKeysAndUnsafeIntegers` does.
  Without the limit, a 30 KB body nested 5,000 deep would end the program
  with a `StackOverflowError`, here or in `jsonEncode`.

## Licence

Apache-2.0. Copyright 2026 Enspyr Pty Ltd.
