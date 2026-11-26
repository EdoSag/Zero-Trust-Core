# Zero-Trust Core

Shared foundation for every Zero-Trust app: one account, one key hierarchy,
one vault lock, one look. Part of the [Zero-Trust suite](https://zerotrust.bz).

Apps built on it: [Notes](https://github.com/EdoSag/Zero-Trust-Notes), [Tasks](https://github.com/EdoSag/Zero-Trust-Tasks), [Calendar](https://github.com/EdoSag/Zero-Trust-Calendar), [Contacts](https://github.com/EdoSag/Zero-Trust-Contacts), [Phone](https://github.com/EdoSag/Zero-Trust-Phone), [Fitness](https://github.com/EdoSag/Zero-Trust-Fitness), [Meds](https://github.com/EdoSag/Zero-Trust-Meds), [Time](https://github.com/EdoSag/Zero-Trust-Time), [Quests](https://github.com/EdoSag/Zero-Trust-Quests), [Browser](https://github.com/EdoSag/Zero-Trust-Browser), [Clock](https://github.com/EdoSag/Zero-Trust-Clock), [Camera](https://github.com/EdoSag/Zero-Trust-Camera), [Gallery](https://github.com/EdoSag/Zero-Trust-Gallery), [Home](https://github.com/EdoSag/Zero-Trust-Home), [Family](https://github.com/EdoSag/Zero-Trust-Family), [Keyboard](https://github.com/EdoSag/Zero-Trust-Keyboard), [Authenticator](https://github.com/EdoSag/Zero-Trust-Authenticator), [Assist](https://github.com/EdoSag/Zero-Trust-Assist),
and the early [Mail](https://github.com/EdoSag/Zero-Trust-Mail). On the phone
each is called "ZT <App>"; in stores and on release pages, "Zero-Trust <App>".

**Zero-knowledge.** Everything an app stores is encrypted on the device, with
keys made from the password, before it is sent. The server holds only
ciphertext, and the password itself is never sent (see
[Key hierarchy](#key-hierarchy) and
[Sign-in never sends the real password](#sign-in-never-sends-the-real-password)).
The recovery key shown at sign-up is the only way back in when the password
is forgotten. What this does and doesn't protect against:
[zerotrust.bz/security](https://zerotrust.bz/security/).

| Path | What |
|---|---|
| `packages/zt_crypto` | Pure Dart: canonical base64, AES-256-GCM sealed boxes, Ed25519, PBKDF2/HKDF, key hierarchy, recovery key |
| `packages/zt_places` | Flutter plugin: on-device place reminders (arrive / leave) and the shared place picker |
| `packages/zt_assist` | Flutter plugin: ask ZT Assist, the private AI on the same phone, to summarize, rewrite, proofread, translate or title a text |
| `packages/zero_trust_core` | Flutter: account service (sign-up, sign-in with legacy upgrade, change password, recovery, delete account), vault lock with auto-lock, shared theme |
| `packages/zt_sharing_ui` | Flutter: the sharing screens every app uses (space members, invite with QR, join, compare codes), English and Hebrew |
| `packages/zt_scheduler` | Pure Dart: the planner behind ZT Calendar's Planner. Fits tasks and habits into free time around events, on the device, and says which blocks to add, move and remove (see its README) |
| `packages/zt_release_checks` | Release checks every app runs in CI: key, sync and sign-in vectors, app setup, database rules (see its README) |
| `supabase/migrations` | The only schema source of truth for the shared Supabase project |
| `supabase/functions` | Edge Functions: `delete-account` and `account-deletion` (account deletion with a 7-day grace and a "Keep my account" link), `change-email`, `sign-in-handoff` (sign in once per phone), `crash-report` (opt-in, not tied to an account) and `planner-ai` (ZT Calendar's optional AI helper, off unless switched on) |
| `android-widget-kit` | The shared look of every app's Android home screen widgets |
| `web-kit`, `tool` | What every web build ships (strict Content Security Policy page, manifest, headers) and the scripts that apply it |

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
      ref: v1.0.1  # always pin a release tag; see CHANGELOG.md
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

### Sign in once per phone (S-2)

When another Zero-Trust app on the phone is signed in, `ZtSignInScreen`
shows **Sign in with ZT Notes** (or "with another ZT app" and a list), and
`ZtUnlockScreen` shows **Unlock with ZT Notes**. Tapping it opens that app,
which asks "Sign in to ZT Calendar?", then for the fingerprint or the
password (`ztConfirmIdentity`), and sends back the account's data key and,
to sign in, a one-time sign-in token from the `sign-in-handoff` edge
function. The asking app then has a session of its own; neither app signs
the other out. Accounts from before the core keep their old key
(`legacyDek`).

How it stays private: the request carries a fresh random secret and the
answer is sealed (AES-256-GCM) with a key derived from it. Requests and
answers go over the apps' launch intents, only between apps signed with the
same key (`PackageManager.checkSignatures`); the answer always goes to the
app named as the asker. A made-up request can only make an app ask its
user; a made-up answer doesn't open. A session made this way doesn't count
as a password sign-in, so deleting the account or changing the email still
asks for the password.

Each app needs, once, the answering side around its first screen, inside
the `MaterialApp`:

```dart
MaterialApp(home: const ZtSignInHandoffScope(child: AppGate()))
```

The asking side needs nothing: the buttons appear on their own on Android
when a sibling app is installed. The Android part lives in this package
(`android/`, Java, registered by Flutter like any plugin); its manifest
lists every `ZtSuite` package under `<queries>` (a test keeps them in step).
Other platforms don't show the buttons.

### Auto-lock

The vault locks by itself; apps only call `touch()` on user input. It locks
after the delay the user picks under **Settings → Auto-lock** (Immediately,
1, 5 or 15 minutes, Never; `ZtAppConfig.autoLockAfter` until they pick):
after that long idle, and when the app comes back after that long in the
background (checked against the clock, since a suspended app runs no
timers). "Immediately" locks as soon as the app leaves the screen. The
choice is kept in secure storage, per install. Pass `onForgotPassword` to
`ZtUnlockScreen` to offer the reset flow there too.

**Never, even after closing the app** is an extra, opt-in choice for people
who find unlocking on every open a hassle (Phone, for example). Picking it
explains what it means, asks for the fingerprint or password, and then keeps
the DEK in the Android Keystore / iOS Keychain (`SessionKeyStore`;
`unlocked_this_device` on iOS). `ZtUnlockScreen` uses that copy to open the
vault without asking after the app is closed or the phone restarts (once the
phone itself is unlocked). Data stays encrypted at rest. It is only offered
on phones with a screen lock, and is dropped if the screen lock is removed.
"Lock now", sign-out, account deletion and picking any other choice remove
the kept key. The default and every other choice behave as before; apps need
no code change beyond moving their core pin.

### Account safety

- **Email confirmation.** With "Confirm email" on in Supabase Auth,
  `signUp` throws `EmailConfirmationSent`; keys are created at the first
  sign-in after the user opens the link. Signing in before that throws
  `EmailNotConfirmed`, and `ZtSignInScreen` offers to resend the link. Pass
  the app's deep link as `ZtSignInScreen(emailRedirectTo: ...)`.
- **Sensitive actions re-check the password with the server**: changing
  the password, a new recovery key, and deleting the account. Exporting
  data asks for the fingerprint or password on the device
  (`ztConfirmIdentity`), whatever the auto-lock setting. The
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

#### One family space for the whole suite (S-10)

The ZT Family circle (a space with app `family`) is the family space of
every app. ZT Family creates it and handles members and invites; any other
app opens the same circle and keeps its family items there, and ZT
Family's hub lists them together.

```dart
// Any app: the circles this account belongs to, kept in sync.
final family = ref.watch(ztFamilySpacesProvider);
final circle = family.entries.firstOrNull;

// Save a family item: id "<app>/<kind>/<id>", app-qualified kind, and a
// summary the hub can show without knowing the app's model.
await ref.read(ztFamilySpacesProvider.notifier).save(
  circle!.info.id,
  ZtFamilySpace.itemId('calendar', 'event', event.id),
  ZtFamilySummary(title: event.title, kind: 'calendar.event', at: event.start)
      .addTo({'kind': 'calendar.event', ...event.toJson()}),
);

// Read only your own items back.
final mine = (await circle.space!.store.all())
    .where((i) => ZtFamilySpace.belongsTo(i.itemId, 'calendar'));
```

- Everyone checks the circle with `ZtFamilySpace.policy` (ZT Family's rules:
  only admins write `family.circle`, only a member writes `family.me/<id>/…`).
  Change it only in Core, so all apps agree.
- How to trust the circle travels between the account's apps in its *suite
  notes* (`vault_items` app `suite`, sealed and signed under a key every app
  of the account derives: `VaultUnlocked.suiteKey`). ZT Family copies its
  notes there (circles from before S-10 too, the next time it opens them);
  another app copies them into its own synced store the first time, so it
  opens the circle offline afterwards.

#### Sharing screens (`packages/zt_sharing_ui`)

The screens on top of `ztSpacesProvider`, the same in every app. A separate
package, so apps that don't share don't get the camera permission the QR
scanner needs. Pin it to the same commit as `zero_trust_core`:

```yaml
zt_sharing_ui:
  git: { url: https://github.com/EdoSag/Zero-Trust-Core.git, path: packages/zt_sharing_ui, ref: <sha> }
```

```dart
final name = await ztAskSharingName(context, ref, title: 'Share “Trip”');
final space = await ref.read(ztSpacesProvider.notifier).create(myName: name!);
ZtSpacePage.open(context, spaceId: space.id, title: 'Trip', inviteNow: true);
ZtJoinSpacePage.open(context, initialLink: link);   // from a pasted/opened link
ZtJoinRequestCards(titleOf: (spaceId) => ...);      // on the home screen
```

`ZtSpacePage` lists members (owners can make owner, make member, remove),
people waiting to join, Invite, Leave and Delete for everyone; a person who
answered but isn't let in yet sees the code to compare. `ZtInvitePage` makes a
one-person invite (optionally as owner) with a QR code, Copy and Send.
`ZtJoinSpacePage` refuses links for another app. The name others see is
remembered in the account's own store (`ztSharingNameProvider`). Text comes
from `ZtSharingStrings` (English and Hebrew, by the app's locale); the app's
name comes from `ZtAppConfig.displayName`.

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

### Ask ZT Assist (`packages/zt_assist`)

ZT Assist holds the suite's AI model and runs it on the phone. Any other
Zero-Trust app can hand it a text and get the answer back piece by piece.
The text goes from one app to the other on the same phone and nowhere
else. A separate package, so only apps that use it can see ZT Assist.

```dart
final assist = ZtAssist.instance;               // FakeZtAssist in tests
if (!await assist.isInstalled()) return;        // or offer ZtAssist.installUrl
final answer = assist.ask(const ZtAssistRequest(
    task: ZtAssistTask.summarize, text: noteText));
await for (final event in answer) {
  switch (event) {
    case ZtAssistChunk(:final text): shown += text;
    case ZtAssistDone(:final truncated): /* say so when only the start was read */
  }
}
```

`run` gives the whole answer at once. A failure arrives as a
`ZtAssistException` whose `error` says what to tell the user (not
installed, no model downloaded yet, ZT Assist needs an update, out of
memory). Cancelling the subscription stops the model. The wording of each
job lives in ZT Assist, so it improves for every app with one update of
ZT Assist. Only apps signed with the suite's key are answered, and the
package only talks to a ZT Assist signed with that key. Android only.

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

### Crash reports (opt-in)

Off by default. When the person turns them on (Settings → Security → Crash
reports), uncaught errors become short reports that carry the app and
version, the platform, the UTC date, the error class, a scrubbed message
for programming errors only, and `package:` stack frames. Never: user
content, error messages from exceptions (they can quote input), account,
email, device id or model, locale, time of day, file paths. The person can
read each report exactly as it would be sent, copy it or delete it.

```dart
final crashes = ZtCrashReporter(
  appId: 'notes',
  appVersion: packageVersion,
  // The suite's own destination: the `crash-report` edge function on the
  // same Supabase project the app signs in to. No key or token is sent.
  sink: ZtHttpCrashReportSink.supabase(supabaseUrl),
);
crashes.install(); // before runApp
await crashes.load();
runApp(ProviderScope(overrides: [
  ztCrashReporterProvider.overrideWithValue(crashes),
  // ...
], child: const App()));
```

Without a sink the choices are Off and "Keep on this phone" (read and
copy). With one, "Ask me before sending" and "Send automatically" appear;
call `maybeAskToSendZtCrashReports(context, crashes)` after unlock to offer
sending saved reports. `ZtHttpCrashReportSink` posts the JSON to any
endpoint without an account token.

Where they go: `supabase/functions/crash-report` checks each report (only
the fields above, printable text, sizes, a day in the last 60 days) and
calls `zt_record_crash_report`, which merges reports of the same bug, app
version and day into one counted row of `public.zt_crash_reports`. Only the
owner can read it; `public.zt_crash_groups` lists one row per bug. Rows are
deleted after 90 days, and at most 5,000 new rows a day are taken (past
that the function answers 503 and phones keep their reports). Deploy with
`supabase functions deploy crash-report --no-verify-jwt`.

### App updates (APKs from GitHub)

Builds installed from GitHub releases (`--dart-define=ZT_CHANNEL=direct`,
Android) check for a newer release themselves; store builds never do.

- On launch, at most once a day and once per version, the sign-in and
  unlock screens show "Update available" with the release notes. Settings ›
  About has the same row (tap to update or check again), a switch to turn
  the daily check off, and "Get updates with Obtainium".
- The check is one anonymous request to
  `api.github.com/repos/<repo>/releases/latest`; nothing about the person is
  sent. "Download" opens the signed APK in the browser, which hands it to
  Android's installer. Android only installs it over the app when it is
  signed with the same key, so a swapped file can't replace the app.
- The repository defaults to `EdoSag/<display name with dashes>`
  ("Zero-Trust Notes" -> `EdoSag/Zero-Trust-Notes`); pass
  `ZtAppConfig(releaseRepo: ...)` when it differs.

### Look and feel

`ZtThemeBuilder` gives every app the same theme: brand indigo, the app's
accent from `ZtSuite`, remembered light/dark/system, and optional wallpaper
colours. `ZtBrandMark(app: ZtSuite.notes)` is the app mark; `ZtSpacing` the
spacing steps. Settings shows "How your data is protected" and, with
`onOpenUrl`, the other Zero-Trust apps.

### Tablets and foldables (S-11)

Every shared screen (settings, change email, recovery key, data protection,
plans, crash reports, sharing pages) keeps its content readable on wide
windows: `ZtReadableListView` centres it at most 720 dp wide (forms 560 dp)
while scrolling still works across the whole window. For an app's own
screens:

```dart
ZtWindowClass.of(context)            // compact < 600 <= medium < 840 <= expanded
ZtReadableListView(children: [...])  // instead of ListView for lists and forms

// List and detail: side by side on a tablet, one pane each side of the
// hinge on an open book-style foldable, list only on a phone.
ZtTwoPane(list: notesList, detail: selected ?? const PickANote());
if (!ZtTwoPane.showsBoth(context)) Navigator.push(...);  // phone: own page
```

`ZtTwoPane` follows the reading direction (in Hebrew the list is on the
right) and never puts content under the hinge (`ZtLayout.verticalHinge`).

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
- **Web kit.** `tool/apply_web_kit.sh <app>/web --name ... --supabase-url ...`
  writes the page every web app ships: `index.html` with a strict Content
  Security Policy (scripts only from the app's own site plus WebAssembly;
  network only to the app's site and the account server), a loading screen,
  `manifest.json` so the app installs from the browser, a `_headers` file
  for hosts that send response headers (Cloudflare Pages), and the pinned
  `sqlite3mc.wasm`. Run it again when the kit changes.
- **Fonts from the app's own site.** Flutter on the web downloads Noto fonts
  from Google Fonts for any script the app's font lacks, Hebrew and emoji
  included. The kit's `flutter_bootstrap.js` points that at
  `fallback-fonts/` on the app's site instead; fill it after each build:

  ```sh
  flutter build web --no-web-resources-cdn
  path/to/Zero-Trust-Core/tool/fetch_fallback_fonts.sh build/web
  ```

  (about 11 MB, fetched by the browser one script at a time, only when
  needed; `--with-cjk` adds Chinese, Japanese and Korean).
- **Deploying.** Apps call the reusable workflow
  `.github/workflows/web-deploy.yml` (usage in its header): it writes the
  kit, builds, fetches the fonts, publishes a `SHA256SUMS` of every file
  with the site, and on a release deploys to Cloudflare Pages, whose
  `_headers` support adds the response headers a `<meta>` policy can't
  (`frame-ancestors`, HSTS, COOP). Pull requests only build.
- **Hide what the platform can't do.** Read `ztCapabilitiesProvider`
  (`ZtCapabilities`): `homeScreenWidgets`, `scheduledNotifications`,
  `biometricUnlock`, `onDeviceSpeech`, `onDeviceTextRecognition`,
  `cameraScanning`, `phoneIntegration`, `shareSheet`. Ask for the feature,
  not the platform, and override the provider in tests.
- **Lock policy on the web.** The password is asked on every visit: nothing
  that opens the vault is kept once the page closes. Settings shows two
  rows only in a browser:
  - *Remember on this browser* (off by default). After a warning and the
    password, the DEK is kept in IndexedDB sealed with a **non-extractable**
    AES-GCM key the browser made (`WebSessionKeyStore`). Scripts of this
    site can ask the browser to unseal it; nobody can read the sealing key.
    It is weaker than a phone's hardware store, which the warning says.
    Lock now, sign-out and a timed auto-lock remove it.
  - *Sign out and remove data from this browser*, for shared computers:
    signs out, deletes every IndexedDB database and the site's storage
    (`ztWipeBrowserStorage`), then reloads the page.

`packages/zero_trust_core/example` is a small app that checks the encrypted
store on each platform; CI builds it for the web. Run it on Linux, Windows or macOS by hand (see its README); the Actions runners here cannot reach the Ubuntu package servers to install GTK.

## Home screen widgets

Android widgets in every app use the shared look in
[`android-widget-kit/`](android-widget-kit/README.md): copy it in with
`android-widget-kit/apply.sh <app repo> <accent>`.

## Tests

```bash
(cd packages/zt_crypto && dart pub get && dart test)
(cd packages/zt_scheduler && dart pub get && dart test)
(cd packages/zero_trust_core && flutter pub get && flutter test)
(cd packages/zt_sharing_ui && flutter pub get && flutter test)
# Database: every migration plus the guard tests, on a plain Postgres 16
(cd supabase && psql -v ON_ERROR_STOP=1 -f tests/00_supabase_stub.sql \
  $(for f in migrations/*.sql; do echo -f "$f"; done) -f tests/key_guard_test.sql \
  -f tests/vault_items_test.sql -f tests/attachments_test.sql)
```

## Branches and releases

Work happens on `Dev`: pull requests target `Dev`, never `main`. A release is
one `Dev` → `main` pull request, tagged `vX.Y.Z` on `main` afterwards. Apps
depend on the core by tag; [CHANGELOG.md](CHANGELOG.md) says what an app must
change for each version. CI (`.github/workflows/ci.yml`) runs the tests above
with Flutter 3.47.9.

Never add `cryptography_flutter` to the core or an app: it breaks the key
derivation and sign-in fails.

## Support and security

- Help centre: [zerotrust.bz/help](https://zerotrust.bz/help/). Questions and
  account deletion: support@zerotrust.bz.
- Security problems: please report them privately to cyber@zerotrust.bz. What
  the encryption does and doesn't protect against is on
  [zerotrust.bz/security](https://zerotrust.bz/security/).
- [Privacy policy](https://zerotrust.bz/privacy/) and
  [terms](https://zerotrust.bz/terms/).

## License

Copyright (C) 2026 Edo Sagron (https://zerotrust.bz)

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
