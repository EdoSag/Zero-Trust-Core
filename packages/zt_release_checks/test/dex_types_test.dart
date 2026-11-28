import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zt_release_checks/src/apk/dex_types.dart';

import 'support/fake_files.dart';

Uint8List prefix(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  const classes = [
    'Landroid/app/Activity;',
    'Lcom/example/app/Main;',
    'Lcom/example/tracker/Client;',
    'Lcom/example/tracker/internal/Queue;',
    'Lcom/examples/Other;',
    'Lio/flutter/app/FlutterActivity;',
    'Ljava/lang/Object;',
    'V',
    '[Ljava/lang/String;',
  ];

  test('reads the class names in order', () {
    final dex = DexTypes.parse(fakeDex(classes));
    expect(dex.typeCount, classes.length);
    expect([
      for (var i = 0; i < dex.typeCount; i++) dex.nameAt(i),
    ], [...classes]..sort());
  });

  test('finds a package that is there', () {
    final dex = DexTypes.parse(fakeDex(classes));
    expect(dex.hasPrefix(prefix('Lcom/example/tracker/')), isTrue);
    expect(dex.hasPrefix(prefix('Lio/flutter/')), isTrue);
    expect(dex.hasPrefix(prefix('Landroid/')), isTrue);
    expect(dex.hasPrefix(prefix('[L')), isTrue);
  });

  test('does not find a package that is not there', () {
    final dex = DexTypes.parse(fakeDex(classes));
    expect(dex.hasPrefix(prefix('Lcom/example/trackers/')), isFalse);
    expect(dex.hasPrefix(prefix('Lcom/exampl/')), isFalse);
    expect(dex.hasPrefix(prefix('Lcom/example/tracker/Client;x')), isFalse);
    expect(dex.hasPrefix(prefix('Lzz/')), isFalse);
    expect(dex.hasPrefix(prefix('A')), isFalse);
  });

  test('a package name that only starts another is not a match', () {
    // com.example. must not match com.examples.Other on its own.
    final dex = DexTypes.parse(fakeDex(['Lcom/examples/Other;']));
    expect(dex.hasPrefix(prefix('Lcom/example/')), isFalse);
    expect(dex.hasPrefix(prefix('Lcom/examples/')), isTrue);
  });

  test('the fast search agrees with walking every name', () {
    final many = [
      for (var a = 0; a < 40; a++)
        for (var b = 0; b < 25; b++) 'Lp$a/q$b/C${a * b};',
    ];
    final dex = DexTypes.parse(fakeDex(many));
    final wanted = [
      for (var a = 0; a < 45; a++) 'Lp$a/',
      for (var b = 0; b < 30; b++) 'Lp7/q$b/',
      'L',
      'Lp',
      'M',
      'Lp39/q24/C936;',
      'Lp39/q24/C937;',
    ];
    for (final text in wanted) {
      expect(
        dex.hasPrefix(prefix(text)),
        dex.hasPrefixSlow(prefix(text)),
        reason: text,
      );
    }
  });

  test('an empty code file has nothing in it', () {
    final dex = DexTypes.parse(fakeDex(const [], otherStrings: const []));
    expect(dex.typeCount, 0);
    expect(dex.hasPrefix(prefix('L')), isFalse);
  });

  test('refuses what is not a code file', () {
    expect(() => DexTypes.parse(Uint8List(10)), throwsFormatException);
    expect(() => DexTypes.parse(Uint8List(200)), throwsFormatException);
  });

  test('refuses tables that point outside the file', () {
    final bytes = fakeDex(classes);
    ByteData.sublistView(bytes).setUint32(0x40, 0x00FFFFFF, Endian.little);
    expect(() => DexTypes.parse(bytes), throwsFormatException);
  });

  test('a type pointing past the strings is refused, not read', () {
    final bytes = fakeDex(classes);
    final data = ByteData.sublistView(bytes);
    final typeIds = data.getUint32(0x44, Endian.little);
    data.setUint32(typeIds, 0x00FFFFFF, Endian.little);
    final dex = DexTypes.parse(bytes);
    expect(() => dex.hasPrefixSlow(prefix('L')), throwsFormatException);
  });
}
