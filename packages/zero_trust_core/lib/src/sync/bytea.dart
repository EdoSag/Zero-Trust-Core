import 'dart:typed_data';

/// Postgres `bytea` as PostgREST sends and takes it: `\x` and two hex digits
/// per byte. A sync moves every item's blob through here, so both ways work
/// on code units instead of making a string per byte.

const _digits = '0123456789abcdef';

String ztByteaEncode(Uint8List bytes) {
  final out = Uint8List(2 + bytes.length * 2);
  out[0] = 0x5c; // backslash
  out[1] = 0x78; // x
  var o = 2;
  for (final b in bytes) {
    out[o++] = _digits.codeUnitAt(b >> 4);
    out[o++] = _digits.codeUnitAt(b & 0x0f);
  }
  return String.fromCharCodes(out);
}

/// Throws [FormatException] on anything but hex digits (either case), with
/// or without the leading `\x`.
Uint8List ztByteaDecode(String value) {
  final start = value.startsWith(r'\x') ? 2 : 0;
  final length = value.length - start;
  if (length.isOdd) throw FormatException('Odd number of hex digits', value);
  final out = Uint8List(length >> 1);
  for (var i = 0, p = start; i < out.length; i++, p += 2) {
    out[i] = (_nibble(value, p) << 4) | _nibble(value, p + 1);
  }
  return out;
}

int _nibble(String s, int index) {
  final c = s.codeUnitAt(index);
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x61 && c <= 0x66) return c - 0x57;
  if (c >= 0x41 && c <= 0x46) return c - 0x37;
  throw FormatException('Not a hex digit', s, index);
}
