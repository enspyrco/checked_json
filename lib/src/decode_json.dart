import 'dart:convert';

/// [text] decoded as any JSON value, as `jsonDecode` decodes it, except that
/// an object naming the same key twice is a [FormatException] rather than an
/// object holding only the last of the two values. Two keys are the same when
/// they are the same once unescaped, so `a` written plainly and `a` written
/// as a `\u` escape of its code (0061) collide. The same
/// key in two different objects is fine.
///
/// For wire text whose kind is not known until it is looked at, such as a
/// list of objects: `JsonObject.parse(decodeJsonRefusingDuplicateKeys(text))`
/// where `JsonObject.parse(jsonDecode(text))` would silently drop a value.
Object? decodeJsonRefusingDuplicateKeys(String text) {
  final value = jsonDecode(text);
  _refuseDuplicateKeys(text);
  return value;
}

/// Throws a [FormatException] at the first key an object of [text] names a
/// second time. [text] is JSON that `jsonDecode` has already accepted, so this
/// walks its structure without checking its syntax again.
void _refuseDuplicateKeys(String text) {
  // One entry per open object or list: the keys an object has named so far,
  // or null for a list.
  final open = <Set<String>?>[];
  var expectingKey = false;
  var i = 0;
  while (i < text.length) {
    switch (text.codeUnitAt(i)) {
      case _openBrace:
        open.add(<String>{});
        expectingKey = true;
        i++;
      case _openBracket:
        open.add(null);
        expectingKey = false;
        i++;
      case _closeBrace || _closeBracket:
        open.removeLast();
        expectingKey = false;
        i++;
      case _comma:
        expectingKey = open.last != null;
        i++;
      case _quote:
        final (:key, :end) = _string(text, i);
        if (expectingKey && !open.last!.add(key)) {
          throw FormatException('duplicate key "$key"', text, i);
        }
        expectingKey = false;
        i = end;
      default:
        i++;
    }
  }
}

/// The string whose opening quote is at [start] in [text], unescaped, and the
/// index just past its closing quote.
({String key, int end}) _string(String text, int start) {
  var i = start + 1;
  StringBuffer? unescaped;
  var runStart = i;
  while (true) {
    final c = text.codeUnitAt(i);
    if (c == _quote) {
      final run = text.substring(runStart, i);
      final key = unescaped == null ? run : (unescaped..write(run)).toString();
      return (key: key, end: i + 1);
    }
    if (c != _backslash) {
      i++;
      continue;
    }
    unescaped ??= StringBuffer();
    unescaped.write(text.substring(runStart, i));
    final escaped = text.codeUnitAt(i + 1);
    if (escaped == _u) {
      // One UTF-16 code unit, so a surrogate pair written as two escapes
      // comes out as the same string as the character written plainly.
      unescaped.writeCharCode(
        int.parse(text.substring(i + 2, i + 6), radix: 16),
      );
      i += 6;
    } else {
      unescaped.writeCharCode(switch (escaped) {
        _b => 0x08,
        _f => 0x0C,
        _n => 0x0A,
        _r => 0x0D,
        _t => 0x09,
        // `\"`, `\\` and `\/` stand for the character after the backslash.
        _ => escaped,
      });
      i += 2;
    }
    runStart = i;
  }
}

const _openBrace = 0x7B;
const _closeBrace = 0x7D;
const _openBracket = 0x5B;
const _closeBracket = 0x5D;
const _comma = 0x2C;
const _quote = 0x22;
const _backslash = 0x5C;
const _b = 0x62;
const _f = 0x66;
const _n = 0x6E;
const _r = 0x72;
const _t = 0x74;
const _u = 0x75;
