import 'dart:collection';

import 'decode_json.dart';

/// A JSON object: string keys, JSON values, read through the readers below.
/// Holding one means the shape was checked, so nothing downstream checks it
/// again.
///
/// The map inside is private, so code outside this library cannot wrap an
/// unchecked value in one. A value from outside becomes one through a door
/// that checks it: [JsonObject.decode] for wire text, [parse] for a value
/// that is already decoded, and [object] or [objects] for one nested in
/// another. An object we build ourselves, for a `toJson`, is [JsonObject.of]
/// a map whose static type is already string-keyed.
///
/// A plain reader requires its field and throws [JsonFieldException] naming it;
/// its `OrNull` twin takes an absent or null field as null and still rejects
/// one of the wrong type. A default for an absent field is the caller's `??`,
/// so the default sits where it is used.
///
/// It is a map that refuses changes, so `jsonEncode`, a map pattern and a
/// test's map matcher each read it as one. A field is still read through a
/// reader, which checks its type; one object is made from others with
/// [withFields], [JsonObject.merge] and [without].
///
/// A map is never a [JsonObject] at runtime, so `map as JsonObject` throws
/// and `map is JsonObject` is false: the doors are the only way in.
final class JsonObject extends UnmodifiableMapBase<String, Object?> {
  const JsonObject._(this._fields);

  final Map<String, Object?> _fields;

  /// An object built from a map we wrote, as a `toJson` returns it. A map
  /// literal is one; so is any map whose type already says string keys.
  const JsonObject.of(Map<String, Object?> fields) : _fields = fields;

  @override
  Object? operator [](Object? key) => _fields[key];

  @override
  bool containsKey(Object? key) => _fields.containsKey(key);

  @override
  int get length => _fields.length;

  @override
  bool get isEmpty => _fields.isEmpty;

  @override
  Iterable<MapEntry<String, Object?>> get entries => _fields.entries;

  /// Two objects are equal when they have the same fields with equal values,
  /// in any order, all the way down; `1` and `1.0` are equal, as in Dart.
  /// The hash is of the fields as they are now, so an object whose map is
  /// still being changed should not be kept in a set.
  @override
  bool operator ==(Object other) =>
      other is JsonObject && _jsonEquals(_fields, other._fields);

  @override
  int get hashCode => _jsonHash(_fields);

  @override
  String toString() => _fields.toString();

  /// A copy of [fields] that refuses changes, for an object kept for the
  /// life of a conversation. Nested objects and lists are shared, not
  /// copied.
  factory JsonObject.unmodifiable(Map<String, Object?> fields) =>
      JsonObject._(Map.unmodifiable(fields));

  /// The object with no fields.
  static const empty = JsonObject._({});

  /// One object with the fields of each of [parts], in order: a later part's
  /// field takes the place of an earlier one's.
  factory JsonObject.merge(Iterable<JsonObject> parts) =>
      JsonObject._({for (final p in parts) ...p._fields});

  /// [text] decoded as a JSON object. A [FormatException] when it is not
  /// JSON, is JSON of another kind (a list, a string, a number, null), names
  /// a key twice in one object, or has an integer past 2^53 - 1; see
  /// [decodeJsonRefusingDuplicateKeysAndUnsafeIntegers].
  factory JsonObject.decode(String text) =>
      parse(decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text)) ??
      (throw const FormatException('not a JSON object'));

  /// [value] as a JSON object, or null when it is anything else. For a
  /// value that is already decoded: one element of a decoded list, or a
  /// message whose kind is not known until it is looked at.
  ///
  /// The test is the map's runtime type, which `jsonDecode` always makes
  /// string-keyed. A `Map<dynamic, dynamic>`, as YAML and Flutter platform
  /// channels deliver one, is not a JSON object here even when every key is
  /// a string: copy it with `Map<String, Object?>.from` first.
  ///
  /// A [JsonObject] placed inside another, as [withFields] or a `toJson`
  /// can place one, is itself.
  static JsonObject? parse(Object? value) => switch (value) {
        final JsonObject o => o,
        final Map<String, Object?> m => JsonObject._(m),
        _ => null,
      };

  /// Whether [k] is present, even with a null value.
  bool has(String k) => _fields.containsKey(k);

  /// The field as it was decoded, for a value whose shape the caller reads
  /// with a pattern (one of several kinds) or passes on untouched.
  Object? raw(String k) => _fields[k];

  /// The field names, for an object used as a dictionary, whose keys are
  /// data rather than names the code knows. Read each value with a reader.
  @override
  Iterable<String> get keys => _fields.keys;

  /// This object with [more] laid over it: a new field is added after the
  /// existing ones, and one already present takes the new value in place.
  JsonObject withFields(Map<String, Object?> more) =>
      JsonObject._({..._fields, ...more});

  /// A copy that refuses changes, for an object kept for the life of a
  /// conversation. Nothing outside this library writes to a [JsonObject],
  /// but whoever made this one with [JsonObject.of] still holds that map;
  /// the copy no longer shares it. Nested objects and lists are shared, not
  /// copied, as [JsonObject.unmodifiable] shares them; [deepFrozen] copies
  /// them too.
  JsonObject frozen() => JsonObject._(Map.unmodifiable(_fields));

  /// A copy all the way down that refuses changes, for an object kept as it
  /// was at one moment, such as a tool's schema. Every object and list
  /// inside is copied as well, so neither a later change to the maps and
  /// lists this was made of nor a write through the copy can change it.
  ///
  /// Field order and list order are kept, so `jsonEncode` writes the same
  /// bytes before and after. Every value inside must be one `jsonEncode`
  /// writes as it is: null, a bool, a finite number, a string, a list, or an
  /// object whose keys are strings. Anything else is a [JsonFieldException]
  /// whose [JsonFieldException.field] is where it is (`a.b[2]`), raised here
  /// rather than by a later `jsonEncode`. A key that is not a string is never
  /// turned into one, since `1` and `'1'` would then collide.
  ///
  /// A nested map comes back as a `Map<String, Object?>` whatever its type
  /// was, so [object] and [objects] read one written as a bare `{}` literal.
  JsonObject deepFrozen() => JsonObject._(Map.unmodifiable({
        for (final MapEntry(:key, :value) in _fields.entries)
          key: _deepFrozen(value, key),
      }));

  /// This object without the fields named in [keys]. A name that is absent
  /// is passed over.
  JsonObject without(Iterable<String> keys) {
    final drop = keys.toSet();
    return JsonObject._({
      for (final MapEntry(:key, :value) in _fields.entries)
        if (!drop.contains(key)) key: value,
    });
  }

  /// The object as a map that refuses changes, for a parameter declared as
  /// a [Map], as some other package's API is. Nothing else needs one:
  /// `jsonEncode` writes a [JsonObject] as it is. A read from it is
  /// unchecked, which is what the name says.
  Map<String, Object?> asUncheckedMap() => UnmodifiableMapView(_fields);

  String string(String k) => switch (_fields[k]) {
        final String s => s,
        _ => throw JsonFieldException(k, 'a string'),
      };
  String? stringOrNull(String k) => _fields[k] == null ? null : string(k);

  /// A whole number, as [wholeNumber] reads one.
  int integer(String k) =>
      wholeNumber(_fields[k]) ?? (throw JsonFieldException(k, 'an integer'));
  int? integerOrNull(String k) => _fields[k] == null ? null : integer(k);

  /// Any finite number, `3` or `3.5`. JSON has no infinity, but a literal
  /// too large for a double (`1e400`) decodes as one, and `toInt` throws on
  /// it.
  num number(String k) => switch (_fields[k]) {
        final num n when n.isFinite => n,
        _ => throw JsonFieldException(k, 'a finite number'),
      };
  num? numberOrNull(String k) => _fields[k] == null ? null : number(k);

  bool boolean(String k) => switch (_fields[k]) {
        final bool b => b,
        _ => throw JsonFieldException(k, 'true or false'),
      };
  bool? booleanOrNull(String k) => _fields[k] == null ? null : boolean(k);

  JsonObject object(String k) =>
      parse(_fields[k]) ?? (throw JsonFieldException(k, 'an object'));
  JsonObject? objectOrNull(String k) => _fields[k] == null ? null : object(k);

  List<Object?> list(String k) => _list(k, 'a list');
  List<Object?>? listOrNull(String k) => _fields[k] == null ? null : list(k);

  List<String> strings(String k) => [
        for (final x in _list(k, 'a list of strings'))
          x is String ? x : throw JsonFieldException(k, 'a list of strings'),
      ];
  List<String>? stringsOrNull(String k) =>
      _fields[k] == null ? null : strings(k);

  List<JsonObject> objects(String k) => [
        for (final x in _list(k, 'a list of objects'))
          parse(x) ?? (throw JsonFieldException(k, 'a list of objects')),
      ];
  List<JsonObject>? objectsOrNull(String k) =>
      _fields[k] == null ? null : objects(k);

  /// The field as a list, or a [JsonFieldException] saying it should have
  /// been [wanted], so a reader of a list of something names the whole shape
  /// whichever way the field is wrong.
  List<Object?> _list(String k, String wanted) => switch (_fields[k]) {
        final List<Object?> l => l,
        _ => throw JsonFieldException(k, wanted),
      };
}

/// A field that is absent, or present but not the shape its reader asked
/// for.
///
/// A [FormatException], so code that catches those still does. A reader that
/// wants to tell "this field is wrong" apart from any other failure catches
/// this type alone.
final class JsonFieldException extends FormatException {
  JsonFieldException(this.field, this.wanted)
      : super('`$field` is not $wanted');
  final String field;

  /// What the field should have been, as a phrase: `a string`, `a list`.
  final String wanted;
}

/// [value], found at [at], copied all the way down into maps and lists that
/// refuse changes; see [JsonObject.deepFrozen].
Object? _deepFrozen(Object? value, String at) => switch (value) {
      null || bool() || String() => value,
      final num n when n.isFinite => n,
      final JsonObject o => _deepFrozen(o._fields, at),
      final Map<Object?, Object?> m => Map<String, Object?>.unmodifiable({
          for (final MapEntry(:key, :value) in m.entries)
            _stringKey(key, at): _deepFrozen(value, '$at.$key'),
        }),
      final List<Object?> l => List<Object?>.unmodifiable([
          for (final (i, x) in l.indexed) _deepFrozen(x, '$at[$i]'),
        ]),
      _ => throw JsonFieldException(at, 'a JSON value'),
    };

/// Whether [a] and [b] are the same JSON value: objects by their fields in
/// any order, lists element by element, anything else by `==`.
bool _jsonEquals(Object? a, Object? b) => switch ((a, b)) {
      (final JsonObject x, _) => _jsonEquals(x._fields, b),
      (_, final JsonObject y) => _jsonEquals(a, y._fields),
      (final Map<Object?, Object?> x, final Map<Object?, Object?> y) =>
        x.length == y.length &&
            x.entries.every(
                (e) => y.containsKey(e.key) && _jsonEquals(e.value, y[e.key])),
      (final List<Object?> x, final List<Object?> y) => x.length == y.length &&
          [for (var i = 0; i < x.length; i++) i]
              .every((i) => _jsonEquals(x[i], y[i])),
      _ => a == b,
    };

/// A hash agreeing with [_jsonEquals]: an object's fields are combined
/// without regard to order.
int _jsonHash(Object? v) => switch (v) {
      final JsonObject o => _jsonHash(o._fields),
      final Map<Object?, Object?> m => Object.hashAllUnordered([
          for (final MapEntry(:key, :value) in m.entries)
            Object.hash(key, _jsonHash(value)),
        ]),
      final List<Object?> l => Object.hashAll(l.map(_jsonHash)),
      _ => v.hashCode,
    };

/// [key] of the object at [at], refused unless it is a string.
String _stringKey(Object? key, String at) => key is String
    ? key
    : throw JsonFieldException(at, 'an object with string keys');

/// [v] as a whole number: `3`, or `3.0` as some writers spell one (and as a
/// web build reads every whole number), but never `3.5`; null for anything
/// else. A double is taken only below 2^53 in size, where it stands for one
/// whole number: 2^53 is also what `9007199254740993.0` decodes to, and far
/// past it `toInt` clamps to the biggest int without saying so.
int? wholeNumber(Object? v) => switch (v) {
      final int n => n,
      final double d
          when d == d.truncateToDouble() && d > -_twoTo53 && d < _twoTo53 =>
        d.toInt(),
      _ => null,
    };

/// 2^53, the first size at which a double no longer pins down one whole
/// number. JavaScript's `Number.MAX_SAFE_INTEGER` is one less, for the same
/// reason.
const _twoTo53 = 9007199254740992.0;
