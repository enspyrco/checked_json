import 'dart:convert';

/// [text] decoded as any JSON value, as `jsonDecode` decodes it, except that
/// two kinds of text are a [FormatException] instead:
///
/// - An object naming the same key twice, which `jsonDecode` keeps only the
///   last value of. Two keys are the same when they are the same once
///   unescaped, so `a` written plainly and `a` written as a `\u` escape of
///   its code (0061) collide. The same key in two different objects is fine.
/// - An integer written without a fraction or exponent whose size is past
///   2^53 - 1 (JavaScript's `Number.MAX_SAFE_INTEGER`). A web build reads it
///   as the nearest double, so `9007199254740993` comes out one less there
///   than on the VM.
///
/// A number written with a `.` or an exponent is a double, and is rounded to
/// the nearest one as `jsonDecode` rounds it, the same on every platform:
/// `9007199254740993.0` decodes as `9007199254740992.0`, and digits past a
/// double's precision are dropped.
///
/// For wire text whose kind is not known until it is looked at, such as a
/// list of objects:
/// `JsonObject.parse(decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(text))`
/// where `JsonObject.parse(jsonDecode(text))` would drop a duplicate's value
/// without a word.
Object? decodeJsonRefusingDuplicateKeysAndUnsafeIntegers(String text) {
  final value = jsonDecode(text);
  _refuseDuplicateKeysAndUnsafeIntegers(text);
  return value;
}

/// Throws a [FormatException] at the first key an object of [text] names a
/// second time, or the first integer past 2^53 - 1 in size. [text] is JSON
/// that `jsonDecode` has already accepted, so this walks its structure
/// without checking its syntax again.
void _refuseDuplicateKeysAndUnsafeIntegers(String text) {
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
      // Outside a string, a digit or minus sign can only start a number.
      case final c when c == _minus || _isDigit(c):
        i = _number(text, i);
      default:
        i++;
    }
  }
}

/// The index just past the number starting at [start] in [text], refusing an
/// integer past 2^53 - 1 in size.
int _number(String text, int start) {
  final digitsStart = text.codeUnitAt(start) == _minus ? start + 1 : start;
  var i = digitsStart;
  while (i < text.length && _isDigit(text.codeUnitAt(i))) {
    i++;
  }
  final digits = text.substring(digitsStart, i);
  // A fraction or exponent makes it a double, and its own digits must not be
  // read as a second number, so the whole of it is passed over here.
  var isInteger = true;
  while (i < text.length &&
      switch (text.codeUnitAt(i)) {
        _dot || _e || _capitalE || _plus || _minus => true,
        final c => _isDigit(c),
      }) {
    isInteger = false;
    i++;
  }
  // JSON writes no leading zeros in an integer, so a longer run of digits is
  // a bigger number, and runs of the same length compare as strings do.
  if (isInteger &&
      (digits.length > _maxSafeInteger.length ||
          digits.length == _maxSafeInteger.length &&
              digits.compareTo(_maxSafeInteger) > 0)) {
    throw FormatException(
      'integer past 2^53 - 1 in size, which a web build reads inexactly',
      text,
      start,
    );
  }
  return i;
}

bool _isDigit(int c) => c >= _zero && c <= _nine;

/// 2^53 - 1, the largest integer that every double between it and zero
/// stands for exactly, so a web build reads it as written.
const _maxSafeInteger = '9007199254740991';

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
const _plus = 0x2B;
const _minus = 0x2D;
const _dot = 0x2E;
const _zero = 0x30;
const _nine = 0x39;
const _e = 0x65;
const _capitalE = 0x45;
const _quote = 0x22;
const _backslash = 0x5C;
const _b = 0x62;
const _f = 0x66;
const _n = 0x6E;
const _r = 0x72;
const _t = 0x74;
const _u = 0x75;
