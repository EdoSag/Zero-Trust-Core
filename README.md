# Zero-Trust Core

Shared foundation for every Zero-Trust app (Fitness, Contacts, Tasks, Notes, …): one account, one key hierarchy, one vault lock, one look.

| Path | What |
|---|---|
| `packages/zt_crypto` | Pure Dart: canonical base64, AES-256-GCM sealed boxes, Ed25519, PBKDF2/HKDF, key hierarchy, recovery key |
| `packages/zero_trust_core` | Flutter: account service (sign-up, sign-in with legacy upgrade, change password, recovery, delete account), vault lock with auto-lock, shared theme |
| `supabase/migrations` | The only schema source of truth for the shared Supabase project |
| `supabase/functions/delete-account` | Edge Function behind in-app account deletion |

## Key hierarchy

```
password -PBKDF2(600k, salt=H(email))-> master key -HKDF-> auth secret  (the only thing Supabase sees)
                                                   -HKDF-> KEK
random DEK, sealed under the KEK and under the recovery key (profiles.wrapped_dek / recovery_wrapped_dek)
DEK -HKDF("zt/app/<id>/v1")-> per-app data key
```

Changing the password re-wraps the DEK; no data is re-encrypted. Accounts created by pre-core app versions are upgraded on first sign-in and keep their existing key as the DEK, so existing data stays readable.

## Using it from an app

```yaml
dependencies:
  zero_trust_core:
    git:
      url: https://github.com/EdoSag/Zero-Trust-Core.git
      path: packages/zero_trust_core
      ref: v0.4.0   # always pin a release tag; see CHANGELOG.md
```

```dart
ProviderScope(
  overrides: [ztAppConfigProvider.overrideWithValue(
    const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'))],
  child: MaterialApp(theme: ZtTheme.light(), darkTheme: ZtTheme.dark(), home: ...),
);
```

### Shared screens

`ZtSignInScreen`, `ZtUnlockScreen`, `ZtRecoveryKeyScreen`,
`ZtForgotPasswordScreen`, `ZtResetPasswordScreen` and `ZtSettingsPage` are the
same in every app. Each auth screen hands back an `UnlockResult`; pass its
`dek` to `vaultControllerProvider.notifier.unlock`, and when
`newRecoveryKey` is set, show `ZtRecoveryKeyScreen` first. Apps add their own
settings rows through `ZtSettingsPage(appSection: [...], backupSection: [...])`.

### Unlock: offline and biometrics

`ZtUnlockScreen` works offline: `AccountService.unlock` keeps the device's
copy of the (sealed) key row and uses it when Supabase doesn't answer within
`onlineTimeout`. When the user turns on **Unlock with biometrics** in
`ZtSettingsPage`, the DEK is kept in the Android Keystore / iOS Keychain
behind strong biometrics, and the unlock screen prompts for it on open.
Enrolling a new fingerprint or face drops the key; the password still works.
Signing out or deleting the account removes both copies.

Each app needs, once:

- Android: `MainActivity` extends `FlutterFragmentActivity`, and
  `minSdkVersion` is at least 28.
- iOS: `NSFaceIDUsageDescription` in `Info.plist`.

### Sign-in never sends the real password

Pre-core accounts still have their raw password as the Supabase password,
so the first sign-in after updating must send it once to upgrade. The client
does that only when `zt_needs_legacy_sign_in(email)` says the account is a
not-yet-upgraded pre-core one; any other failed sign-in stops there. Apply
the `core_v3_*` migrations (live since 2026-10-22) before shipping, or
pre-core accounts can't upgrade.

The same migration guards `profiles`: key material can't be erased or
downgraded, and every replaced key row is kept in `profile_key_history`
(owner read-only, newest 50) so a bad write can be rolled back.

### Sync

```dart
final vault = ref.read(vaultControllerProvider) as VaultUnlocked;
final sync = ItemSyncEngine(
  appId: 'notes',
  appKey: vault.appKey,
  deviceId: deviceId,                 // stable per install
  store: myDriftOrIsarStore,          // implements LocalItemStore
  backend: SupabaseSyncBackend(),
  signingKeys: await KeyHierarchy.signingKeys(vault.appKey),
);
await sync.save(note.id, note.toJson());
final result = await sync.sync();     // pull, then push
sync.startLive();                     // realtime from other devices
```

Every item is its own encrypted, signed row in `vault_items`; conflicts are
last-writer-wins and the losing local edit comes back in
`result.conflicts`, so the app can offer to restore it.

- **Edit times** come from a hybrid logical clock: never earlier than any
  version the device has seen, so a phone whose clock is behind still wins
  with a later edit. The server skips writes dated more than 10 minutes
  ahead of its own time; they stay dirty and go up once that time arrives.
- **Pulls** reach back `pullOverlap` (30 s) behind the last high-water mark,
  so rows that committed out of order aren't missed.
- **Unreadable rows** (bad signature, failed decryption) are listed in
  `result.rejected` and retried on every sync; show a warning while it's
  non-empty.
- **Uploads** go `pushBatchSize` (200) rows per request.

A `LocalItemStore` needs `dirtyItems()` (an indexed query) and
`rejectedIds()` / `setRejectedIds()` besides the basics.

## Tests

```bash
(cd packages/zt_crypto && dart pub get && dart test)
(cd packages/zero_trust_core && flutter pub get && flutter test)
# Database: every migration plus the guard tests, on a plain Postgres 16
(cd supabase && psql -v ON_ERROR_STOP=1 -f tests/00_supabase_stub.sql \
  $(for f in migrations/*.sql; do echo -f "$f"; done) -f tests/key_guard_test.sql \
  -f tests/vault_items_test.sql)
```
