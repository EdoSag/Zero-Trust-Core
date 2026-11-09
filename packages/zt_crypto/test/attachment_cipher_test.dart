import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zt_crypto/zt_crypto.dart';

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));

  test('round-trips empty, exact-chunk and multi-chunk files', () async {
    for (final n in [0, 1, 16, 17, 32, 33, 100]) {
      final plain = Uint8List.fromList(List.generate(n, (i) => i));
      final sealed = await AttachmentCipher.encrypt(plain,
          key: key, attachmentId: 'a', chunkSize: 16);
      expect(sealed.length, AttachmentCipher.encryptedLength(n, chunkSize: 16));
      expect(
          await AttachmentCipher.decrypt(sealed, key: key, attachmentId: 'a'),
          plain);
    }
  });

  test('wrong key, wrong id, dropped or reordered chunks all fail', () async {
    final plain = Uint8List.fromList(List.generate(40, (i) => i));
    final sealed = await AttachmentCipher.encrypt(plain,
        key: key, attachmentId: 'a', chunkSize: 16);
    Future<void> fails(List<int> bytes, {String id = 'a', List<int>? k}) =>
        expectLater(
            AttachmentCipher.decrypt(bytes, key: k ?? key, attachmentId: id),
            throwsA(isA<AttachmentCorrupt>()));

    await fails(sealed, id: 'b');
    await fails(sealed, k: List.filled(32, 0));
    const chunk = 16 + 28;
    // Drop the last chunk and claim two.
    final dropped = [...sealed.sublist(0, 12 + 2 * chunk)]..[11] = 2;
    await fails(dropped);
    // Swap chunks 0 and 1.
    final swapped = [
      ...sealed.sublist(0, 12),
      ...sealed.sublist(12 + chunk, 12 + 2 * chunk),
      ...sealed.sublist(12, 12 + chunk),
      ...sealed.sublist(12 + 2 * chunk),
    ];
    await fails(swapped);
    await fails(sealed.sublist(0, 8));
    await fails([...'XXXX'.codeUnits, ...sealed.sublist(4)]);
  });
}
