import 'dart:collection';

import 'decode_json.dart';

/// A JSON object: string keys, JSON values, read through the readers below.
/// Holding one means the shape was checked, so nothing downstream checks it
/// again, and nothing can change it, all the way down.
///
/// The map inside is private, so code outside this library cannot wrap an
/// unchecked value in one. A value from outside becomes one through a door
/// that checks it: [JsonObject.decode] for wire text, [parse] for a value
/// that is already decoded, and [object] or [objects] for one nested in
/// another. An object we build ourselves, for a `toJson`, is [JsonObject.of]
/// a map, or a [MutableJsonObject] built up field by field and then
/// [MutableJsonObject.toJsonObject].
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
/// Every object inside is a [JsonObject] and every list inside refuses
/// changes, so nothing reached through one can be changed either. No one
/// outside holds the map inside: [JsonObject.of] and [parse] copy what they
/// are given, and [JsonObject.decode] wraps a map only it has seen.
///
/// A map is never a [JsonObject] at runtime, so `map as JsonObject` throws
/// and `map is JsonObject` is false: the doors are the only way in.
final class JsonObject extends UnmodifiableMapBase<String, Object?> {
  const JsonObject._(this._fields, this._depth);

  /// [fields], already frozen, as a [JsonObject] whose depth is measured.
  JsonObject._frozen(Map<String, Object?> fields)
      : this._(fields, 1 + _deepestValue(fields.values));

  final Map<String, Object?> _fields;

  /// How many objects and lists deep this one goes, counting itself: `{}`
  /// is 1 and `{"a": [{}]}` is 3. Never more than [jsonObjectNestingLimit].
  final int _depth;

  /// A copy of [fields], all the way down, as a `toJson` returns one.
  ///
  /// Every value must be one `jsonEncode` writes as it is: null, a bool, a
  /// finite number, a string, a list, or an object whose keys are strings.
  /// Anything else (a `DateTime`, `NaN`) is a [JsonFieldException] whose
  /// [JsonFieldException.field] is where it is (`a.b[2]`), raised here
  /// rather than by a later `jsonEncode`. A key that is not a string is
  /// never turned into one, since `1` and `'1'` would then collide. Field
  /// and list order are kept.
  ///
  /// A [JsonObject] inside is kept as it is, since it cannot change.
  factory JsonObject.of(Map<String, Object?> fields) =>
      JsonObject._frozen(_frozenFields(fields));

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
  @override
  bool operator ==(Object other) =>
      other is JsonObject && _jsonEquals(_fields, other._fields);

  @override
  int get hashCode => _jsonHash(_fields);

  @override
  String toString() => _fields.toString();

  /// The object with no fields.
  static const empty = JsonObject._({}, 1);

  /// One object with the fields of each of [parts], in order: a later part's
  /// field takes the place of an earlier one's.
  factory JsonObject.merge(Iterable<JsonObject> parts) => JsonObject._frozen(
      Map.unmodifiable({for (final p in parts) ...p._fields}));

  /// [text] decoded as a JSON object. A [FormatException] when it is not
  /// JSON, is JSON of another kind (a list, a string, a number, null), names
  /// a key twice in one object, or has an integer past 2^53 - 1; see
  /// [decodeJsonRefusingDuplicateKeysAndUnsafeIntegers], which also says how
  /// a field named in [integerFieldsAsStrings] is read: an integer there,
  /// such as a 64-bit id, comes back as a string of its digits.
  factory JsonObject.decode(
    String text, {
    Set<String> integerFieldsAsStrings = const {},
  }) =>
      switch (decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(
        text,
        integerFieldsAsStrings: integerFieldsAsStrings,
      )) {
        final Map<String, Object?> m => _wrapDecodedObject(m, 1),
        _ => throw const FormatException('not a JSON object'),
      };

  /// [value] as a JSON object, or null when it is anything else. For a
  /// value that is already decoded: one element of a decoded list, or a
  /// message whose kind is not known until it is looked at.
  ///
  /// A map is copied as [JsonObject.of] copies one, since whoever passed it
  /// may still hold it; a [JsonObject] is itself.
  ///
  /// The test is the map's runtime type, which `jsonDecode` always makes
  /// string-keyed. A `Map<dynamic, dynamic>`, as YAML and Flutter platform
  /// channels deliver one, is not a JSON object here even when every key is
  /// a string: copy it with `Map<String, Object?>.from` first.
  static JsonObject? parse(Object? value) => switch (value) {
        final JsonObject o => o,
        final Map<String, Object?> m => JsonObject.of(m),
        _ => null,
      };

  /// Whether [k] is present, even with a null value.
  bool has(String k) => _fields.containsKey(k);

  /// The field as it was decoded, for a value whose shape the caller reads
  /// with a pattern (one of several kinds) or passes on untouched. An object
  /// inside is a [JsonObject], and a list refuses changes.
  Object? raw(String k) => _fields[k];

  /// The field names, for an object used as a dictionary, whose keys are
  /// data rather than names the code knows. Read each value with a reader.
  @override
  Iterable<String> get keys => _fields.keys;

  /// This object with [more] laid over it: a new field is added after the
  /// existing ones, and one already present takes the new value in place.
  /// [more] is copied as [JsonObject.of] copies a map.
  JsonObject withFields(Map<String, Object?> more) => JsonObject._frozen(
      Map.unmodifiable({..._fields, ..._frozenFields(more)}));

  /// This object without the fields named in [keys]. A name that is absent
  /// is passed over.
  JsonObject without(Iterable<String> keys) {
    final drop = keys.toSet();
    return JsonObject._frozen(Map.unmodifiable({
      for (final MapEntry(:key, :value) in _fields.entries)
        if (!drop.contains(key)) key: value,
    }));
  }

  /// A [MutableJsonObject] holding these fields, to change and then turn
  /// back into a [JsonObject].
  MutableJsonObject toMutable() => MutableJsonObject(this);

  /// This object, for a parameter declared as a [Map], as some other
  /// package's API is. A read from it is unchecked, which is what the name
  /// says.
  Map<String, Object?> asUncheckedMap() => this;

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

  JsonObject object(String k) => switch (_fields[k]) {
        final JsonObject o => o,
        _ => throw JsonFieldException(k, 'an object'),
      };
  JsonObject? objectOrNull(String k) => _fields[k] == null ? null : object(k);

  /// The field's list itself, which refuses changes.
  List<Object?> list(String k) => _list(k, 'a list');
  List<Object?>? listOrNull(String k) => _fields[k] == null ? null : list(k);

  List<String> strings(String k) => List.unmodifiable([
        for (final x in _list(k, 'a list of strings'))
          x is String ? x : throw JsonFieldException(k, 'a list of strings'),
      ]);
  List<String>? stringsOrNull(String k) =>
      _fields[k] == null ? null : strings(k);

  List<JsonObject> objects(String k) => List.unmodifiable([
        for (final x in _list(k, 'a list of objects'))
          x is JsonObject
              ? x
              : throw JsonFieldException(k, 'a list of objects'),
      ]);
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

/// A JSON object that can change, for building one field by field. Turn it
/// into a [JsonObject] with [toJsonObject].
///
/// Each value is checked and copied when it is written, as [JsonObject.of]
/// checks and copies one, so a `DateTime` or `NaN` is a
/// [JsonFieldException] at the line that wrote it. An object or list inside
/// cannot change once written: to change one, build it again and write it
/// again.
///
/// It is not a [JsonObject], and equality is identity, since its fields can
/// change after it is put in a set.
final class MutableJsonObject extends MapBase<String, Object?> {
  /// An object holding the fields of [fields], each checked and copied.
  MutableJsonObject([Map<String, Object?> fields = const {}]) {
    addAll(fields);
  }

  final _fields = <String, Object?>{};

  @override
  Object? operator [](Object? key) => _fields[key];

  /// Sets [key] to a copy of [value], refused unless it is a JSON value.
  @override
  void operator []=(String key, Object? value) =>
      _fields[key] = _frozen(value, key, 1);

  @override
  Object? remove(Object? key) => _fields.remove(key);

  @override
  void clear() => _fields.clear();

  @override
  bool containsKey(Object? key) => _fields.containsKey(key);

  @override
  int get length => _fields.length;

  @override
  Iterable<String> get keys => _fields.keys;

  /// The fields as they are now, as a [JsonObject]. A later change to this
  /// object does not reach it.
  JsonObject toJsonObject() => JsonObject._frozen(Map.unmodifiable(_fields));
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

/// The most objects and lists a [JsonObject] holds one inside another,
/// counting itself: `{"a": [{}]}` is 3 deep. Anything deeper is refused at
/// every door with a [FormatException], since walking it (in a copy, in
/// `jsonEncode`, in `==`, in a recursive `fromJson`) would run out of stack
/// with a `StackOverflowError`, which `on FormatException` does not catch.
/// `jsonEncode` itself runs out somewhere between 1,000 and 5,000 levels.
const jsonObjectNestingLimit = 512;

/// The depth of the deepest of [values], already frozen: a [JsonObject]'s
/// own, a list's one more than its deepest element's, anything else 0.
int _deepestValue(Iterable<Object?> values) {
  var deepest = 0;
  for (final v in values) {
    final d = switch (v) {
      final JsonObject o => o._depth,
      final List<Object?> l => 1 + _deepestValue(l),
      _ => 0,
    };
    if (d > deepest) deepest = d;
  }
  return deepest;
}

/// [fields] copied for a [JsonObject]: each value as [_frozen] makes it,
/// found at its key, one level inside the object being made.
Map<String, Object?> _frozenFields(Map<String, Object?> fields) =>
    Map.unmodifiable({
      for (final MapEntry(:key, :value) in fields.entries)
        key: _frozen(value, key, 1),
    });

/// [value], found at [at] with [above] objects and lists around it, copied
/// all the way down: each map into a [JsonObject] and each list into one
/// that refuses changes. A [JsonObject] is kept as it is.
Object? _frozen(Object? value, String at, int above) => switch (value) {
      null || bool() || String() => value,
      final num n when n.isFinite => n,
      final JsonObject o when above + o._depth > jsonObjectNestingLimit =>
        throw _tooDeep(at),
      final JsonObject o => o,
      Map<Object?, Object?>() ||
      List<Object?>() when above >= jsonObjectNestingLimit =>
        throw _tooDeep(at),
      final Map<Object?, Object?> m => JsonObject._frozen(Map.unmodifiable({
          for (final MapEntry(:key, :value) in m.entries)
            _stringKey(key, at): _frozen(value, '$at.$key', above + 1),
        })),
      final List<Object?> l => List<Object?>.unmodifiable([
          for (final (i, x) in l.indexed) _frozen(x, '$at[$i]', above + 1),
        ]),
      _ => throw JsonFieldException(at, 'a JSON value'),
    };

JsonFieldException _tooDeep(String at) => JsonFieldException(
    at, 'within $jsonObjectNestingLimit levels of objects and lists');

/// [m], fresh from `jsonDecode` and seen by no one else, at [depth] (the
/// outermost object is 1), as a [JsonObject] without copying it: each
/// object inside is wrapped in place, and each list is wrapped in a view
/// that refuses changes.
JsonObject _wrapDecodedObject(Map<String, Object?> m, int depth) {
  m.updateAll((_, v) => _wrapDecoded(v, depth + 1));
  return JsonObject._frozen(m);
}

Object? _wrapDecoded(Object? v, int depth) {
  if ((v is Map || v is List) && depth > jsonObjectNestingLimit) {
    throw const FormatException(
        'objects and lists nested more than $jsonObjectNestingLimit deep');
  }
  switch (v) {
    case final Map<String, Object?> m:
      return _wrapDecodedObject(m, depth);
    case final List<Object?> l:
      for (var i = 0; i < l.length; i++) {
        l[i] = _wrapDecoded(l[i], depth + 1);
      }
      return UnmodifiableListView(l);
    default:
      return v;
  }
}

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
