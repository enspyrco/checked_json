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
        expect(() => decodeJsonRefusingDuplicateKeys(text),
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
        expect(decodeJsonRefusingDuplicateKeys(text), jsonDecode(text));
      });
    }
  });

  test('the offset points at the second key', () {
    const text = '{"a": 1, "a": 2}';
    expect(
      () => decodeJsonRefusingDuplicateKeys(text),
      throwsA(isA<FormatException>().having((e) => e.offset, 'offset', 9)),
    );
  });

  test('text that is not JSON fails as jsonDecode fails', () {
    expect(
        () => decodeJsonRefusingDuplicateKeys('{"a": '), throwsFormatException);
    expect(() => JsonObject.decode('{"a": '), throwsFormatException);
  });

  test('JsonObject.decode still refuses JSON of another kind', () {
    expect(() => JsonObject.decode('[1]'), throwsFormatException);
  });
}
