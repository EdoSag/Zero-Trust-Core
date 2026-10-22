# Changelog

Apps depend on the core by git tag (`ref: vX.Y.Z`). Upgrade notes list what
an app must change.

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
