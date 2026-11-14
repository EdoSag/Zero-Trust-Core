# Changelog

Apps depend on the core by git tag (`ref: vX.Y.Z`). Upgrade notes list what
an app must change.

## Unreleased

- **Widget kit: more icons and lists** (roadmap W4, W6, W7, W9). New kit
  icons checklist, image, message, pin, dropdown and chevron start/end
  (mirrored in Hebrew), an accent ring for "today", and a README section on
  scrolling list widgets (`RemoteViewsCompat`). Resources only: apps copy
  them with `apply.sh`, no Dart change.

## 0.11.0

Sharing between Zero-Trust users, plans groundwork, web and desktop
support, opt-in crash reports and the fixes found while reviewing them.
Apps that share must all be on this version: older ones cannot read the
member records it writes.

### Shared spaces trust chain

Each admin now vouches for a member in a row of their own,
`zt.member/<userId>/by/<adminId>`, which only that admin may write. Before,
a second admin confirming someone re-signed every member row, and a new
device of the creator could no longer learn who is in the space.

**Upgrade note:** every app that shares must move to this version together.
Older builds cannot read the new rows.

### Invite links per app

Invite links are now `https://zerotrust.bz/join/<app>#zt1.…` (the app id
was only after the `#` before). All sharing apps claimed the same `/join`
path, so on a phone with two of them Android opened every invite in the one
installed last. Links in the old form are still read when pasted or scanned.

Upgrade notes: in `AndroidManifest.xml`, change the invite intent filter to
`android:pathPrefix="/join/<appId>"` (for example `/join/meds`). The website
serves `/join/<app>/` from Zero-Trust-Website.
### Space stores and locking

Fix: a vault lock while a shared space's local store was opening could use
the already zeroed key, see the file as unreadable and move it aside (with
any unsynced edits), and leave a store open that nothing closed. The opener
now copies the key first, stops when locked, closes a store that finished
opening too late, and opens each space only once. No app change.

### Invite proof check

Database fix (migration `20261111200000_invite_null_proof`): answering a
shared-space invite with no proof is now refused. Before, it used up the
invite without the link's token. No app change; run the SQL once live.

### Crash fingerprint on the web

Fix: `ZtCrashReport.fingerprintOf` used a 64-bit integer literal, which does
not compile for the web, so the web build of anything using the core failed.
It now computes the same FNV-1a hash with BigInt and always returns 16 hex
digits (it could return a leading minus sign before). No app change.

### Sharing screens

New package `packages/zt_sharing_ui` with the sharing screens, lifted from
Tasks and made app-neutral so Notes, Tasks, Calendar and later apps look the
same: `ZtSpacePage` (members, roles, remove, leave, delete for everyone,
waiting-to-join code), `ZtInvitePage` (QR, copy, send, invite as owner),
`ZtJoinSpacePage` (paste or scan, refuses other apps' links, shows the code),
`ztConfirmJoin`, `ZtJoinRequestCards`, `ztAskSharingName` and
`ztSharingNameProvider` (the shared name, kept in the account's own store as
kind `zt.sharing_name`). English and Hebrew. No change to `zero_trust_core`.

### Z26: web and desktop

The core now builds and runs on the web and on Windows, macOS and Linux.
Additive: Android and iOS apps change nothing.

- **Encrypted local store in the browser.** `ZtLocalStore` opens SQLite3
  Multiple Ciphers as WebAssembly with the file in IndexedDB, encrypted under
  the same key as on a phone. Web apps ship `web/sqlite3mc.wasm` from
  `tool/fetch_sqlite3mc_wasm.sh` (pinned version and checksum).
- **Biometric unlock only where hardware gates the key** (Android, iOS).
  Desktop and web report it unavailable instead of keeping the key in an
  ordinary keychain.
- **One browser tab at a time** per account store (Web Locks); another tab
  gets `LocalStoreInUse`, shown as "already open in another tab" (English and
  Hebrew).
- **Attachments on the web** go into `DatabaseAttachmentCache` (IndexedDB), so
  attachments added offline and their waiting uploads and deletes survive a
  reload.
- **Export on the web** downloads the zip.
- `example/`: a smoke-check app; CI builds it for the web.

### Z25: plan groundwork

Plans and what each allows, with no payment provider yet. Needs migration
`20261111130000_core_v11_plans` on the database. Every account stays on the
free plan, whose limits are exactly the Z17 defaults, so nothing changes for
users. Additive: apps change nothing unless they show the plan.

- **Plans.** `zt_plans` (public catalogue: limits, translated names,
  feature switches such as `drive` or `vpn`) and `zt_subscriptions` (who is
  on which plan, from where: manual, Google Play, App Store or web; status
  and period end). Clients only read; the owner or a later billing webhook
  writes. No payment details are stored, only the store's reference.
- **Limits follow the plan.** `zt_storage_limits_for` now takes a
  per-account override first, then the account's plan, then free. A lapsed
  period keeps the plan for 3 more days so late store renewals don't drop
  anyone to free.
- **Server checks.** `zt_has_feature('drive')` for later features' policies
  and edge functions; `zt_grant_plan(user, plan, until, note)` for the owner
  to give a plan by hand (SQL editor only).
- **In the apps.** `ztPlanProvider` / `ZtPlan` (`has('drive')`, `nameFor`),
  and `ZtPlanTile` ("Plan: Free", renewal date, payment problem), shown by
  `ZtSettingsPage(showPlan: true, onOpenPlans: ...)`. English and Hebrew.
- **Plus plan, hidden.** Migration `20261111150000_core_v11_plus_plan` adds
  `plus` (one plan for every app: 1 GiB synced data, 20 GiB attachments) with
  `offered = false` until payments exist; the owner grants it to beta
  testers with `zt_grant_plan`.

### zt_places: on-device place reminders

New package `packages/zt_places` (Flutter plugin, Android): "remind me when
I arrive at / leave a place" for Notes (N16), Tasks (T11) and later apps.
Separate from `zero_trust_core`, so only apps that use it ask for location.

- **On the phone only.** Android's own `LocationManager` proximity alerts
  (AOSP, no Google Play services). No map tiles and no address search, since
  both send the location to a server. The OS keeps only the place, the
  reminder's title and text, and an app payload.
- **API.** `ZtPlaceReminders.sync(reminders, style:)` makes the watched list
  exactly what the app passes (apps keep reminders and "My places" in their
  own encrypted store). A reminder fires once; a new id arms it again.
  `ZtPlaceTrigger.arrive / leave`; "arrive" set while already there waits
  until the phone has left once. Re-registered after reboot and app update.
- **Per-app look.** `ZtPlaceNotificationStyle`: channel, small icon, lock
  screen title and an optional "Done" button.
- **Events.** `events` stream of fired / done / tap (with the payload),
  including ones queued while the app was closed (`collect()` on unlock and
  resume).
- **Place picker.** `ZtPlacePickerPage`: arrive or leave, "My places", the
  current location, or pasted coordinates and map links (`ZtLatLng.tryParse`
  reads geo:, Google, Apple and OpenStreetMap links), name and radius. English
  and Hebrew (`ZtPlacesStrings`), right to left.
- **Permissions.** `permissions()`, `requestLocation()`,
  `requestBackground()` ("Allow all the time"), `requestNotifications()`,
  `openSettings()`. Tests use `ZtPlaceRemindersFake`.
- **Fixes after review.** An "arrive" reminder set while known to be
  outside, or that has seen the phone leave, now fires on the next arrival
  even within the first two minutes. Events read from the phone's queue
  while no app code listens (before unlock) wait for the first listener
  instead of being dropped. `ZtLatLng.tryParse` returns null instead of
  throwing on a broken %-escape.

Using it from an app:

```yaml
  zt_places:
    git:
      url: https://github.com/EdoSag/Zero-Trust-Core.git
      path: packages/zt_places
      ref: <tag or commit>
```

iOS (region monitoring) is not built yet; `supported` is false there.

### Z24: sharing between Zero-Trust users

Shared spaces: encrypted items several accounts share (a child in Meds; later
shared notes, task lists, calendars, address books). Needs migration
`20261111090000_core_v10_shared_spaces` on the database. Additive: apps that
don't use sharing change nothing.

- **Sharing identity.** `ZtIdentity` (zt_crypto): an X25519 + Ed25519 pair
  derived from the account DEK, the same in every app and on every device,
  never stored on the server. `VaultUnlocked.identity` holds it while
  unlocked; locking zeroes it.
- **Key handover.** `KeyWrap` seals a space key for one person (X25519 with a
  fresh ephemeral key, HKDF, AES-GCM bound to space, epoch and recipient);
  the admin's identity signs every handover.
- **Invites by link and QR code.** `SpaceInviteLink`: the token and the
  inviter's key fingerprint travel only in the link's fragment; the server
  keeps the token's hash. The invitee's answer is sealed under the token, so
  the server can't swap their key. `VerificationCode` gives both phones the
  same 8 digits to compare before the admin confirms.
- **Member list inside the space.** Names and public keys are encrypted,
  admin-signed `zt.member/<userId>` items. Trust starts from the inviter's
  fingerprint and follows admins' signatures; rows from unknown authors,
  forged rows, keys nobody trusted signed, admin-only rows from members and
  rows from removed members are all refused.
- **Roles.** Admin (members, admin-only items) and member. Apps mark their
  admin-only kinds with `SpacePolicy`; the server enforces it too.
- **Removal rotates the key** in the same step (`zt_remove_space_member`);
  when someone leaves or deletes their account, an admin's device rotates on
  its next sync. The last admin leaving promotes the longest-standing member.
- **Sync** reuses `ItemSyncEngine` (now with a pluggable `ItemCodec`; the
  account's own items are byte-for-byte unchanged): offline edits, hybrid
  clock, last-writer-wins, tombstones, live updates, per-space storage limits
  (1 MiB per item, 50 MiB and 100,000 items per space).
- **App wiring.** `ztSpacesProvider` (`SpacesController`) lists, opens and
  syncs the app's spaces (live, on resume, after edits, every 5 minutes, and
  when memberships or keys change), with create, invite, answer, pending
  joins, confirm, remove, roles, rename, leave and delete. Each space has its
  own encrypted local store. `InMemorySpaceServer` stands in for Supabase in
  app tests.
### Owned items in shared spaces

Additive, client side only (no database change).

- **Items owned by one member.** `SpacePolicy(ownedPrefixes: {...})`: an item
  `<prefix><userId>` (or `<prefix><userId>/...`) can be written or deleted
  only by that member, not even by an admin. `SharedSpace.save`/`delete`
  refuse it locally, and other members' devices reject such rows from anyone
  else (the author is signed into every row), so a changed app can't post
  numbers in someone else's name. Fitness challenges use it for each
  person's progress.

## 0.10.0

Hebrew and English in every app.

- **Hebrew** for every core screen (sign-in, unlock, recovery, onboarding,
  "How your data is protected", settings, errors), right-to-left.
- **Language setting** under Settings → Appearance → Language: English (the
  default), עברית, or the phone's language. Kept per install, like the theme
  (`ztLanguageProvider`, `ZtLanguageController.preload()`).
- `ZtLanguages.supported` and `ZtLanguages.delegates` for `MaterialApp`.
- Loading a language sets `Intl.defaultLocale`, so dates and numbers follow
  the app's language.
- Email and recovery key fields stay left-to-right in Hebrew.

Upgrade: in `main()` call `await ZtLanguageController.preload();` before
`runApp`, and give `MaterialApp`
`locale: ref.watch(ztLanguageProvider)`,
`supportedLocales: ZtLanguages.supported` and
`localizationsDelegates: [AppL10n.delegate, ...ZtLanguages.delegates]`.
An app that skips this keeps working in English.

## Unreleased (Android widget kit)

- **Home screen widget kit** (`android-widget-kit/`, roadmap W1-W3). Shared
  Android resources for every app's widgets: rounded corners that follow the
  launcher, Material You colours on Android 12+, light and dark, text styles,
  buttons and icons, plus the rules for the header, the locked state, sizes
  and the "Show details on the home screen" switch. Copied into an app with
  `android-widget-kit/apply.sh <app> <accent>`. No Dart code changes, so no
  new tag is needed.

## Unreleased (database only)

- **Old tables removed.** Migration `20261110120000_drop_unused_tables` drops
  the pre-core tables (`encrypted_vault`, `encrypted_tasks`,
  `encrypted_task_items`, `encrypted_notes`, `encrypted_contacts`, plus the
  never-used `encrypted_sms`, `encrypted_note_items`,
  `encrypted_contact_items`), the old Contacts photo bucket policies and the
  PostGIS extension. No Dart code changes. Apps whose old-data import reads
  these tables must treat a missing table as "nothing to import".

## 0.9.0

Storage limits and server cleanup (Z17), and Supabase advisor fixes (Z18).
Needs the three `20261110…` migrations on the database; until they are
applied the new code behaves exactly like 0.8.1 (no limits are reported, the
storage row stays hidden). No key or sign-in changes.

- **Per-account storage limits.** The server counts each account's synced
  data (`zt_storage_usage`) and refuses growth past its limits: 1 MiB per
  item, 50 MiB and 100,000 items of synced data, 500 MiB of attachments
  (overridable per account in `zt_storage_limits`). Deleting is never
  refused.
- **Sync handles a full account.** Deletes are pushed before edits, so a
  full account can always free space. When the server refuses a batch, the
  engine pushes item by item so everything that fits still goes up; refused
  edits stay on the device, waiting. `SyncResult` / `SyncStatus` gain
  `storageFull` and `tooLarge`, and `ZtSyncStatusTile` says so.
- **Storage row.** `ZtSettingsPage(showStorageUsage: true)` adds
  `ZtStorageTile` ("2.4 MB of 50 MB used", with a bar), backed by
  `ztStorageUsageProvider` (`zt_my_storage()`).
- **Tombstone cleanup.** The server removes deleted-item tombstones after 180
  days (daily `pg_cron` job). A device that hasn't synced for 150 days does a
  full re-sync and drops items the server no longer has
  (`ItemSyncEngine.fullResyncAfter`); its own unpushed edits are kept.
- **Advisor fixes.** The key-history trigger function is no longer callable
  over the API, and PostGIS's `spatial_ref_sys` is read-only to app users.

Upgrade: change the ref to `v0.9.0`. Optionally pass `showStorageUsage: true`
to `ZtSettingsPage`.

## 0.8.1

Faster password unlock. No API, key or database changes: every key comes out
byte for byte the same.

- **Key stretching about 4x faster.** The 600k-round PBKDF2 now runs on a
  dedicated pure-Dart PBKDF2-HMAC-SHA256 (`fast_pbkdf2.dart`) that hashes
  HMAC's key pads once and allocates nothing per round. Since 0.7.1 pinned
  key derivation to the generic pure-Dart classes, a password unlock took
  10-15 seconds on a mid-range phone; this brings it to a few. Checked
  against RFC 7914 vectors, the existing golden vectors and `DartPbkdf2` on
  random inputs. The web keeps the library code.
- **Unlock derives while it fetches.** `AccountService.unlock` with a key
  copy on the device runs the derivation while the server's copy is
  fetched (up to `onlineTimeout`), instead of one after the other. The
  server's copy still wins when it differs.

Upgrade: change the ref to `v0.8.1`.

## 0.8.0

Polish before launch. No breaking changes, no database changes; every
addition is opt-in, and sign-in, keys and sync work exactly as before.

- **Onboarding** (Z12): `ZtOnboardingScreen`, three pages shown once
  (`ztOnboardingSeenProvider`). `ZtSignInScreen(offerBiometrics: true)` offers
  biometric unlock straight after sign-in
  (`AccountService.enableBiometricsAfterSignIn`, no second key derivation).
- **Export my data** (Z4): `ZtSettingsPage(onDataExported: ...)` adds the row;
  it warns, builds a ZIP (`data.json` grouped by kind, decrypted attachments,
  a README) and hands the file to the app, usually for the share sheet.
- **Settings links** (Z5): `termsUrl`, `supportUrl` ("Help and feedback")
  next to `privacyPolicyUrl`, and an "Open-source licences" row.
- **Languages** (Z9): every core string now comes from
  `lib/l10n/zt_en.arb` via `ZtL10n`. English only for now; the wording is
  unchanged. New dependencies: `flutter_localizations`, `intl` (any version),
  `archive`.
- **Accessibility** (Z10): tests on every shared screen, light and dark,
  for tap-target size, labels and text contrast, plus layout at 200% text.
  Headings are marked as headings, sign-in errors are announced, the
  recovery key is read out letter by letter, and the strength meter reads
  its tip.
- **Tests and CI** (Z19): fixed key vectors (checked against Python's
  hashlib) so a dependency bump can't silently change keys; tests that an
  account made in any app, or a pre-core account upgraded in one, opens all
  four; format checks; pinned Flutter 3.47.9; a Deno lint/type-check job for
  the delete-account function; a check that generated strings match the ARB.
- The password dialogs ignore an empty password instead of running the slow
  key derivation.

Upgrade: change `ref:` to `v0.8.0`. Optional: add `ZtL10n.delegate` to
`localizationsDelegates`, pass the new settings parameters, show
`ZtOnboardingScreen` and set `offerBiometrics: true`.

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
