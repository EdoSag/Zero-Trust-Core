// Zero-Trust release checks. `dart run zt_release_checks` copies this file
// into the app's test folder, runs it with the app's own dependencies, and
// deletes it again. Don't commit the copy; change the template in
// Zero-Trust-Core/packages/zt_release_checks/templates instead.
//
// Every value below was made by core 0.11 and checked independently with
// Python (hashlib, hmac, cryptography). If one fails, a dependency bump or a
// code change has changed how keys are made or data is sealed, and existing
// accounts or synced data would no longer open. Never update the expected
// values to make a check pass.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

const appId = '{{APP_ID}}';

const _email = 'vector@zero-trust.test';
const _password = 'correct horse battery staple';
const _fast = KdfParams(iterations: 1000);

/// Every app in the suite; an account made in any of them must open in all.
const _suite = [
  'notes',
  'tasks',
  'fitness',
  'contacts',
  'calendar',
  'phone',
  'browser',
  'time',
  'meds',
];

/// App key and signing public key for DEK = 00 01 .. 1f.
const _appKeys = {
  'notes': (
    '9f7d31ba23b1c1d8124b22f4dc7b87d83aa5b31ef2b716b2755a53f641a43926',
    'eb439239cef948b010d5a2d5153cf835c99363a8493ed127f2f9a1a13ba3d8cc',
  ),
  'tasks': (
    '72447d98b94e4b9ae5f244ec49fe2d0c32b87885e304885ee78ebf7734f933de',
    'f2af4b5166647320976992504cae86d23f58bd2e001201f8730e49b6cafc4fb8',
  ),
  'fitness': (
    '24b54d980b25e1d04e9dc1925daaac00efc463654ec0a65a3d12571b237dd4f9',
    '6650b012b083a24440bd5b423951926fb4e4199130fb063948718c6cd44c1960',
  ),
  'contacts': (
    '74bc60bd1b9c1075d45f169c415b528464ef4c3e2beb06b0680cfc6ba661a9eb',
    '27a184e6a1e2b473bdb12537d1084675f3f79d1638710640c69e7f1e22bc014a',
  ),
  'calendar': (
    '69176a9fa3b673d4250d44a67864f523fdf9ded152019f3556afc4a8d11d138b',
    'e30aaab3c7910fa8d60e29685ac01de03bf81d261044d509a3a18780ede5291c',
  ),
  'phone': (
    '93e69f549e39bb841aa1f8f74a8f59042cec4e120dc8c664520b774a86709535',
    'ebdb80fe404a37f2b9a9c08fc21d446705e2d4733e97f264497a03514d042a83',
  ),
  'browser': (
    '771af478ab6840bfa393abf3784f998eae2d140d4ad8b4b8526c4ff7f4270ea4',
    '16fc2a4fcea82ee957cf832c620e53d70d0f363f8b82473be6492c673f62efda',
  ),
  'time': (
    '3069d1f6572d582be734870060933de62b8afb1292fcf7e501425d60e8ab5aeb',
    '9afd1f41e95877294fb6fb6de35695fad9468b26a70a0a7efd10be3f5d292fc7',
  ),
  'meds': (
    'a00141d9453fe804b4ba4a367bc77fa0231a29370b62ecd86e5e40e512bb5af0',
    '8fbd62513195046dc1dddb9de787e99bfd9a8571583691f3001d8eaf7a1c760d',
  ),
};

/// One synced item per app, sealed and signed by core 0.11 (item
/// `release-check`, 2026-11-14 09:00 UTC): blob, signature.
const _syncedItems = {
  'notes': (
    'XHhz20ENU85Hs+cPRxlk2elVmC/ENYn83pnCo5RNseo2w1Nbl2tbPN6lcVrA2K9rO8Ve60zDNjqv/7HOxgcPIo5g',
    'tzykeNWKecJCa1FtpVaQRyLxtgbgbRMCdsZ+dkAplsDluvwcGZbcuwipys+NOg7KxbQdZoME6KguSbgU/jmaBw==',
  ),
  'tasks': (
    'AeHA48NPXzje2HAmlzHJboZROldhyyOz7GxkcEU620fJYxAJgvd8/LeSclT4s3V6eFhaWXo0DSsPXhHobrn1RQw3',
    'oYsUbdG4iqlUTRBjlnprtcTQ4rerDXTwHhDHuj/bUpc2zyL0Dt7fFCC1T1jCzMmHpzprzQbDjH0HrOQIG1fIBw==',
  ),
  'fitness': (
    '6UR2Ua/qq6cBhk6Uvfqa0pctuhzCU6DSQvE+vvQDbyA4f8iWoF/ZTb6ikGZLJb7pc0A8EM9w/V7c9wb7SZgzuQOS',
    'DdiR6pOY4jzdgZbnyn9IJBsUvWvyghvjforDl7G9xLX0TaopDnD1Q5C5TL+HTH3uy25d5aVSRtZPT+ZJz2SSDQ==',
  ),
  'contacts': (
    '9DBy96wFJipLSvwaUWdBygMnFNOkhX/24aY19sSkmjuI+jpzllwBbIIe9/pcVKmdH/A1qHpBUt695Fdbb28Fuwdb',
    'V3ofSW8khQthL2mcvmKtw/Gf/RdwUhFsanOTs6IrbFvJJCEKYRxFhNoHGaolGQDTdEj2dyYgfSF9tjB0MnXpDA==',
  ),
  'calendar': (
    'cZf4ZzEaVayytT2ERFijXnY7VgnXXlUNjAoT959TI8Fr7PLFbv/ebw+gIx3QmN3+uAUtLn+nSJuAS48WN2WcJq/d',
    '6iGhurabepN0FGpT+9wQoOOVlycmh+emII4sLegIG9fa+QJhi1LN1RbVPo2oWOhyw6rVIJI3nWhPS3xenr3JDQ==',
  ),
  'phone': (
    'FGX3pTstpAvLfOg98FHBia7pEP/J+3rUcc6grt0I/CvYQXU1QJQdiMarOYGD7J8DR5mUtdSUwlC6QoW/UNp115FC',
    '1fbwicfN2MRh52yMkO5Tf8Bstxf4n9axe6OHE7oUDoIGqkFxdioMoN6TrnJHf3aA0a4UrIeKciHsebO46Qb3Ag==',
  ),
  'browser': (
    'uGYT/DjSkl9xCEH0BsWGCIQbTl+pYDdmyQeMlKStZ12Cy8ZcpjIW+z6J0W2RRWGd2qSFBOzSCiEemfFOu0jhRf7T',
    'IC7L5VnTiodBT3zZUBWMp/EAWlzi+9O4QFCK6Zs6IsJzcQi9q5JeL1TiBZXLzUBO5OJsHQdcIzgOP8K1q88SDw==',
  ),
  'time': (
    'F/31rxxBeu4bFKYF8/+hkoredCwU7NAvMcjSPyXJGSvqdB3cVUoN6x3ln28Ayz7V+FJr9gdR4CPuzO8pRD/z0BIs',
    'c9uiBFJP5wB2lvBCrfdvCM+agj7KP53tmKHfTebNFQJBBS9IZpfoRc/JH94Ei33L/ipZhcj7y9d+DmftudFxAQ==',
  ),
  'meds': (
    'qQZez4BiAYDG3ZlT0qCdm2Rdz3IhDVqIyac/QIJbWrPVoYMb8JJrk+WAakPCBmdKYl6/QFpSX/F2/61PhYkHaqp1',
    'OoJmH2sGk4vB/UrhZzr8c867vuJ+gylHUc7+RWjv1PkLNbCH2TwAGYI5J/vhMStSY7X/htddokLXX2Lqb//aDw==',
  ),
};

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

final _dek = Uint8List.fromList(List.generate(32, (i) => i));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app id is one of the suite', () {
    expect(_suite, contains(appId),
        reason: 'Add "$appId" with vectors made by core and checked '
            'independently, in Zero-Trust-Core/packages/zt_release_checks.');
  });

  group('keys: existing accounts still open', () {
    test('email salt, sign-in secret and key-encryption key', () async {
      final salt = await Kdf.saltForEmail(_email);
      expect(_hex(salt), '8c3fde42923154af6c393a6cb24a0dcf');
      final c = await KeyHierarchy.deriveCredentials(
          password: _password, salt: salt, params: _fast);
      expect(c.authSecret, 'XGbet9CZv8NsekltgyS0HcJNhbe-gPYY8bpGEVKiz-8');
      expect(_hex(c.kek),
          '7d3116d1fd66aad7248df427e9e3fabba3bb406db31ea3a9bec3c482c120e7ae');
    });

    test('pre-core data key (what the old apps derived)', () async {
      final key = await Kdf.deriveMasterKey(
          password: _password,
          salt: await Kdf.saltForEmail(_email),
          params: _fast);
      expect(_hex(key),
          '1f4c21241f2bb0d361388f85ecf857fff78d3ba48a253f2f2b30be7a5db8af7a');
    });

    test('keys stored by core 0.7 open with the password and recovery key',
        () async {
      final stored = WrappedKeys(
        kdfSalt: _bytes('8c3fde42923154af6c393a6cb24a0dcf'),
        kdfParams: _fast,
        wrappedDek: _bytes('1af8dabce1b340f66124b0b1fccfea00109889e2f343488a'
            '55acad86db89b3a2c72b88bc6ffe89d5e7cec149c5fe8423ca04149fd0331bf9'
            'ddbdd3c8'),
        recoveryWrappedDek: _bytes('4beb5ffd2710ad9431627d9683172b0995195375'
            '8d46475a5f1d0abbb62e61bcb04bbd9d41f8fa296a1b7abfbd47e6ba8498f8d4'
            'ca87bc85ba9c2f99'),
      );
      const dek =
          '27c06da71e64c52c1d4e7a4fa5ee077c8c41db4b82061a3e15ccbbd08ffd6f98';
      expect(
          _hex(await KeyHierarchy.unlockWithPassword(
              password: _password, stored: stored)),
          dek);
      final recovery = await RecoveryKey.parse(
          'ZT-CGMG-PJFF-2K2H-10HG-09S9-Y832-CBBQ-90DZ-7MTH-7JVQ-R6AP-NZC3-3KQG-CJ');
      expect(
          _hex(await KeyHierarchy.unlockWithRecoveryKey(
              recoveryKey: recovery, stored: stored)),
          dek);
    });

    test("this app's data key and signing key", () async {
      final expected = _appKeys[appId]!;
      final key = await KeyHierarchy.appKey(_dek, appId);
      expect(_hex(key), expected.$1);
      expect(_hex((await KeyHierarchy.signingKeys(key)).publicKeyBytes),
          expected.$2);
    });
  });

  group('sync: data written before still opens', () {
    Future<AppItemCodec> codecFor(String app) async {
      final key = await KeyHierarchy.appKey(_dek, app);
      return AppItemCodec(
          appId: app,
          appKey: key,
          signingKeys: await KeyHierarchy.signingKeys(key));
    }

    RemoteItem golden(String app) {
      final (blob, signature) = _syncedItems[app]!;
      return RemoteItem(
        itemId: 'release-check',
        updatedAt: DateTime.utc(2026, 11, 14, 9),
        deviceId: 'golden',
        dataBlob: base64.decode(blob),
        signature: base64.decode(signature),
      );
    }

    test('an item synced by core 0.11 opens in this app', () async {
      expect(await (await codecFor(appId)).open(golden(appId)),
          {'title': 'Written by core 0.11', 'n': 1});
    });

    test('a new item round-trips and stays sealed', () async {
      final codec = await codecFor(appId);
      final sealed = await codec.seal(
          LocalItem(
            itemId: 'check-2',
            json: const {'text': 'Shalom, release'},
            updatedAt: DateTime.utc(2026, 11, 14),
            dirty: true,
          ),
          'device-a');
      expect(utf8.decode(sealed.dataBlob!, allowMalformed: true),
          isNot(contains('Shalom')));
      expect(await (await codecFor(appId)).open(sealed),
          {'text': 'Shalom, release'});
    });

    test("another app's key can't open or forge this app's data", () async {
      for (final other in _suite.where((a) => a != appId)) {
        await expectLater(
            (await codecFor(other)).open(golden(appId)), throwsA(anything),
            reason: other);
      }
    });
  });

  group('account: one sign-in for every app', () {
    test('an account made in any app opens here with the same key', () async {
      for (final maker in _suite) {
        final backend = _MemoryBackend();
        final created = await AccountService(backend, params: _fast)
            .signUp(email: _email, password: _password);
        await backend.signOut();
        final here = await AccountService(backend, params: _fast)
            .signIn(email: _email, password: _password);
        expect(here.dek, created.dek, reason: 'made in $maker');
        expect(here.newRecoveryKey, isNull, reason: 'made in $maker');
      }
    });

    for (final (name, encode) in [
      ('URL-safe, as Tasks and Contacts wrote it', ZtBase64.encode),
      ('standard base64, as Notes wrote it', base64.encode),
    ]) {
      test('a pre-core account ($name) signs in and keeps its old data key',
          () async {
        final legacySalt = Kdf.newSalt();
        final oldKey = await Kdf.deriveMasterKey(
            password: _password, salt: legacySalt, params: _fast);
        final backend = _MemoryBackend()
          ..authPasswords[_email] = _password
          ..profiles[_email] = ProfileRecord(legacySalt: encode(legacySalt));

        final first =
            await AccountService(backend, params: _fast, legacyParams: _fast)
                .signIn(email: _email, password: _password);
        expect(first.dek, oldKey);
        expect(first.legacyDek, isTrue);
        expect(first.newRecoveryKey, isNotNull);
        expect(backend.authPasswords[_email], isNot(_password),
            reason: 'the server must stop seeing the real password');

        // Every other app, after this one upgraded the account.
        await backend.signOut();
        final again =
            await AccountService(backend, params: _fast, legacyParams: _fast)
                .signIn(email: _email, password: _password);
        expect(again.dek, oldKey);
        expect(again.legacyDek, isTrue);
      });
    }

    test('a wrong password never reaches the server', () async {
      final backend = _MemoryBackend();
      await AccountService(backend, params: _fast)
          .signUp(email: _email, password: _password);
      await backend.signOut();
      backend.passwordsSeenByServer.clear();
      await expectLater(
          AccountService(backend, params: _fast)
              .signIn(email: _email, password: 'wrong horse battery'),
          throwsA(anything));
      expect(backend.passwordsSeenByServer, isNot(contains(_password)));
      expect(backend.passwordsSeenByServer,
          isNot(contains('wrong horse battery')));
    });
  });
}

/// Supabase Auth and the `profiles` table, in memory.
class _MemoryBackend implements AccountBackend {
  final Map<String, String> authPasswords = {};
  final Map<String, ProfileRecord> profiles = {};
  final List<String> passwordsSeenByServer = [];
  String? _user;

  @override
  String? get currentUserId => _user;
  @override
  String? get currentEmail => _user;

  @override
  Future<void> signIn(String email, String authPassword) async {
    passwordsSeenByServer.add(authPassword);
    if (authPasswords[email] != authPassword) throw const InvalidCredentials();
    _user = email;
  }

  @override
  Future<bool> needsLegacySignIn(String email) async {
    final p = profiles[email];
    return p != null &&
        p.legacySalt != null &&
        !p.authUpgraded &&
        (p.keys == null || p.keys!.legacyDek);
  }

  @override
  Future<void> markAuthUpgraded() async {
    final p = profiles[_user!]!;
    profiles[_user!] = ProfileRecord(
        legacySalt: p.legacySalt, keys: p.keys, authUpgraded: true);
  }

  @override
  Future<bool> signUp(String email, String authPassword,
      {String? redirectTo}) async {
    passwordsSeenByServer.add(authPassword);
    authPasswords[email] = authPassword;
    _user = email;
    return true;
  }

  @override
  Future<void> resendConfirmation(String email, {String? redirectTo}) async {}

  @override
  Future<void> signOutOtherDevices() async {}

  @override
  Future<void> updateAuthPassword(String authPassword) async {
    passwordsSeenByServer.add(authPassword);
    authPasswords[_user!] = authPassword;
  }

  @override
  Future<void> signOut() async => _user = null;

  @override
  Future<void> sendPasswordReset(String email, {String? redirectTo}) async {}

  @override
  Future<ProfileRecord?> fetchProfile() async => profiles[_user];

  @override
  Future<void> writeKeys(StoredKeys keys) async {
    profiles[_user!] = ProfileRecord(
      legacySalt: profiles[_user]?.legacySalt,
      keys: keys,
      authUpgraded: profiles[_user]?.authUpgraded ?? false,
    );
  }

  @override
  Future<void> deleteAccount() async {
    authPasswords.remove(_user);
    profiles.remove(_user);
    _user = null;
  }
}
