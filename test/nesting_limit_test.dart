import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:test/test.dart';

/// [n] objects one inside another: `{"a":{"a":1}}` for 2.
String nestedObjects(int n) => '${'{"a":' * n}1${'}' * n}';

/// An object holding [n] - 1 lists one inside another: `{"a":[1]}` for 2.
String nestedLists(int n) => '{"a":${'[' * (n - 1)}1${']' * (n - 1)}}';

void main() {
  const limit = jsonObjectNestingLimit;

  group('decode', () {
    test('takes objects and lists nested exactly to the limit', () {
      expect(JsonObject.decode(nestedObjects(limit)), isA<JsonObject>());
      expect(JsonObject.decode(nestedLists(limit)), isA<JsonObject>());
    });

    test('refuses one level more with a FormatException', () {
      expect(() => JsonObject.decode(nestedObjects(limit + 1)),
          throwsFormatException);
      expect(() => JsonObject.decode(nestedLists(limit + 1)),
          throwsFormatException);
    });

    test('refuses 100,000 levels with a FormatException, not a stack overflow',
        () {
      expect(() => JsonObject.decode(nestedObjects(100000)),
          throwsFormatException);
      expect(
          () => JsonObject.decode(nestedLists(100000)), throwsFormatException);
    });
  });

  group('decodeJsonRefusingDuplicateKeysAndUnsafeIntegers', () {
    test('refuses a top-level list nested past the limit', () {
      final deep = '${'[' * (limit + 1)}${']' * (limit + 1)}';
      expect(() => decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(deep),
          throwsFormatException);
      final atLimit = '${'[' * limit}${']' * limit}';
      expect(decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(atLimit),
          isA<List<Object?>>());
    });

    test('takes and refuses exactly what JsonObject.decode does', () {
      final texts = [
        for (final n in [1, 2, limit - 1, limit, limit + 1, 5000, 100000]) ...[
          nestedObjects(n),
          nestedLists(n),
        ],
        // Brackets inside a string are not nesting.
        '{"a":"${'[' * (limit + 1)}"}',
      ];
      bool refuses(Object? Function() decode) {
        try {
          decode();
          return false;
        } on FormatException {
          return true;
        }
      }

      for (final t in texts) {
        expect(
          refuses(() => decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(t)),
          refuses(() => JsonObject.decode(t)),
          reason:
              '${t.length} characters: ${t.substring(0, t.length.clamp(0, 12))}',
        );
      }
      expect(refuses(() => JsonObject.decode(nestedObjects(limit))), isFalse);
      expect(
          refuses(() => JsonObject.decode(nestedObjects(limit + 1))), isTrue);
    });
  });

  group('parse', () {
    test('takes a decoded value nested exactly to the limit', () {
      expect(JsonObject.parse(jsonDecode(nestedObjects(limit))),
          isA<JsonObject>());
    });

    test('refuses one level more, naming where it is', () {
      expect(
        () => JsonObject.parse(jsonDecode(nestedObjects(limit + 1))),
        throwsA(isA<JsonFieldException>().having(
          (e) => e.field,
          'field',
          List.filled(limit, 'a').join('.'),
        )),
      );
    });

    test('refuses 100,000 levels with a FormatException', () {
      expect(() => JsonObject.parse(jsonDecode(nestedObjects(100000))),
          throwsFormatException);
      expect(() => JsonObject.parse(jsonDecode(nestedLists(100000))),
          throwsFormatException);
    });
  });

  group('an object already made', () {
    test('cannot be nested past the limit one of() at a time', () {
      var o = JsonObject.empty;
      for (var i = 1; i < limit; i++) {
        o = JsonObject.of({'a': o});
      }
      expect(jsonEncode(o), '${'{"a":' * (limit - 1)}{}${'}' * (limit - 1)}');
      expect(() => JsonObject.of({'a': o}), throwsFormatException);
      expect(
          () => JsonObject.of({
                'a': [o]
              }),
          throwsFormatException);
      expect(
          () => JsonObject.empty.withFields({'a': o}), throwsFormatException);
      expect(() => MutableJsonObject()['a'] = o, throwsFormatException);
    });

    test('counts a list around an object as a level', () {
      var o = JsonObject.empty;
      // Depth limit - 2, so the object, a list and this fill the limit.
      for (var i = 3; i < limit; i++) {
        o = JsonObject.of({'a': o});
      }
      expect(
          JsonObject.of({
            'a': [o]
          }),
          isA<JsonObject>());
      expect(
          () => JsonObject.of({
                'a': [
                  [o]
                ]
              }),
          throwsFormatException);
    });

    test('a decoded object at the limit cannot go inside another', () {
      final deep = JsonObject.decode(nestedObjects(limit));
      expect(() => JsonObject.of({'b': deep}), throwsFormatException);
      expect(JsonObject.merge([deep, deep]), deep);
      expect(deep.without(['a']), JsonObject.empty);
    });
  });
}
