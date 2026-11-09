# Changelog

Apps depend on the core by git tag (`ref: vX.Y.Z`). Upgrade notes list what
an app must change.

## 0.7.2

- **New Tasks mark**: a checklist on cyan instead of a check in a circle on
  blue, which looked too much like Google Tasks. Shows on sign-in, unlock and
  in "Other Zero-Trust apps" in every app.
- **`ZtLauncherIcons`**: draws an app's launcher icons (Android adaptive and
  themed, older Android, iOS, web) from the same brand mark. Upgrade: add
  `tool/launcher_icon_test.dart` and run `flutter test tool/launcher_icon_test.dart`.

## 0.7.1

Fixes sign-in and unlock in apps that include `cryptography_flutter`
(Fitness and Notes): they showed "Something went wrong" before contacting
the server.

- Key derivation (PBKDF2, HKDF, the email salt, the recovery-key checksum)
  now always uses the pure-Dart implementations. With `cryptography_flutter`
  installed, HMAC ran through Android's javax.crypto, which rejects the
  empty HMAC key that HKDF uses when there's no salt. The derived keys are
  byte-for-byte the same as before, so no account or data changes.
- No upgrade steps. Apps can also drop `cryptography_flutter` if they don't
  use it.

## 0.7.0

Shared building blocks the other apps need before they move onto the core.
No breaking changes; pre-core accounts sign in and keep their data exactly
as before.

- **Typed collections** (`ZtCollection<T>`): each kind of item (notes,
  notebooks, tasks, lists, contacts…) gets `fromJson`/`toJson`, `list`,
  `get`, `watch`, `save`, `delete`. Items carry `kind` and a schema version
  (`_v`); older items go through `upgrade` on read, items from a newer app
  version are listed by `newerItems` and never overwritten, and fields the
  app doesn't know are kept on save. A collection with `kind: null` owns
  items without a `kind`, so everything Notes has written stays readable.
- **Encrypted attachments** (`ZtAttachments`, `ztAttachmentsProvider`):
  images, photos and files up to 20 MB, encrypted on the device with their
  own key (kept inside the item) in authenticated 256 KiB chunks
  (`AttachmentCipher` in `zt_crypto`). Stored locally first so they show
  offline; uploads and deletes wait for the network and are retried after
  every sync. Private bucket `zt-attachments`, own folder only.
- **Auto-lock and system screens**: `VaultController.whileShowingSystemUi`
  keeps the vault unlocked while a file/photo picker, permission prompt or
  share sheet covers the app (up to 15 minutes away).
- **"How your data is protected"** screen (`ZtDataProtectionScreen`), linked
  from Settings → Security.
- **Clearer errors**: `ztErrorMessage` also covers sync, storage and
  attachment errors; the sync row says why it failed.
- **New passwords** (sign-up, change, reset) show a strength meter, must
  rate "Good" or better, and are checked against known breaches (Have I Been
  Pwned, k-anonymity: only 5 hex characters of the SHA-1 leave the device;
  skipped when offline). Signing in is never checked.
- **One brand look**: `ZtSuite` lists the four apps with their accents and
  store ids; `ZtBrandMark` on sign-in, unlock and settings; `ZtThemeBuilder`
  applies the app's accent, remembers light/dark/system, and offers
  wallpaper colours (Material You) under Appearance; `ZtSpacing` tokens.
- **Other Zero-Trust apps** section in Settings (needs `onOpenUrl`).

Upgrade notes:

- Wrap `MaterialApp` in `ZtThemeBuilder` instead of passing `ZtTheme.light()`
  yourself (optional, but it's what remembers the theme choice).
- Wrap file pickers, camera and permission prompts in
  `vaultControllerProvider.notifier.whileShowingSystemUi(...)`.
- `ZtTheme.light(accent:)` now uses the accent's tonal colours for the
  secondary roles instead of the raw colour.
- Server: `20261109103420_core_v7_attachments_bucket.sql` (the
  `zt-attachments` bucket) is live since 2026-11-09.
- Android: `api.pwnedpasswords.com` must be reachable (no network-security
  config blocks it by default).

## 0.6.0

Lock and account hardening.

- **Auto-lock on background.** The vault locks when the app returns after
  the auto-lock delay in the background, checked against the clock so it
  works even when the OS suspended the app, or as soon as the app is hidden
  when set to "Immediately". Apps no longer need to call `lock()` themselves.
- **Auto-lock picker** in `ZtSettingsPage`: Immediately, 1, 5, 15 minutes or
  Never, kept in secure storage (`ztAutoLockProvider`,
  `ztPreferencesStoreProvider`). `ZtAppConfig.autoLockAfter` is the default.
- **Email confirmation works.** `AccountService.signUp` throws
  `EmailConfirmationSent` when Supabase requires confirmation, and keys are
  created at the first sign-in instead. `signIn` throws `EmailNotConfirmed`
  before then; `resendConfirmation` sends the link again.
  `ZtSignInScreen` handles both and takes `emailRedirectTo`.
- **Password change and recovery sign out every other device.** Recovery
  also replaces the recovery key that was just used, returned as
  `UnlockResult.newRecoveryKey`.
- **Sensitive actions re-check the password with the server.**
  `changePassword`, the new `newRecoveryKey(password)` and
  `deleteAccount(password:)` sign in again first. The `delete-account`
  function refuses a session without a password sign-in in the last 10
  minutes.
- **Faster unlock.** The password KDF runs on a background isolate, so the
  UI no longer freezes for seconds, and sign-up derives it once instead of
  twice. The unlock button shows a spinner, and `ZtUnlockScreen` takes
  `onForgotPassword`.
- **Clearer errors**: offline, too many attempts, server down, and session
  ended each get their own message.

Upgrade notes:

- `deleteAccount()` is now `deleteAccount(password: ...)`.
- `AccountBackend` has `signUp` returning `bool`, `resendConfirmation` and
  `signOutOtherDevices` (only matters for custom backends).
- Remove any `lock()` call on `AppLifecycleState.paused`; it now overrides
  the user's auto-lock choice.
- Handle `newRecoveryKey` from `ZtResetPasswordScreen` like after sign-up.
- Server: redeploy the `delete-account` function. To require email
  confirmation, turn on "Confirm email" in Supabase Auth.

## 0.5.1

- Locking the vault now really stops sync. Before, `SyncController` picked
  up the engine that had just been closed and kept retrying with it (and
  reopened its realtime subscription) until the next unlock.

No app changes needed.

## 0.5.0

Shared app plumbing, so each app stops building its own.

- `ZtLocalStore`: the on-device store, a SQLite file encrypted as a whole
  (SQLite3 Multiple Ciphers) under a key derived from the app key, one file
  per account. `ztLocalStoreProvider` opens it on unlock and closes it on
  lock; an unreadable file is set aside and re-synced.
- `SyncController` (`ztSyncControllerProvider`): syncs on unlock, on resume,
  2 s after edits, every 5 minutes, and backs off after failures (5 s
  doubling to 5 minutes), plus realtime. Its `SyncStatus` drives the shared
  `ZtSyncStatusTile` ("Synced 2 min ago"), shown by
  `ZtSettingsPage(showSyncStatus: true)`.
- `ztDeviceIdProvider`: a stable per-install id in secure storage.
- `ItemSyncEngine.fromVault` derives the signing keys itself. The engine now
  keeps its own copy of the app key and refuses to run after `close()`, so a
  sync still running when the vault locks can't seal data with a zeroed key.
- `LegacyImporter` and `SyncController.importLegacy`: moves pre-core data
  into synced items once per device, then drops the legacy key
  (`VaultController.forgetLegacyKey`). Imported items are dated 2000-01-01,
  so any real edit wins over them, even one made while another device was
  importing. `ItemSyncEngine.save` takes an optional `at` for this.
- Deleting the account also deletes this app's local store.

Upgrade notes: add to the app's `pubspec.yaml`

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

(without it `ZtLocalStore.open` throws rather than writing plain text).
Apps that keep their own `LocalItemStore` override `ztLocalStoreProvider`.

## 0.4.0

Sync reliability.

- Edit times use a hybrid logical clock, so a phone whose clock is behind no
  longer loses with a later edit.
- Database (`20261022180100_vault_items_future_guard.sql`): `vault_items`
  skips writes dated more than 10 minutes ahead of the server.
- Pulls overlap the last 30 s, so out-of-order commits aren't missed.
- Rows that fail verification or decryption are retried on every sync
  (`SyncResult.rejected` now lists all of them, not just this sync's).
- Changes upload in batches of 200 (`SyncBackend.pushAll` replaces `push`;
  new `SyncBackend.fetch`).
- Migration files renamed to the versions recorded in the live database;
  the deferred Fitness policy fix moved to `supabase/deferred/`.

Upgrade notes: implement `LocalItemStore.dirtyItems`, `rejectedIds` and
`setRejectedIds`. The migration is live since 2026-10-22.

## 0.3.0

- Sign-in sends the raw password only to not-yet-upgraded pre-core accounts
  (`zt_needs_legacy_sign_in`).
- `profiles` key guard and `profile_key_history`.
- Offline unlock from the device's copy of the sealed keys; biometric
  unlock.

Upgrade notes: `flutter_secure_storage ^11`; Android
`FlutterFragmentActivity` and `minSdk` 28; iOS `NSFaceIDUsageDescription`.

## 0.2.0

- `ItemSyncEngine` over `vault_items`; shared sign-in, unlock, recovery and
  settings screens.

## 0.1.0

- `zt_crypto` and the account service.
