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
- `JsonObject.parse(value)` for a value that is already decoded. Null when it
  is not a JSON object. A duplicate's value is already gone from a decoded
  value, and a big integer already rounded on the web, so for wire text of
  any kind decode it with
  `decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text)` rather than
  `jsonDecode`.
- `object(k)` and `objects(k)` for an object nested in another.
- `JsonObject.of(map)` for an object you build yourself, for a `toJson`, from
  a map whose static type is already string-keyed.

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
final kept = plain.frozen();                            // read-only copy
final schema = tool.deepFrozen();                       // read-only all the way down
```

For an object used as a dictionary, whose keys are data rather than names the
code knows, `keys` gives the names and a reader reads each value:

```dart
final prices = {for (final m in table.keys) m: table.number(m)};
```

`frozen()` copies only the object itself, and nested objects and lists stay
shared. `deepFrozen()` copies and protects every one of them, keeps field and
list order, and refuses (with the path) any value `jsonEncode` couldn't write,
including a key that is not a string.

`jsonEncode` writes a `JsonObject` as it is, so encoding needs no map. The one
way out to a `Map` is `asUncheckedMap()`, a read-only view for a parameter
declared as a `Map`, as some other package's API is. A read from it is
unchecked, which is what the name says.

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
- **Two objects are equal when their fields are.** Fields compare in any
  order, all the way down, with `1` equal to `1.0` as in Dart. A
  `JsonObject` never equals a plain map with the same fields. The hash is of
  the fields as they are now, so don't keep one in a set while the map it
  was made `of` is still changing.
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

## Licence

Apache-2.0. Copyright 2026 Enspyr Pty Ltd.
