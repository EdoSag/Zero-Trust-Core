import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

Future<ui.Image> _decode(File f) async {
  final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

void main() {
  testWidgets('writes Android, iOS and web icons for an app', (tester) async {
    await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('zt_icons');
      addTearDown(() => root.deleteSync(recursive: true));
      final res = '${root.path}/android/app/src/main/res';
      Directory('$res/mipmap-hdpi').createSync(recursive: true);
      File('$res/mipmap-hdpi/ic_launcher_background.png').writeAsBytesSync([0]);
      final ios = '${root.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset';
      Directory(ios).createSync(recursive: true);
      File('$ios/Contents.json').writeAsStringSync(jsonEncode({
        'images': [
          {'size': '60x60', 'scale': '3x', 'filename': 'Icon-App-60x60@3x.png'},
          {
            'size': '83.5x83.5',
            'scale': '2x',
            'filename': 'Icon-App-83.5x83.5@2x.png'
          },
        ]
      }));
      Directory('${root.path}/web/icons').createSync(recursive: true);

      await ZtLauncherIcons.write(ZtSuite.tasks, root: root.path);

      expect((await _decode(File('$res/mipmap-xxxhdpi/ic_launcher.png'))).width,
          192);
      expect(
          (await _decode(File('$res/mipmap-mdpi/ic_launcher_foreground.png')))
              .width,
          108);
      expect(File('$res/mipmap-hdpi/ic_launcher_background.png').existsSync(),
          isFalse);
      expect(
          File('$res/drawable/ic_launcher_background.xml').readAsStringSync(),
          contains('#6366F1'));
      expect(File('$res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync(),
          contains('<monochrome'));
      expect((await _decode(File('$ios/Icon-App-60x60@3x.png'))).width, 180);
      expect(
          (await _decode(File('$ios/Icon-App-83.5x83.5@2x.png'))).width, 167);
      expect(
          (await _decode(File('${root.path}/web/icons/Icon-maskable-512.png')))
              .width,
          512);
      expect((await _decode(File('${root.path}/web/favicon.png'))).width, 16);
    });
  });
}
