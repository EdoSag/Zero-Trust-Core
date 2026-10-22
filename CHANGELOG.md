# Changelog

Apps depend on the core by git tag (`ref: vX.Y.Z`). Upgrade notes list what
an app must change.

## 0.4.0

Sync reliability.

- Edit times use a hybrid logical clock, so a phone whose clock is behind no
  longer loses with a later edit.
- Database (`20261023000000_vault_items_future_guard.sql`): `vault_items`
  skips writes dated more than 10 minutes ahead of the server.
- Pulls overlap the last 30 s, so out-of-order commits aren't missed.
- Rows that fail verification or decryption are retried on every sync
  (`SyncResult.rejected` now lists all of them, not just this sync's).
- Changes upload in batches of 200 (`SyncBackend.pushAll` replaces `push`;
  new `SyncBackend.fetch`).
- Migration files renamed to the versions recorded in the live database;
  the deferred Fitness policy fix moved to `supabase/deferred/`.

Upgrade notes: implement `LocalItemStore.dirtyItems`, `rejectedIds` and
`setRejectedIds`. Apply the new migration before shipping.

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
