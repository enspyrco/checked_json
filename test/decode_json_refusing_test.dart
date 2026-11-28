import 'dart:convert';

import 'package:checked_json/checked_json.dart';
import 'package:test/test.dart';

/// A backslash, spliced in so a `\u` escape of a printable character is built
/// at run time rather than written out in this file.
const _bs = r'\';

Matcher _duplicate(String key) => isA<FormatException>()
    .having((e) => e.message, 'message', 'duplicate key "$key"');

void main() {
  group('a key named twice in one object is refused', () {
    for (final (name, text, key) in [
      ('at the top level', '{"a": 1, "a": 2}', 'a'),
      (
        'in a nested object',
        '{"x": {"text": "a.docx", "suffix": ".docx", '
            '"suffix": ".pdf"}}',
        'suffix'
      ),
      ('in an object inside a list', '{"x": [1, {"b": 1, "b": 1}]}', 'b'),
      ('in an object inside a top-level list', '[{"b": 1, "b": 1}]', 'b'),
      ('when one spelling is escaped', '{"a": 1, "${_bs}u0061": 2}', 'a'),
      ('when both are escaped differently', r'{"\/": 1, "/": 2}', '/'),
      (
        'as a surrogate pair against the character',
        '{"\u{1F600}": 1, "\\ud83d\\ude00": 2}',
        '\u{1F600}'
      ),
      (
        'after a string value that looks like a key',
        '{"a": "b", "b": 1, "b": 2}',
        'b'
      ),
      ('after a nested object closes', '{"a": {"k": 1}, "k": 1, "a": 2}', 'a'),
    ]) {
      test(name, () {
        expect(() => decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text),
            throwsA(_duplicate(key)));
        if (text.startsWith('{')) {
          expect(() => JsonObject.decode(text), throwsA(_duplicate(key)));
        }
      });
    }
  });

  group('decodes as jsonDecode does', () {
    for (final (name, text) in [
      ('the same key in two sibling objects', '[{"a": 1}, {"a": 2}]'),
      ('the same key at two depths', '{"a": {"a": {"a": 1}}}'),
      ('keys that differ only once unescaped', r'{"a\"": 1, "a\\": 2}'),
      ('a key that is a prefix of another', '{"ab": 1, "a": 2}'),
      (
        'strings holding braces, quotes and commas',
        r'{"k": "{\"k\": 1, ", "j": ["}", "]", ","]}'
      ),
      ('escaped key names', r'{"\n": 1, "\t": 2, "\u0000": 3, "\\": 4}'),
      ('an empty object and list', '{"a": {}, "b": [], "c": [{}]}'),
      (
        'a value of every kind',
        '{"n": null, "t": true, "f": false, '
            '"i": -12, "d": 1.5e3, "s": "x"}'
      ),
      ('a scalar', '"x"'),
      ('whitespace everywhere', ' \n{ "a" :\t[ 1 , { "a" : 2 } ] }\r\n'),
    ]) {
      test(name, () {
        expect(decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text),
            jsonDecode(text));
      });
    }
  });

  group('an integer past 2^53 - 1 in size is refused', () {
    for (final (name, text, offset) in [
      ('one past', '9007199254740992', 0),
      ('the brief case', '[9007199254740993]', 1),
      ('negative', '{"n": -9007199254740992}', 6),
      ('longer', '{"a": [1, 123456789012345678901]}', 10),
    ]) {
      test(name, () {
        expect(
          () => decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('2^53 - 1'))
              .having((e) => e.offset, 'offset', offset)),
        );
      });
    }
    test('through JsonObject.decode', () {
      expect(() => JsonObject.decode('{"n": 9007199254740993}'),
          throwsFormatException);
    });
  });

  group('numbers that decode the same everywhere pass', () {
    for (final (name, text) in [
      ('2^53 - 1', '[9007199254740991, -9007199254740991]'),
      ('a big number with a fraction', '[9007199254740993.0]'),
      ('a big number with an exponent', '[1e300, 9007199254740993e0]'),
      ('a long fraction', '[0.12345678901234567890123]'),
      (
        'a long exponent',
        '[1e-0000000000000000000001, 2E+00000000000000000001]'
      ),
      (
        'digits in a key and a string',
        '{"12345678901234567890": "99999999999999999"}'
      ),
      ('zero and minus zero', '[0, -0, 0.0]'),
    ]) {
      test(name, () {
        expect(decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text),
            jsonDecode(text));
      });
    }
  });

  test('the offset points at the second key', () {
    const text = '{"a": 1, "a": 2}';
    expect(
      () => decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text),
      throwsA(isA<FormatException>().having((e) => e.offset, 'offset', 9)),
    );
  });

  test('text that is not JSON fails as jsonDecode fails', () {
    expect(() => decodeJsonRefusingDuplicateKeysAndUnsafeIntegers('{"a": '),
        throwsFormatException);
    expect(() => JsonObject.decode('{"a": '), throwsFormatException);
  });

  test('JsonObject.decode still refuses JSON of another kind', () {
    expect(() => JsonObject.decode('[1]'), throwsFormatException);
  });

  _integerFieldsAsStrings();
}

void _integerFieldsAsStrings() {
  group('a field named in integerFieldsAsStrings', () {
    const named = {'id'};
    Object? decode(String text) =>
        decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(
          text,
          integerFieldsAsStrings: named,
        );

    test('comes back as its digits, exactly, past 2^53', () {
      expect(
        decode('[{"id": 3856380378147192832, "guid": "g"}]'),
        [
          {'id': '3856380378147192832', 'guid': 'g'},
        ],
      );
    });

    test('is a string when it is small, too', () {
      expect(JsonObject.decode('{"id": 7}', integerFieldsAsStrings: named),
          JsonObject.of({'id': '7'}));
    });

    test('keeps its minus sign', () {
      expect(decode('{"id": -12}'), {'id': '-12'});
    });

    test('is read at any depth', () {
      expect(
        decode('{"a": {"b": [{"id": 9007199254740993}]}}'),
        {
          'a': {
            'b': [
              {'id': '9007199254740993'},
            ],
          },
        },
      );
    });

    test('is matched once its key is unescaped', () {
      expect(decode('{"${_bs}u0069d": 1}'), {'id': '1'});
    });

    test('leaves a fraction, an exponent, a string and a list alone', () {
      const text = '[{"id": 1.5}, {"id": 1e3}, {"id": "x"}, {"id": [1, 2]}]';
      expect(decode(text), jsonDecode(text));
    });

    test('changes no other field, and no field named like it as a value', () {
      const text = '{"n": 1, "k": "id", "l": ["id", 2], "id": 3}';
      expect(decode(text), {
        'n': 1,
        'k': 'id',
        'l': ['id', 2],
        'id': '3',
      });
    });

    test('an unsafe integer in any other field is still refused', () {
      expect(() => decode('{"id": 1, "n": 9007199254740993}'),
          throwsFormatException);
    });

    test('a duplicate key is still refused', () {
      expect(() => decode('{"id": 1, "id": 2}'), throwsFormatException);
    });

    test('text that is not JSON still fails as jsonDecode fails', () {
      expect(() => decode('{"id": 1'), throwsFormatException);
    });
  });
}
