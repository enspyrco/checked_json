import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:test/test.dart';

void main() {
  group('nothing reached through a JsonObject can change', () {
    const text = '{"o": {"x": 1}, "l": [1, {"y": 2}], "s": ["a"]}';

    for (final (name, make) in [
      ('decoded', () => JsonObject.decode(text)),
      ('of a map', () => JsonObject.of(_plain())),
      ('parsed', () => JsonObject.parse(_plain())!),
    ]) {
      group(name, () {
        test('a nested object is a JsonObject, by object and by raw', () {
          final obj = make();
          expect(obj.raw('o'), isA<JsonObject>());
          expect(obj.object('o').integer('x'), 1);
          expect(() => (obj.raw('o')! as Map<String, Object?>)['x'] = 2,
              throwsUnsupportedError);
        });

        test('a list refuses changes, by list and by raw', () {
          final obj = make();
          expect(() => obj.list('l').add(3), throwsUnsupportedError);
          expect(() => (obj.raw('l')! as List<Object?>).add(3),
              throwsUnsupportedError);
          expect(() => obj.strings('s').add('b'), throwsUnsupportedError);
        });

        test('an object inside a list is a JsonObject', () {
          final obj = make();
          expect(obj.list('l')[1], isA<JsonObject>());
          expect(
            () => (obj.list('l')[1]! as Map<String, Object?>)['y'] = 3,
            throwsUnsupportedError,
          );
        });

        test('it writes the same JSON', () {
          expect(jsonDecode(jsonEncode(make())), jsonDecode(text));
        });
      });
    }

    test('of copies, so a later change to its map does not reach it', () {
      final map = _plain();
      final obj = JsonObject.of(map);
      (map['l']! as List<Object?>).add(3);
      ((map['o']! as Map<String, Object?>))['x'] = 9;
      map['new'] = true;
      expect(obj.list('l'), hasLength(2));
      expect(obj.object('o').integer('x'), 1);
      expect(obj.has('new'), isFalse);
    });

    test('parse copies too', () {
      final map = _plain();
      final obj = JsonObject.parse(map)!;
      map['new'] = true;
      expect(obj.has('new'), isFalse);
    });

    test('withFields copies what it lays over', () {
      final list = <Object?>[1];
      final obj = JsonObject.empty.withFields({'l': list});
      list.add(2);
      expect(obj.list('l'), [1]);
      expect(() => obj.list('l').add(3), throwsUnsupportedError);
    });

    test('merge and without give objects that refuse changes', () {
      final a = JsonObject.of({'a': 1});
      final b = JsonObject.of({'b': 2});
      final merged = JsonObject.merge([a, b]);
      expect(merged, JsonObject.of({'a': 1, 'b': 2}));
      expect(merged.without(['a']), b);
    });
  });

  group('of refuses a value jsonEncode cannot write, naming where', () {
    for (final (name, value, at) in [
      ('a DateTime', <String, Object?>{'at': DateTime(2026)}, 'at'),
      ('NaN', <String, Object?>{'n': double.nan}, 'n'),
      ('infinity', <String, Object?>{'n': double.infinity}, 'n'),
      (
        'one nested in an object',
        <String, Object?>{
          'a': {'b': DateTime(2026)},
        },
        'a.b',
      ),
      (
        'one nested in a list',
        <String, Object?>{
          'a': [1, 2, DateTime(2026)],
        },
        'a[2]',
      ),
      (
        'a map with a key that is not a string',
        <String, Object?>{
          'a': {1: 'x'},
        },
        'a',
      ),
    ]) {
      test(name, () {
        expect(
          () => JsonObject.of(value),
          throwsA(
              isA<JsonFieldException>().having((e) => e.field, 'field', at)),
        );
      });
    }
  });

  group('MutableJsonObject', () {
    test('builds a JsonObject field by field', () {
      final m = MutableJsonObject()
        ..['a'] = 1
        ..['l'] = [1, 2]
        ..['o'] = {'x': true};
      m.remove('a');
      final obj = m.toJsonObject();
      expect(
          obj,
          JsonObject.of({
            'l': [1, 2],
            'o': {'x': true}
          }));
      expect(obj.object('o').boolean('x'), isTrue);
    });

    test('refuses a value jsonEncode cannot write, where it is written', () {
      final m = MutableJsonObject();
      expect(
        () => m['at'] = DateTime(2026),
        throwsA(
            isA<JsonFieldException>().having((e) => e.field, 'field', 'at')),
      );
      expect(
        () => m.addAll({'n': double.nan}),
        throwsA(isA<JsonFieldException>()),
      );
      expect(m, isEmpty);
    });

    test('a JsonObject it made does not change when it does', () {
      final m = MutableJsonObject({'a': 1});
      final obj = m.toJsonObject();
      m['a'] = 2;
      m['b'] = 3;
      expect(obj, JsonObject.of({'a': 1}));
    });

    test('a list it was given is copied when written', () {
      final list = <Object?>[1];
      final m = MutableJsonObject()..['l'] = list;
      list.add(2);
      expect(m.toJsonObject().list('l'), [1]);
    });

    test('toMutable starts from an object, which it leaves alone', () {
      final obj = JsonObject.of({'a': 1});
      final m = obj.toMutable()..['b'] = 2;
      expect(m.toJsonObject(), JsonObject.of({'a': 1, 'b': 2}));
      expect(obj, JsonObject.of({'a': 1}));
    });

    test('is not a JsonObject, and compares by identity', () {
      final Object m = MutableJsonObject({'a': 1});
      expect(m is JsonObject, isFalse);
      expect(JsonObject.parse(m), JsonObject.of({'a': 1}));
      expect(m == MutableJsonObject({'a': 1}), isFalse);
    });

    test('jsonEncode writes it as a map', () {
      expect(jsonEncode(MutableJsonObject({'a': 1})), '{"a":1}');
    });
  });
}

Map<String, Object?> _plain() => {
      'o': <String, Object?>{'x': 1},
      'l': <Object?>[
        1,
        <String, Object?>{'y': 2},
      ],
      's': <Object?>['a'],
    };
