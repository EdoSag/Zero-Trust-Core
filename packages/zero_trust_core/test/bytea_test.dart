import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/src/sync/bytea.dart';

void main() {
  test('every byte value survives the round trip', () {
    final bytes = Uint8List.fromList(List.generate(256, (i) => i));
    final text = ztByteaEncode(bytes);
    expect(text.startsWith(r'\x000102'), isTrue);
    expect(text.endsWith('fdfeff'), isTrue);
    expect(ztByteaDecode(text), bytes);
  });

  test('reads what Postgres sends, in either case, with or without the prefix',
      () {
    expect(ztByteaDecode(r'\xDEADbeef'), [0xde, 0xad, 0xbe, 0xef]);
    expect(ztByteaDecode('00ff'), [0x00, 0xff]);
    expect(ztByteaDecode(r'\x'), isEmpty);
    expect(ztByteaEncode(Uint8List(0)), r'\x');
  });

  test('refuses text that is not hex', () {
    expect(() => ztByteaDecode(r'\xzz'), throwsFormatException);
    expect(() => ztByteaDecode(r'\xabc'), throwsFormatException);
  });
}
