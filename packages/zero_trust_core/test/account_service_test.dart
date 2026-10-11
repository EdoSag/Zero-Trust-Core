import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

const fast = KdfParams(iterations: 1000);

/// In-memory stand-in for Supabase Auth + the `profiles` table. Records every
/// password the "server" ever receives, so tests can assert it never sees
/// the real one.
class FakeBackend implements AccountBackend {
  final Map<String, String> authPasswords = {};
  final Map<String, ProfileRecord> profiles = {};
  final List<String> passwordsSeenByServer = [];
  String? _user;
  bool failNextPasswordUpdate = false;

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
  Future<void> signUp(String email, String authPassword) async {
    passwordsSeenByServer.add(authPassword);
    authPasswords[email] = authPassword;
    _user = email;
  }

  @override
  Future<void> updateAuthPassword(String authPassword) async {
    if (failNextPasswordUpdate) {
      failNextPasswordUpdate = false;
      throw Exception('network');
    }
    passwordsSeenByServer.add(authPassword);
    authPasswords[_user!] = authPassword;
  }

  @override
  Future<void> signOut() async => _user = null;

  @override
  Future<ProfileRecord?> fetchProfile() async => profiles[_user];

  @override
  Future<void> writeV2Keys({
    required Uint8List kdfSalt,
    required Map<String, Object?> kdfParams,
    required Uint8List wrappedDek,
    required Uint8List recoveryWrappedDek,
  }) async {
    profiles[_user!] = ProfileRecord(
      legacySalt: profiles[_user]?.legacySalt,
      keyVersion: 2,
      kdfSalt: kdfSalt,
      kdfParams: kdfParams,
      wrappedDek: wrappedDek,
      recoveryWrappedDek: recoveryWrappedDek,
    );
  }

  @override
  Future<void> deleteAccount() async {
    authPasswords.remove(_user);
    profiles.remove(_user);
    _user = null;
  }
}

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

  test('wrong password is rejected', () async {
    await service.signUp(email: email, password: password);
    await service.signOut();
    expect(service.signIn(email: email, password: 'wrong password!!'),
        throwsA(isA<InvalidCredentials>()));
  });

  test('legacy account is upgraded and keeps its existing data key', () async {
    // What today's apps did: Supabase password = raw password, data key =
    // PBKDF2(password, profiles.salt), salt written unpadded (Contacts/Tasks).
    final legacySalt = Kdf.newSalt();
    final todaysKey =
        await Kdf.deriveMasterKey(password: password, salt: legacySalt, params: fast);
    backend.authPasswords[email] = password;
    backend.profiles[email] = ProfileRecord(legacySalt: ZtBase64.encode(legacySalt));

    final upgraded = await service.signIn(email: email, password: password);
    expect(upgraded.dek, todaysKey);
    expect(upgraded.newRecoveryKey, isNotNull);
    expect(backend.authPasswords[email], isNot(password));

    await service.signOut();
    final next = await service.signIn(email: email, password: password);
    expect(next.dek, todaysKey);
  });

  test('legacy salt written by Notes (standard base64) also upgrades', () async {
    final legacySalt = Kdf.newSalt();
    backend.authPasswords[email] = password;
    backend.profiles[email] = ProfileRecord(legacySalt: base64.encode(legacySalt));
    final upgraded = await service.signIn(email: email, password: password);
    expect(upgraded.dek,
        await Kdf.deriveMasterKey(password: password, salt: legacySalt, params: fast));
  });

  test('an upgrade interrupted before the auth switch completes next time', () async {
    final legacySalt = Kdf.newSalt();
    backend.authPasswords[email] = password;
    backend.profiles[email] = ProfileRecord(legacySalt: ZtBase64.encode(legacySalt));
    backend.failNextPasswordUpdate = true;

    await expectLater(service.signIn(email: email, password: password), throwsException);
    expect(backend.authPasswords[email], password); // still legacy auth

    final retry = await service.signIn(email: email, password: password);
    expect(retry.dek,
        await Kdf.deriveMasterKey(password: password, salt: legacySalt, params: fast));
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
        recoveryKey: recoveryText.toLowerCase(), newPassword: 'recovered password');
    expect(recovered.dek, created.dek);

    await service.signOut();
    final again = await service.signIn(email: email, password: 'recovered password');
    expect(again.dek, created.dek);
  });

  test('rotating the recovery key invalidates the old one', () async {
    final created = await service.signUp(email: email, password: password);
    final oldKey = await created.newRecoveryKey!.format();
    final newKey = await service.rotateRecoveryKey(Uint8List.fromList(created.dek));
    await expectLater(
        service.recover(recoveryKey: oldKey, newPassword: 'another password'),
        throwsA(anything));
    final ok = await service.recover(
        recoveryKey: await newKey.format(), newPassword: 'another password');
    expect(ok.dek, created.dek);
  });

  test('short passwords are refused before anything is sent', () async {
    expect(() => service.signUp(email: email, password: 'short'), throwsArgumentError);
    expect(backend.passwordsSeenByServer, isEmpty);
  });

  test('delete account removes auth user and profile', () async {
    await service.signUp(email: email, password: password);
    await service.deleteAccount();
    expect(backend.authPasswords, isEmpty);
    expect(backend.profiles, isEmpty);
  });
}
