import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

void main() {
  test('every app once, with its own id and package', () {
    final ids = ZtSuite.apps.map((a) => a.appId).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, containsAll(['calendar', 'meds', 'keyboard', 'authenticator']));
    for (final app in ZtSuite.apps) {
      expect(app.androidPackage, 'dev.sagron.zerotrust${app.appId}');
      expect(ZtSuite.byId(app.appId), same(app));
    }
  });

  test('ZT Authenticator is listed but not offered yet', () {
    expect(ZtSuite.authenticator.androidPackage,
        'dev.sagron.zerotrustauthenticator');
    expect(ZtSuite.authenticator.available, isFalse);
    expect(ZtSuite.apps.where((a) => !a.available),
        [ZtSuite.authenticator, ZtSuite.assist, ZtSuite.privacy]);
  });

  test('ZT Assist is listed but not offered yet', () {
    expect(ZtSuite.byId('assist'), same(ZtSuite.assist));
    expect(
        ZtSuite.byPackage('dev.sagron.zerotrustassist'), same(ZtSuite.assist));
    expect(ZtSuite.assist.available, isFalse);
    // Its chats are part of a full backup.
    expect(ZtBackup.apps, contains('assist'));
  });

  test('ZT Privacy is listed but not offered yet', () {
    expect(ZtSuite.byId('privacy'), same(ZtSuite.privacy));
    expect(ZtSuite.byPackage('dev.sagron.zerotrustprivacy'),
        same(ZtSuite.privacy));
    expect(ZtSuite.privacy.available, isFalse);
    // What the user ticked or accepted on each phone is part of a full
    // backup. The list of installed apps is never stored, so it is not.
    expect(ZtBackup.apps, contains('privacy'));
  });
}
