import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:test/test.dart';

void main() {
  group('a map is never a JsonObject at runtime', () {
    final Object map = <String, Object?>{'a': 1};

    test('a cast throws', () {
      expect(() => map as JsonObject, throwsA(isA<TypeError>()));
    });

    test('a type test is false', () {
      expect(map is JsonObject, isFalse);
      expect(switch (map) { JsonObject() => true, _ => false }, isFalse);
    });

    test('parse is the way in', () {
      expect(JsonObject.parse(map)?.integer('a'), 1);
    });
  });

  group('jsonEncode writes it as a map', () {
    test('at the top', () {
      expect(jsonEncode(JsonObject.of({'a': 1})), '{"a":1}');
    });

    test('nested in another object and in a list', () {
      final inner = JsonObject.of({'b': true});
      final outer = JsonObject.of({
        'o': inner,
        'l': [inner],
      });
      expect(jsonEncode(outer), '{"o":{"b":true},"l":[{"b":true}]}');
    });

    test('returned from a toJson, as a vocabulary returns one', () {
      expect(jsonEncode(_Verdict()), '{"shape":"approved"}');
    });

    test('a write through it throws', () {
      final Map<String, Object?> m = JsonObject.of({'a': 1});
      expect(() => m['a'] = 2, throwsUnsupportedError);
    });
  });

  group('a JsonObject placed inside another is read back as itself', () {
    final inner = JsonObject.of({'b': 2});
    final outer = JsonObject.empty.withFields({
      'o': inner,
      'l': [inner],
    });

    test('by object and objects', () {
      expect(outer.object('o').integer('b'), 2);
      expect(outer.objects('l').single.integer('b'), 2);
    });

    test('by parse on raw', () {
      expect(JsonObject.parse(outer.raw('o')), same(inner));
    });

    test('by deepFrozen, as a map', () {
      final frozen = outer.deepFrozen();
      expect(frozen.raw('o'), {'b': 2});
      expect(frozen.object('o').integer('b'), 2);
      expect(jsonEncode(frozen), jsonEncode(outer));
    });
  });

  group('equality is by value', () {
    void same(JsonObject a, JsonObject b) {
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    }

    test('the same fields in another order, all the way down', () {
      same(
        JsonObject.decode('{"a": 1, "b": {"x": [1, {"y": null}], "z": "s"}}'),
        JsonObject.decode('{"b": {"z": "s", "x": [1, {"y": null}]}, "a": 1}'),
      );
    });

    test('a nested JsonObject equals the same fields as a map', () {
      same(
        JsonObject.of({
          'o': JsonObject.of({'k': true})
        }),
        JsonObject.decode('{"o": {"k": true}}'),
      );
    });

    test('1 and 1.0 are equal', () {
      same(JsonObject.of({'n': 1}), JsonObject.of({'n': 1.0}));
    });

    test('different values, extra fields and list order are not equal', () {
      expect(JsonObject.of({'a': 1}), isNot(JsonObject.of({'a': 2})));
      expect(JsonObject.of({'a': 1}), isNot(JsonObject.of({'a': 1, 'b': 2})));
      expect(JsonObject.of({'a': null}), isNot(JsonObject.of({'b': null})));
      expect(
        JsonObject.of({
          'l': [1, 2],
        }),
        isNot(JsonObject.of({
          'l': [2, 1],
        })),
      );
    });

    test('a JsonObject never equals a map', () {
      expect(JsonObject.of({'a': 1}) == ({'a': 1} as Object), isFalse);
    });
  });

  test('toString shows the fields', () {
    expect(JsonObject.of({'a': 1}).toString(), '{a: 1}');
  });

  test('empty is a constant', () {
    const e = JsonObject.empty;
    expect(e.keys, isEmpty);
  });
}

final class _Verdict {
  JsonObject toJson() => const JsonObject.of({'shape': 'approved'});
}
