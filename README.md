# Zero-Trust Core

Shared foundation for every Zero-Trust app (Fitness, Contacts, Tasks, Notes, …): one account, one key hierarchy, one vault lock, one look.

| Path | What |
|---|---|
| `packages/zt_crypto` | Pure Dart: canonical base64, AES-256-GCM sealed boxes, Ed25519, PBKDF2/HKDF, key hierarchy, recovery key |
| `packages/zt_places` | Flutter plugin: on-device place reminders (arrive / leave) and the shared place picker |
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
      ref: v0.10.0  # always pin a release tag; see CHANGELOG.md
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

`ZtOnboardingScreen` (privacy promise, recovery key, biometrics) runs once
before the first sign-in; `ztOnboardingSeenProvider` says whether it has.
`ZtSignInScreen(offerBiometrics: true)` offers fingerprint or face unlock
right after signing in, without asking for the password again.

Settings links: `privacyPolicyUrl`, `termsUrl` and `supportUrl` (all opened
through `onOpenUrl`); "Open-source licences" is always there.
`onDataExported` adds "Export my data": a decrypted ZIP of every item and
attachment (`ZtDataExporter`), handed to the app to share.

### Languages

Every app is in English (the default) and Hebrew, chosen under
Settings → Appearance → Language (English, עברית, or the phone's language).
The core's own strings are in `packages/zero_trust_core/lib/l10n/zt_en.arb`
and `zt_he.arb`. An app wires the choice into `MaterialApp` once:

```dart
// main(), before runApp, so the first frame is already in the right language:
await ZtLanguageController.preload();

MaterialApp(
  locale: ref.watch(ztLanguageProvider),
  supportedLocales: ZtLanguages.supported,
  localizationsDelegates: [AppL10n.delegate, ...ZtLanguages.delegates],
)
```

The app's own strings go in its own `lib/l10n/app_en.arb` and `app_he.arb`
(same `flutter gen-l10n` setup). Hebrew turns the app right-to-left: use
`EdgeInsetsDirectional`, `AlignmentDirectional` and `start`/`end` rather than
`left`/`right`, and keep emails, URLs, phone numbers and codes in
`TextDirection.ltr` fields. Loading a language also sets
`Intl.defaultLocale`, so `DateFormat` and `NumberFormat` follow it.

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

### Auto-lock

The vault locks by itself; apps only call `touch()` on user input. It locks
after the delay the user picks under **Settings → Auto-lock** (Immediately,
1, 5 or 15 minutes, Never; `ZtAppConfig.autoLockAfter` until they pick):
after that long idle, and when the app comes back after that long in the
background (checked against the clock, since a suspended app runs no
timers). "Immediately" locks as soon as the app leaves the screen. The
choice is kept in secure storage, per install. Pass `onForgotPassword` to
`ZtUnlockScreen` to offer the reset flow there too.

### Account safety

- **Email confirmation.** With "Confirm email" on in Supabase Auth,
  `signUp` throws `EmailConfirmationSent`; keys are created at the first
  sign-in after the user opens the link. Signing in before that throws
  `EmailNotConfirmed`, and `ZtSignInScreen` offers to resend the link. Pass
  the app's deep link as `ZtSignInScreen(emailRedirectTo: ...)`.
- **Sensitive actions re-check the password with the server**: changing
  the password, a new recovery key, and deleting the account. The
  `delete-account` function also refuses a session whose last password
  sign-in is older than 10 minutes.
- **After a password change or a recovery**, every other device is signed
  out. A recovery also issues a new recovery key (the old one was just typed
  in), returned as `UnlockResult.newRecoveryKey`: show `ZtRecoveryKeyScreen`.

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

Add the encrypted SQLite build to the app's `pubspec.yaml` once:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

Then the core runs sync for the app. While the vault is unlocked,
`ztSyncControllerProvider` opens the account's encrypted local store, syncs
on unlock, on resume, 2 s after edits and every 5 minutes, retries with
backoff after failures, and applies other devices' changes live:

```dart
final sync = ref.read(ztSyncControllerProvider.notifier);
await sync.save(note.id, note.toJson());   // pushed shortly after
await sync.delete(note.id);
final store = await ref.read(ztLocalStoreProvider.future) as ZtLocalStore;
final notes = await store.liveItems();     // store.changes to refresh
ref.watch(ztSyncControllerProvider);       // SyncStatus: lastSyncedAt,
                                           // error, rejected, conflicts
```

`ZtSettingsPage(showSyncStatus: true)` shows the shared "Synced 2 min ago"
row. Keep a provider listening to `ztSyncControllerProvider` (the app's root
widget, for example) so sync runs while the app is open.

- **Local store** (`ZtLocalStore`): one SQLite file per account, encrypted as
  a whole (ChaCha20-Poly1305) under a key derived from the app key, so item
  text, ids and timestamps are unreadable while locked. It closes when the
  vault locks. A file the key can't open is renamed `.unreadable-<time>` and the
  store re-syncs. Apps with their own store override `ztLocalStoreProvider`
  with any `LocalItemStore`.
- **Device id** (`ztDeviceIdProvider`): random per install, kept in secure
  storage.
- **Rows**: every item is its own encrypted, signed row in `vault_items`;
  conflicts are last-writer-wins, and the losing local edit is kept in
  `SyncStatus.conflicts` so the app can offer to restore it.
- **Edit times** come from a hybrid logical clock: never earlier than any
  version the device has seen, so a phone whose clock is behind still wins
  with a later edit. The server skips writes dated more than 10 minutes
  ahead of its own time; they stay dirty and go up once that time arrives.
- **Pulls** reach back 30 s behind the last high-water mark, so rows that
  committed out of order aren't missed.
- **Unreadable rows** (bad signature, failed decryption) are listed in
  `SyncStatus.rejected` and retried on every sync; the status row says so.
- **Uploads** go 200 rows per request.

To drive sync by hand instead, build `ItemSyncEngine.fromVault(...)` and call
`sync()`, `startLive()` and `close()` yourself.

### Typed collections

Each kind of item an app keeps is a `ZtCollection<T>`; several share the
app's store, told apart by the item's `kind`:

```dart
final notes = ZtCollection<Note>(
  kind: null,            // the app's default: items with no kind
  version: 2,            // schema version this build writes
  fromJson: (id, json, updatedAt) => Note.fromJson(id, json, updatedAt),
  toJson: (n) => n.toJson(),   // every field, null for cleared ones
  idOf: (n) => n.id,
  upgrade: (json, from) => {...json, 'pinned': false},  // 1 -> 2
);
final notebooks = ZtCollection<Notebook>(kind: 'notebook', ...);

notes.watch(store);                     // Stream<List<Note>>
await notes.save(sync, store, note);    // synced to every device
await notes.newerItems(store);          // "Update the app to see N items"
```

### Sharing between Zero-Trust users (shared spaces)

A *space* is a set of items several accounts share: a child in Meds, later a
shared notebook, list or calendar. The server sees only who belongs to which
space and sealed, signed rows; names, keys and content stay encrypted.

```dart
final spaces = ref.read(ztSpacesProvider.notifier);
final space = await spaces.create(myName: 'Dana');           // you are admin
await spaces.save(space.id, 'child', {'kind': 'child', ...}); // synced to all

// Invite: share the link, or show link.qrData as a QR code.
final link = await spaces.invite(space.id, role: SpaceRole.member);

// On the other phone (link pasted or scanned):
final join = await spaces.answer(SpaceInviteLink.parse(text), myName: 'Grandpa');
// join.verificationCode, e.g. "4821 0937"

// Back on the admin's phone, after both read out the same code:
final pending = await spaces.pendingJoins(space.id);
await spaces.confirm(pending.single);   // or revokeInvite(...) if it differs

await spaces.remove(space.id, userId);  // new key for everyone else
ref.watch(ztSpacesProvider)             // spaces, their stores and status
```

- Read a space's items from `entry.space!.store` (a `ZtLocalStore`; use a
  `ZtCollection` on it like on the app's own store).
- Mark what only admins may write with `ztSpacePolicyProvider`
  (`SpacePolicy(adminOnlyKinds: {...})`).
- Every member holds every key epoch they were given, so history stays
  readable; a removed member gets nothing written after their removal.
- Invite links look like `https://zerotrust.bz/join#zt1.<app>.…`; register
  that link (or let users paste it) in the app.

### Place reminders (`packages/zt_places`)

"Remind me when I arrive at / leave a place", watched by the phone itself
(Android's `LocationManager` proximity alerts; no Google Play services, no
map tiles, no address search), so the location never leaves the phone. A
separate package, so only apps that use it ask for location.

```dart
final places = ZtPlaceRemindersAndroid();       // ZtPlaceRemindersFake in tests
final choice = await ZtPlacePickerPage.show(context,
    reminders: places, savedPlaces: myPlaces, newId: newUuid);
await places.sync([
  ZtPlaceReminder(id: '$noteId@$setAt', place: choice!.place,
      trigger: choice.trigger, title: note.title, payload: noteId),
], style: const ZtPlaceNotificationStyle(
    channelId: 'place_reminders', channelName: 'Place reminders'));
places.events.listen((e) { /* fired, done, tap: e.payload */ });
await places.collect();                         // on unlock and resume
```

Keep reminders and "My places" in the app's own encrypted store and pass
the full list to `sync` whenever it changes. iOS is not built yet.

### Attachments

```dart
final files = await ref.read(ztAttachmentsProvider.future);
final photo = await files.put(bytes, mimeType: 'image/jpeg');
note = note.copyWith(images: [...note.images, photo.toJson()]);  // ref in the item
final shown = await files.read(ZtAttachmentRef.fromJson(json));
await files.delete(ref);   // when the item or image is removed
```

Each file has its own key, stored in the item (so only the account can read
it), and is encrypted in authenticated chunks before it leaves the device.
Wrap pickers in `whileShowingSystemUi` so auto-lock doesn't fire while the
picker is open.

### Look and feel

`ZtThemeBuilder` gives every app the same theme: brand indigo, the app's
accent from `ZtSuite`, remembered light/dark/system, and optional wallpaper
colours. `ZtBrandMark(app: ZtSuite.notes)` is the app mark; `ZtSpacing` the
spacing steps. Settings shows "How your data is protected" and, with
`onOpenUrl`, the other Zero-Trust apps.

### Data from before the core

Accounts upgraded from a pre-core app version unlock with
`VaultUnlocked.legacyKey`, the key the old data was encrypted with. Move
that data across once per device, then the key is dropped:

```dart
await ref.read(ztSyncControllerProvider.notifier).importLegacy([
  LegacyImporter(
    source: 'notes-drive-v1',
    read: (legacyKey) async => [
      for (final old in await readOldNotes(legacyKey))
        LegacyRecord(itemId: old.id, json: old.toJson()),
    ],
  ),
]);
```

It syncs first and never replaces an item that already exists (another
device may have imported and edited it), so use the old record's own id.
A failure leaves the import to run again on the next call.

## Web and desktop

The same core builds for the web (any modern browser) and for Windows, macOS
and Linux, with the same zero-trust model: keys are derived and used only in
the browser or on the computer, and the server only ever sees ciphertext.

What is different off the phone:

- **Local store on the web.** `ZtLocalStore` uses SQLite3 Multiple Ciphers
  compiled to WebAssembly and keeps the same encrypted file in the browser's
  IndexedDB, so the browser only holds ciphertext and the vault unlocks
  offline after the first sync. The app must ship the WebAssembly file:

  ```sh
  path/to/Zero-Trust-Core/tool/fetch_sqlite3mc_wasm.sh web/
  ```

  (pinned version and checksum; set `ztSqliteWasmUrl` if it lives elsewhere).
  A store the key can't open is deleted and re-synced, since browsers can't
  rename it aside.
- **One tab at a time.** An account's store can be open in only one browser
  tab (Web Locks); a second tab gets `LocalStoreInUse` ("already open in
  another tab"), so two tabs can't overwrite each other's changes.
- **Build web apps with `--no-web-resources-cdn`**, so the Flutter engine is
  served from the app's own site rather than fetched from Google's CDN.
- **Biometric unlock is Android and iOS only.** Only there is the stored key
  gated by biometrics in hardware; on desktop and the web
  `SecureBiometricKeyStore.isAvailable()` is false and the password unlocks.
- **Attachments on the web** (sealed files plus waiting uploads and deletes)
  are kept in a `DatabaseAttachmentCache` in IndexedDB, so ones added offline
  survive a reload.
- **Export my data on the web** downloads the zip through the browser;
  `onDataExported` is only called on devices.

`packages/zero_trust_core/example` is a small app that checks the encrypted
store on each platform; CI builds it for the web. Run it on Linux, Windows or macOS by hand (see its README); the Actions runners here cannot reach the Ubuntu package servers to install GTK.

## Home screen widgets

Android widgets in every app use the shared look in
[`android-widget-kit/`](android-widget-kit/README.md): copy it in with
`android-widget-kit/apply.sh <app repo> <accent>`.

## Tests

```bash
(cd packages/zt_crypto && dart pub get && dart test)
(cd packages/zero_trust_core && flutter pub get && flutter test)
# Database: every migration plus the guard tests, on a plain Postgres 16
(cd supabase && psql -v ON_ERROR_STOP=1 -f tests/00_supabase_stub.sql \
  $(for f in migrations/*.sql; do echo -f "$f"; done) -f tests/key_guard_test.sql \
  -f tests/vault_items_test.sql -f tests/attachments_test.sql)
```

## License

Copyright (C) 2026 EdoSag (https://zerotrust.bz)

Zero-Trust is open source under the [GNU Affero General Public License v3.0](LICENSE)
(AGPL-3.0-only), the same licence Signal uses.

- You may use, study, change and share the code, including in your own projects.
- If you share a changed version, or run it for other people over a network, you must
  publish your full source code under the same licence.
- This program comes with no warranty; see the licence for details.

Third-party libraries keep their own licences; every app built on this core lists them under
Settings > Open-source licences.

### Name and logo

The AGPL covers the code, not the brand. "Zero-Trust", "ZT", the app names and icons are
reserved. If you publish a fork, give it a different name and icon so nobody mistakes it
for an official Zero-Trust app.

### Servers

The official apps use the Zero-Trust servers. A fork must use its own backend (for
example its own Supabase project) and must not connect to the official servers.

### Contributing

Pull requests are welcome. By sending one you agree that your contribution is licensed
under the AGPL-3.0 and that the copyright holder may also license it under other terms,
including commercially. This keeps the project able to offer paid plans and other licences.
