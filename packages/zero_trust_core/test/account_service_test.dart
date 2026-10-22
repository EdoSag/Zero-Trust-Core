import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import 'support/fake_backend.dart';

void main() {
  late FakeBackend backend;
  late AccountService service;
  const email = 'edo@example.com';
  const password = 'correct horse battery';

  setUp(() {
    backend = FakeBackend();
    service = AccountService(backend, params: fast, legacyParams: fast);
  });

  test('sign-up then sign-in on another device yields the same DEK', () async {
    final created = await service.signUp(email: email, password: password);
    expect(created.newRecoveryKey, isNotNull);
    await service.signOut();

    final other = AccountService(backend, params: fast);
    final again = await other.signIn(email: email, password: password);
    expect(again.dek, created.dek);
    expect(again.newRecoveryKey, isNull);
  });

  test('the server never receives the real password', () async {
    await service.signUp(email: email, password: password);
    await service.signOut();
    await service.signIn(email: email, password: password);
    expect(backend.passwordsSeenByServer, isNot(contains(password)));
  });

  test('wrong password is rejected and never reaches the server', () async {
    await service.signUp(email: email, password: password);
    await service.signOut();
    await expectLater(
        service.signIn(email: email, password: 'wrong password!!'),
        throwsA(isA<InvalidCredentials>()));
    expect(backend.passwordsSeenByServer, isNot(contains('wrong password!!')));
  });

  test('an unknown email never has its password sent', () async {
    await expectLater(
        service.signIn(email: 'nobody@example.com', password: password),
        throwsA(isA<InvalidCredentials>()));
    expect(backend.passwordsSeenByServer, isNot(contains(password)));
  });

  test('after an upgrade, a typo never sends the raw password', () async {
    final legacySalt = Kdf.newSalt();
    backend.authPasswords[email] = password;
    backend.profiles[email] =
        ProfileRecord(legacySalt: ZtBase64.encode(legacySalt));
    await service.signIn(email: email, password: password);
    expect(backend.profiles[email]!.authUpgraded, isTrue);
    await service.signOut();
    backend.passwordsSeenByServer.clear();

    await expectLater(service.signIn(email: email, password: 'a typo password'),
        throwsA(isA<InvalidCredentials>()));
    expect(backend.passwordsSeenByServer, isNot(contains('a typo password')));
  });

  test('an unrecorded upgrade is recorded at the next sign-in', () async {
    final legacySalt = Kdf.newSalt();
    backend.authPasswords[email] = password;
    backend.profiles[email] =
        ProfileRecord(legacySalt: ZtBase64.encode(legacySalt));
    await service.signIn(email: email, password: password);
    final p = backend.profiles[email]!;
    backend.profiles[email] =
        ProfileRecord(legacySalt: p.legacySalt, keys: p.keys); // mark lost
    await service.signOut();

    await service.signIn(email: email, password: password);
    expect(backend.profiles[email]!.authUpgraded, isTrue);
  });

  test('legacy account is upgraded and keeps its existing data key', () async {
    // What today's apps did: Supabase password = raw password, data key =
    // PBKDF2(password, profiles.salt), salt written unpadded (Contacts/Tasks).
    final legacySalt = Kdf.newSalt();
    final todaysKey = await Kdf.deriveMasterKey(
        password: password, salt: legacySalt, params: fast);
    backend.authPasswords[email] = password;
    backend.profiles[email] =
        ProfileRecord(legacySalt: ZtBase64.encode(legacySalt));

    final upgraded = await service.signIn(email: email, password: password);
    expect(upgraded.dek, todaysKey);
    expect(upgraded.legacyDek, isTrue);
    expect(upgraded.newRecoveryKey, isNotNull);
    expect(backend.authPasswords[email], isNot(password));

    await service.signOut();
    final next = await service.signIn(email: email, password: password);
    expect(next.dek, todaysKey);
  });

  test('legacy salt written by Notes (standard base64) also upgrades',
      () async {
    final legacySalt = Kdf.newSalt();
    backend.authPasswords[email] = password;
    backend.profiles[email] =
        ProfileRecord(legacySalt: base64.encode(legacySalt));
    final upgraded = await service.signIn(email: email, password: password);
    expect(
        upgraded.dek,
        await Kdf.deriveMasterKey(
            password: password, salt: legacySalt, params: fast));
  });

  test('an upgrade interrupted before the auth switch completes next time',
      () async {
    final legacySalt = Kdf.newSalt();
    backend.authPasswords[email] = password;
    backend.profiles[email] =
        ProfileRecord(legacySalt: ZtBase64.encode(legacySalt));
    backend.failNextPasswordUpdate = true;

    await expectLater(
        service.signIn(email: email, password: password), throwsException);
    expect(backend.authPasswords[email], password); // still legacy auth

    final retry = await service.signIn(email: email, password: password);
    expect(
        retry.dek,
        await Kdf.deriveMasterKey(
            password: password, salt: legacySalt, params: fast));
    expect(backend.authPasswords[email], isNot(password));
  });

  test('change password keeps the DEK; old password stops working', () async {
    final created = await service.signUp(email: email, password: password);
    await service.changePassword(
        currentPassword: password, newPassword: 'a brand new password');
    await service.signOut();

    expect(service.signIn(email: email, password: password),
        throwsA(isA<InvalidCredentials>()));
    final again =
        await service.signIn(email: email, password: 'a brand new password');
    expect(again.dek, created.dek);
  });

  test('recovery key resets the password and keeps the DEK', () async {
    final created = await service.signUp(email: email, password: password);
    final recoveryText = await created.newRecoveryKey!.format();
    // The Supabase reset-email link gives the app a session; simulate it.
    final recovered = await service.recover(
        recoveryKey: recoveryText.toLowerCase(),
        newPassword: 'recovered password');
    expect(recovered.dek, created.dek);

    await service.signOut();
    final again =
        await service.signIn(email: email, password: 'recovered password');
    expect(again.dek, created.dek);
  });

  test('rotating the recovery key invalidates the old one', () async {
    final created = await service.signUp(email: email, password: password);
    final oldKey = await created.newRecoveryKey!.format();
    final newKey =
        await service.rotateRecoveryKey(Uint8List.fromList(created.dek));
    await expectLater(
        service.recover(recoveryKey: oldKey, newPassword: 'another password'),
        throwsA(anything));
    final ok = await service.recover(
        recoveryKey: await newKey.format(), newPassword: 'another password');
    expect(ok.dek, created.dek);
  });

  test('short passwords are refused before anything is sent', () async {
    expect(() => service.signUp(email: email, password: 'short'),
        throwsArgumentError);
    expect(backend.passwordsSeenByServer, isEmpty);
  });

  test('upgraded account: the vault exposes the legacy key for old data',
      () async {
    final legacySalt = Kdf.newSalt();
    final todaysKey = await Kdf.deriveMasterKey(
        password: password, salt: legacySalt, params: fast);
    backend.authPasswords[email] = password;
    backend.profiles[email] =
        ProfileRecord(legacySalt: ZtBase64.encode(legacySalt));
    await service.signIn(email: email, password: password);
    await service.signOut();
    final again = await service.signIn(email: email, password: password);
    expect(again.legacyDek, isTrue);

    final c = ProviderContainer(overrides: [
      ztAppConfigProvider.overrideWithValue(
          const ZtAppConfig(appId: 'tasks', displayName: 'Zero-Trust Tasks')),
    ]);
    addTearDown(c.dispose);
    await c
        .read(vaultControllerProvider.notifier)
        .unlock(again.dek, legacyDek: again.legacyDek);
    final state = c.read(vaultControllerProvider) as VaultUnlocked;
    expect(state.legacyKey, todaysKey);
    expect(state.appKey, isNot(todaysKey));
  });

  test('new accounts have no legacy key', () async {
    final created = await service.signUp(email: email, password: password);
    expect(created.legacyDek, isFalse);
  });

  test(
      'password change interrupted after the auth switch completes on next sign-in',
      () async {
    final created = await service.signUp(email: email, password: password);
    backend.failWritesAfter = 1; // pending write ok, final promote fails
    await expectLater(
        service.changePassword(
            currentPassword: password, newPassword: 'a brand new password'),
        throwsException);
    await service.signOut();

    final again =
        await service.signIn(email: email, password: 'a brand new password');
    expect(again.dek, created.dek);
    expect(backend.profiles[email]!.keys!.pendingWrappedDek, isNull);
    await service.signOut();
    expect(
        (await service.signIn(email: email, password: 'a brand new password'))
            .dek,
        created.dek);
  });

  test(
      'password change interrupted before the auth switch keeps the old password',
      () async {
    final created = await service.signUp(email: email, password: password);
    backend.failNextPasswordUpdate = true;
    await expectLater(
        service.changePassword(
            currentPassword: password, newPassword: 'a brand new password'),
        throwsException);
    await service.signOut();
    expect((await service.signIn(email: email, password: password)).dek,
        created.dek);
  });

  test('sign-up interrupted before keys were stored is finished by sign-in',
      () async {
    backend.failWritesAfter = 0;
    await expectLater(
        service.signUp(email: email, password: password), throwsException);
    await service.signOut();

    final finished = await service.signIn(email: email, password: password);
    expect(finished.newRecoveryKey, isNotNull);
    await service.signOut();
    expect((await service.signIn(email: email, password: password)).dek,
        finished.dek);
  });

  test('raising KDF params later does not lock out existing accounts',
      () async {
    const older = KdfParams(iterations: 1000);
    const newer = KdfParams(iterations: 2000);
    final created = await AccountService(backend, params: older)
        .signUp(email: email, password: password);
    await backend.signOut();

    final upgraded =
        AccountService(backend, params: newer, previousParams: const [older]);
    expect((await upgraded.signIn(email: email, password: password)).dek,
        created.dek);
    expect(backend.profiles[email]!.keys!.kdfParams, newer.toJson());
    await backend.signOut();

    // Moved forward: the newest release alone can now sign in.
    expect(
        (await AccountService(backend, params: newer)
                .signIn(email: email, password: password))
            .dek,
        created.dek);
  });

  group('offline unlock', () {
    test('uses the device copy of the keys when the server is unreachable',
        () async {
      final created = await service.signUp(email: email, password: password);
      backend.offline = true;
      final unlocked = await service.unlock(password);
      expect(unlocked.dek, created.dek);
      await expectLater(
          service.unlock('wrong password!!'), throwsA(isA<KeyMismatch>()));
    });

    test('a hung connection falls back after the timeout', () async {
      final slow = _SlowBackend();
      final s = AccountService(slow,
          params: fast, onlineTimeout: const Duration(milliseconds: 50));
      final created = await s.signUp(email: email, password: password);
      slow.hang = true;
      expect((await s.unlock(password)).dek, created.dek);
    });

    test('with no device copy, the network error is shown', () async {
      await service.signUp(email: email, password: password);
      final fresh = AccountService(backend, params: fast);
      backend.offline = true;
      await expectLater(fresh.unlock(password), throwsException);
    });

    test('a password changed on another device works once online', () async {
      final created = await service.signUp(email: email, password: password);
      final other = AccountService(backend, params: fast);
      await other.changePassword(
          currentPassword: password, newPassword: 'a brand new password');

      // This device still has the old copy: offline, the old password works.
      backend.offline = true;
      expect((await service.unlock(password)).dek, created.dek);
      backend.offline = false;
      expect((await service.unlock('a brand new password')).dek, created.dek);
      await expectLater(service.unlock(password), throwsA(isA<KeyMismatch>()));
    });

    test('sign-out forgets the device copy', () async {
      await service.signUp(email: email, password: password);
      await service.signOut();
      await backend.signIn(email, (backend.authPasswords[email])!);
      backend.offline = true;
      await expectLater(service.unlock(password), throwsException);
    });
  });

  group('biometric unlock', () {
    late InMemoryBiometricKeyStore bio;
    late AccountService s;

    setUp(() {
      bio = InMemoryBiometricKeyStore();
      s = AccountService(backend, params: fast, biometrics: bio);
    });

    test('needs the password to turn on, then unlocks without it', () async {
      final created = await s.signUp(email: email, password: password);
      expect(await s.biometricsEnabled(), isFalse);
      await expectLater(
          s.enableBiometrics('wrong password!!'), throwsA(isA<KeyMismatch>()));
      expect(await s.biometricsEnabled(), isFalse);

      await s.enableBiometrics(password);
      expect(await s.biometricsEnabled(), isTrue);
      final unlocked = await s.unlockWithBiometrics();
      expect(unlocked!.dek, created.dek);
    });

    test('cancelling the prompt returns null', () async {
      await s.signUp(email: email, password: password);
      await s.enableBiometrics(password);
      bio.approve = false;
      expect(await s.unlockWithBiometrics(), isNull);
    });

    test('new biometrics enrolled: key dropped, password still works',
        () async {
      final created = await s.signUp(email: email, password: password);
      await s.enableBiometrics(password);
      bio.invalidate(email);
      await expectLater(
          s.unlockWithBiometrics(), throwsA(isA<BiometricKeyInvalidated>()));
      expect(await s.biometricsEnabled(), isFalse);
      expect((await s.unlock(password)).dek, created.dek);
    });

    test('keeps the legacy flag for upgraded accounts', () async {
      backend.authPasswords[email] = password;
      backend.profiles[email] =
          ProfileRecord(legacySalt: ZtBase64.encode(Kdf.newSalt()));
      await s.signIn(email: email, password: password);
      await s.enableBiometrics(password);
      expect((await s.unlockWithBiometrics())!.legacyDek, isTrue);
    });

    test('unavailable hardware refuses to turn on', () async {
      bio.available = false;
      await s.signUp(email: email, password: password);
      expect(await s.biometricsAvailable(), isFalse);
      await expectLater(s.enableBiometrics(password), throwsStateError);
    });

    test('still works after a password change (same DEK)', () async {
      final created = await s.signUp(email: email, password: password);
      await s.enableBiometrics(password);
      await s.changePassword(
          currentPassword: password, newPassword: 'a brand new password');
      expect((await s.unlockWithBiometrics())!.dek, created.dek);
    });

    test('sign-out and account deletion remove it', () async {
      await s.signUp(email: email, password: password);
      await s.enableBiometrics(password);
      await s.signOut();
      await backend.signIn(email, backend.authPasswords[email]!);
      expect(await s.biometricsEnabled(), isFalse);

      await s.enableBiometrics(password);
      await s.deleteAccount();
      expect(await bio.isEnabled(email), isFalse);
    });
  });

  test('delete account removes auth user and profile', () async {
    await service.signUp(email: email, password: password);
    await service.deleteAccount();
    expect(backend.authPasswords, isEmpty);
    expect(backend.profiles, isEmpty);
  });
}

/// Profile reads hang (a captive portal, a dead connection) once [hang] is set.
class _SlowBackend extends FakeBackend {
  bool hang = false;

  @override
  Future<ProfileRecord?> fetchProfile() =>
      hang ? Completer<ProfileRecord?>().future : super.fetchProfile();
}
