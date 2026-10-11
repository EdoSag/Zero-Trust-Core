import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zt_crypto/zt_crypto.dart';

void main() {
  test('signing keys are the same on every device and differ per app',
      () async {
    final dek = Uint8List.fromList(List.generate(32, (i) => i));
    final notesKey = await KeyHierarchy.appKey(dek, 'notes');
    final a = await KeyHierarchy.signingKeys(notesKey);
    final b = await KeyHierarchy.signingKeys(Uint8List.fromList(notesKey));
    expect(a.publicKeyBytes, b.publicKeyBytes);

    final tasks =
        await KeyHierarchy.signingKeys(await KeyHierarchy.appKey(dek, 'tasks'));
    expect(tasks.publicKeyBytes, isNot(a.publicKeyBytes));

    final sig = await Signing.sign([1, 2, 3], a);
    expect(
        await Signing.verify([1, 2, 3],
            signature: sig, publicKey: b.publicKeyBytes),
        isTrue);
  });
}
