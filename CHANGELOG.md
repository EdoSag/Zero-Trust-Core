# Changelog

Apps depend on the core by git tag (`ref: vX.Y.Z`). Upgrade notes list what
an app must change.

## Unreleased

Nothing for apps to change.

- ZT Assist joins the suite list (`ZtSuite.assist`, app id `assist`), not
  offered in "Other Zero-Trust apps" until it is released. Its chats are
  part of a full backup. The release checks know its keys.
- New package `packages/zt_assist` (Flutter plugin, Android): an app hands
  a text to ZT Assist on the same phone and gets a summary, a rewrite, a
  correction, a translation or a title back, piece by piece. Only apps
  that want it depend on it:

  ```yaml
  zt_assist:
    git:
      url: https://github.com/EdoSag/Zero-Trust-Core.git
      ref: <the same ref as zero_trust_core>
      path: packages/zt_assist
  ```
- `zt_assist` 0.2.0: quick add. `ZtAssistTask.quickAdd` has ZT Assist read
  a typed line ("dentist tomorrow at 9") into a title, a day, a time, a
  length, a reminder and a place, and `ZtAssistQuickAdd.fromAnswer` checks
  the answer before an app uses it. A ZT Assist from before this job
  answers "needs an update".

## 1.0.1

Nothing for apps to change: move to `ref: v1.0.1` like to 1.0.0.

### Review fixes (`zero_trust_core`)

- With "Check for updates" off, opening Settings no longer asks GitHub: the
  row says "Tap to check now." and checks only when tapped (S-1).
- Restoring a full backup into the same account puts back files the server
  lost or damaged for items that are unchanged since the backup. Files of
  items changed or deleted since are still never uploaded (S-5).

## 1.0.0

The first stable release. Every app moves to this tag. It holds sign in
once per phone (S-2), the full backup file (S-5), one family space for the suite (S-10), tablet and
foldable layouts (S-11), the in-app update check with an Obtainium link
(S-1), email change (Z14), crash reports (Z15), the 7-day account deletion
grace (Z22), the retired raw-password sign-in (Z21), every app in the
suite list, and the fix for sync freezing after a large import. Old and
pre-core accounts sign in and see their data as before.

Moving an app from 0.13.0, or from a `backport/import-freeze-fix-on-core-*`
branch, to `ref: v1.0.0`:

- Nothing has to change for the app to build and run. The upgrade notes in
  each section below are optional improvements.
- Worth doing in the same bump: pass
  `sink: ZtHttpCrashReportSink.supabase(supabaseUrl)` for crash reports
  (Z15), build release APKs with `--dart-define=ZT_CHANNEL=direct` for the
  update check (S-1), and override `ztBackupFilesProvider` to offer the full
  backup on phones (S-5), and wrap the first screen in
  `ZtSignInHandoffScope` so other apps can sign in with this one (S-2).
- Database: all migrations up to `20261123130000_core_review_fixes` are
  live. Edge functions `delete-account`, `account-deletion`, `change-email`,
  `crash-report` and `sign-in-handoff` must be deployed for Z14, Z15, Z22
  and S-2 sign-in to work (S-2 unlock works without it).

### Sign in once per phone (S-2)

- New: when another Zero-Trust app on the phone is signed in, the sign-in
  screen offers **Sign in with ZT Notes** and the lock screen **Unlock with
  ZT Notes**. That app asks its user (fingerprint or password) and hands
  over the account's key and, to sign in, a one-time token, so the asking
  app gets a session of its own without the password. Only apps signed
  with the same key take part, and everything that travels between them is
  sealed with a secret only the asking app has. Old accounts keep their
  pre-core key (`legacyDek`).
- The core now has an Android part (`android/`, plain Java), registered by
  Flutter like any plugin. Its manifest adds `<queries>` for the suite's
  packages.
- New `AccountService.handoffGrant`, `signInWithHandoff` and
  `unlockWithHandoff`; optional backend interface `AccountHandoffBackend`
  (the Supabase backend implements it; test fakes don't need to).
- New edge function `sign-in-handoff` (with the session): a one-time
  magic-link token for the signed-in account, made without sending email.
  Deploy with `supabase functions deploy sign-in-handoff`.
- Upgrade: wrap the app's first screen in `ZtSignInHandoffScope`, inside
  the `MaterialApp` (`home: const ZtSignInHandoffScope(child: AppGate())`),
  so it can answer other apps. Without it the app can still ask, but never
  answers.

### Every app in the suite list (`ZtSuite`)

- `ZtSuite.apps` now has all 17 apps, in the website's order: Calendar,
  Browser, Phone, Camera, Gallery, Home, Family, Meds, Keyboard and ZT
  Authenticator join Notes, Tasks, Fitness, Contacts, Time, Quests and
  Clock. Each has its accent, icon, tagline (English and Hebrew) and
  Android package `dev.sagron.zerotrust<id>`.
- New `ZtSuiteApp.available` (default true). ZT Authenticator
  (`authenticator`, `dev.sagron.zerotrustauthenticator`) is `false` until
  it's out: it isn't offered under "Other Zero-Trust apps" yet, but its
  data is in full backups and its own app gets its brand.
- These apps now get their brand mark on the sign-in, unlock and about
  screens. An app that sets `ZtAppConfig.accent` keeps it; one that
  doesn't now gets its suite accent (the same colour as on the website).

### Sync no longer freezes the app after a large import (`zero_trust_core`)

- Every sync re-reads the last 30 seconds before the newest row it has
  seen. After an import that uploads hundreds of items at once, that window
  holds the whole import, so every later sync downloaded it again, and the
  engine checked the signature of and decrypted each row before noticing it
  already had it. On a phone that blocked the screen for many seconds on
  every open, resume and edit ("isn't responding"). A row the device
  already holds, or has a newer version of, is now skipped before any
  crypto.
- Fixed: a pull of more than 500 changed rows read the newest 500 twice and
  never reached the older ones (`order` sorts newest first unless told
  otherwise). Pulls now page oldest first, for the account's own items and
  for shared spaces.
- `bytea` blobs are read and written without making a string per byte.
- The screen keeps drawing and taking taps during an import and a large
  sync. Sealing, signing, checking and decrypting run on the UI isolate, and
  so does the local store; a few hundred items in a row used to run in one
  piece. `ItemSyncEngine` now lets the event loop run every 8 ms of such
  work: while it reads a pull, while it seals and records a push, and while
  an app saves or deletes items one after another (new `Breather`).
- `ZtCollection.watch` reads and decodes only the items that changed, not
  the whole collection on every change. Saving 850 events one by one used
  to decode about 360,000 items along the way.
- `ZtLocalStore.changes` announces a long run of writes (24 or more with
  less than 50 ms between them) in batches about 120 ms apart instead of
  once per item, so an app's own listener that reloads a list isn't run
  hundreds of times in a row. Single writes are announced at once, as
  before.
- A row skipped because the device already holds it still moves the edit
  clock (found in review): after a restart with the device's clock set
  back, the next edit could be stamped older than the version it replaces
  and lose to it.

- A save, a delete or a sync row that needs no pause runs exactly as it did
  before the breather: `Breather.step` and `Breather.enter` return null
  instead of a finished future, so nothing waits an extra turn of the
  microtask queue. (ZT Notes has widget tests that start a save under
  `runAsync` while the engine is still starting on the test's fake clock;
  the extra turn made three of them hang.)

Upgrade notes: nothing to change in apps. No database change. Under
`flutter test` the pauses and the batching are off (the fake clock never
fires their timers), so tests behave as before; pass `Breather(enabled:
true)` or `ZtLocalStore.open(mergeBursts: true)` to test them.

### Encrypted full backup file (S-5; `zero_trust_core`)

- New: Settings, Backup has "Back up everything" and "Restore from a
  backup". One `.ztbackup` file holds every Zero Trust app's data and
  attached files, encrypted with a backup password (at least 12
  characters; PBKDF2 600,000 rounds, then AES-256-GCM in 1 MiB chunks).
  It can be restored into the same account or a new one, on any phone.
  Restoring never overwrites newer changes; a wrong password and a damaged
  or cut file give different messages.
- Each attached file is checked (opened with its own key, at its own size)
  before it goes into the backup; a damaged one is reported as missing.
  Items that can't be opened are left out and the message says how many.
  A restore uploads only the files of the items it restores.
- New API: `ZtBackup.create`, `ZtBackup.checkHeader`, `ZtBackup.open`,
  `ZtBackup.restore`, `ZtBackupTiles`, `ZtBackupFiles` and
  `ztBackupFilesProvider`. `ZtDataExport.findAttachmentRefs` is now public.

Upgrade notes: the rows show on the web by themselves. On phones, an app
turns them on by overriding `ztBackupFilesProvider` with a save and pick
function (for example from `file_picker`); see the `ZtBackupFiles` docs.

### Review fixes for account deletion, crash reports, sessions and families

- Account deletion (Z22): the hourly purge now claims each account just
  before deleting it (`zt_claim_account_deletion`), so "Keep my account"
  can no longer race the purge. A claimed account can't be kept; a claim
  older than 30 minutes (a purge that died) is retried. Migration
  `20261123130000_core_review_fixes.sql`.
- "Keep my account" no longer says the account is kept when the purge has
  already started: it says it's too late, and the warning stays
  (`accountTooLateToKeep`).
- Meeting polls (K-5): the 30-live-poll limit is also counted when an
  expired poll is moved back into the future.
- Crash reports (Z15): `zt_crash_groups` shows the newest whole stack
  instead of merging frames across rows, and parallel reports of one bug
  merge into one row (advisory lock) instead of failing.
- `change-email` and `delete-account` answer browser preflights
  (`withSessionCors` in `_shared/cors.ts`), so web and desktop builds can
  call them.
- ZT Family uses the shared family circle rules (`ZtFamilySpace.policy`)
  like every other app, so a member can't write another member's
  `family.me/<id>/` items there.

No app changes needed. Edge functions `account-deletion`, `change-email`
and `delete-account` need a redeploy.

### Release checks follow Z21 (`zt_release_checks`)

- The shared release checks no longer expect a never-upgraded pre-core
  account to sign in with its raw password (retired in Z21; re-checked live
  on 2026-11-22: 0 such accounts, Edo's pre-core account is upgraded). They
  now check that an upgraded pre-core account signs in to every app with
  its old data key, and that a never-upgraded one is refused without the
  raw password being sent. This turns Core CI green again.

### Tablet and foldable layouts (S-11; `zero_trust_core`, `zt_sharing_ui`)

- New: `ZtWindowClass` (Material 3 size classes), `ZtLayout`
  (`readableWidth` 720, `formWidth` 560, `readablePadding`,
  `verticalHinge`), `ZtReadableListView`, and `ZtTwoPane` (list and detail
  side by side on tablets, split at the hinge on an open foldable, list
  only on phones; right-to-left aware).
- Every shared screen now stays readable on tablets and unfolded phones:
  settings, change email, recovery key, forgot and reset password, data
  protection, plans, crash reports, and the sharing pages. Phones look the
  same as before.
- Upgrade: nothing required. Apps adopt `ZtTwoPane` / `ZtReadableListView`
  for their own screens.

### sqlite3mc.wasm follows the app's sqlite3 (`tool/`)

- `tool/fetch_sqlite3mc_wasm.sh` now fetches the `sqlite3mc.wasm` of the
  `sqlite3` version in the app's `pubspec.lock` (3.9.1 or 3.9.2; 3.9.2 when
  there is no lock yet), each checked against its own pinned checksum. CI
  broke when `sqlite3` 3.9.2 came out, because the example has no committed
  lock and the script only knew 3.9.1. An unknown version still stops the
  build, with a message saying to add its checksum.

### One family space for the whole suite (S-10; `zero_trust_core`)

- The ZT Family circle (space app `family`) is now every app's family
  space: `ztFamilySpacesProvider` opens and syncs it from any app,
  `ztFamilySharedSpacesProvider` gives its `SharedSpaces`.
- `ZtFamilySpace`: item ids `<app>/<kind>/<id>` (`itemId`, `appOf`,
  `belongsTo`), one shared `policy` (ZT Family's: `family.circle` admin
  only, `family.me/` owned) and `summaryKey`. `ZtFamilySummary` (`t`, `at`,
  `due`, `done`, `list`, `kind`) is what ZT Family's hub shows.
- Suite notes: `ZtSuiteNotes` (`vault_items` app `suite`) under the new
  `VaultUnlocked.suiteKey`, the same in every app of an account and zeroed
  on lock. `ZtFamilyPrivateStore` keeps the circle's trust notes there as
  well as in the app's own store, so other apps can open a circle ZT Family
  made, including circles made before this change.
- `SpacesController` takes an optional source (the family circles).
- No database change: `vault_items` already accepts app `suite`.
- Upgrade: ZT Family needs nothing but should use `ZtFamilySpace.policy`
  as its `ztSpacePolicyProvider`. Other apps opt in by using
  `ztFamilySpacesProvider`.

### ZT Family "share my trip" links (L-1; database)

- Migration `20261123090000_family_trip_shares` (written by the Family
  thread, copy of `/mnt/project-files/sql/family-trip-shares.sql`):
  `family_trip_shares` holds only sealed text (the key is in the link
  after `#`), owner-only RLS, at most 3 running shares per account and 4
  hours each; anyone with the link reads a running share through
  `family_trip_get(id)`; ended rows are purged every 10 minutes; rows go
  with the account.
- Upgrade: nothing in Core; ZT Family uses it.

### In-app update check and Obtainium link (S-1; `zero_trust_core`)

- Direct Android builds (`ZT_CHANNEL=direct`) tell the person when a newer
  signed release is on GitHub: once on launch (at most daily, once per
  version, after the deletion-grace check) and in Settings › About, with
  "What's new" and a Download button that hands the APK to the browser and
  Android's installer. Store builds show and check nothing.
- Settings › About also gets a "Check for updates" switch (on by default)
  and "Get updates with Obtainium" (adds the app's GitHub repo to
  Obtainium). English and Hebrew.
- New: `ZtUpdates`, `ZtReleaseSource`, `ZtRelease`, `ztIsNewerVersion`,
  `ZtUpdatesTiles`, `ztCheckForUpdateAfterUnlock`, providers
  `ztUpdatesProvider`, `ztInstalledVersionProvider`,
  `ztReleaseSourceProvider`, `ztOpenExternalUrlProvider`;
  `ZtAppConfig.releaseRepo` (defaults to `EdoSag/Zero-Trust-<App>`).
- New dependencies: `url_launcher`, `package_info_plus`.
- Upgrade: build release APKs with `--dart-define=ZT_CHANNEL=direct`
  (without it the build counts as a store build and the rows stay hidden).
  Apps whose repository name doesn't follow the display name pass
  `releaseRepo`.

### Retire the raw-password sign-in fallback (Z21; database, `zero_trust_core`)

- Checked live on 2026-11-22: every pre-core account was already upgraded
  (its old key is the data key, `legacy_dek`), so `AccountService.signIn`
  no longer falls back to sending the raw password. A wrong password is
  simply "incorrect email or password".
- Migration `20261122130000_retire_legacy_sign_in`: `zt_needs_legacy_sign_in`
  always answers false, so older app versions stop sending raw passwords
  too, and it no longer reveals which emails had a pre-core account.
- Kept on purpose: upgraded accounts sign in and unlock as before, the
  vault still hands apps the legacy key (`VaultUnlocked.legacyKey`), and
  `LegacyImporter` still imports data left on a phone by a pre-core app.
- `AccountBackend.needsLegacySignIn` and `AccountService.legacyParams` stay
  for compatibility but are no longer used.
- Upgrade: nothing to do.

### Change the account's email (Z14; database, edge function, `zero_trust_core`)

- Settings › **Change email** (English and Hebrew): new address + current
  password, then the 6-digit code emailed to the new address.
- The sign-in secret depends on the email, so the server switches the
  email and the Supabase password in one admin call (edge function
  `change-email`); there is never a moment when neither address signs in.
  The encryption keys are not touched, so other devices and apps keep
  working and just sign in with the new address next time. The old address
  gets a notice.
- Migration `20261122110000_email_change`: `zt_email_changes` (hashed code,
  15 minutes, 5 tries; service role only), `zt_email_in_use`, daily purge.
- `AccountService`: `canChangeEmail`, `startEmailChange`,
  `finishEmailChange`. A password change now wraps the data key under the
  stored salt and derives the sign-in secret from the current email (they
  differ only after an email change). New errors `EmailInUse`,
  `EmailChangeCodeWrong`, `EmailChangeExpired`.
- Shared `_shared/mail.ts` (Brevo) now sends the deletion and email-change
  emails.
- Upgrade: nothing to do; the setting appears with the Supabase backend.

### Account deletion waits 7 days (Z22; database, edge functions, `zero_trust_core`)

- Migration `20261122100000_account_deletion_grace`: `zt_account_deletions`
  (the person sees only their own date), scheduling, "keep" by session or
  by the email link's token (only its SHA-256 is stored), and an hourly
  pg_cron job that asks `account-deletion` to delete accounts whose 7 days
  are over (needs pg_net and two Vault secrets, see the function's header).
- `delete-account` now schedules instead of deleting and emails the date
  (EN + HE) with a "Keep my account" link to zerotrust.bz/account/keep/.
  Asking again never postpones the date. Older apps keep working: they
  sign out after any 2xx, as before.
- New `account-deletion` function (deploy with `--no-verify-jwt`): "keep"
  from the website, and the hourly purge (storage files, then the auth
  user; shared code in `_shared/delete_user.ts`).
- `AccountLifecycleBackend` (implemented by `SupabaseAccountBackend`):
  optional, so apps' test fakes of `AccountBackend` need no change.
  `AccountService.deleteAccount` returns the deletion date (null without the
  grace period); `pendingDeletion()` and `keepAccount()` are new.
- Screens: after delete, a dialog says the date; after sign-in or unlock,
  an account set to be deleted gets "Keep my account / Delete as planned"
  (in the background, never delaying the app); settings show a row with the
  date while it is pending. English and Hebrew.
- Upgrade: nothing to do; apps get it when they move their core pin.

### Crash reports have a destination (Z15; database, edge function, `zero_trust_core`)

- Migration `20261122090000_crash_reports`: `zt_crash_reports` (one counted
  row per bug, app version, platform and day; owner only), the
  `zt_crash_groups` view, `zt_record_crash_report` (service role only, 5,000
  new rows a day at most) and a daily purge of rows older than 90 days.
- Edge function `supabase/functions/crash-report` (deploy with
  `--no-verify-jwt`): refuses anything but a scrubbed report, logs nothing.
- `ZtHttpCrashReportSink.supabase(supabaseUrl)` posts there with no key or
  token.
- Upgrade: pass `sink: ZtHttpCrashReportSink.supabase(supabaseUrl)` to the
  app's `ZtCrashReporter` (see README "Crash reports (opt-in)"). Settings
  then offer "Ask me before sending" and "Send automatically".

### ZT Time and ZT Quests in "Other Zero-Trust apps" (`zero_trust_core`)

- `ZtSuite.time` and `ZtSuite.quests` join `ZtSuite.apps`, so every app's
  settings list them under "Other Zero-Trust apps" (English and Hebrew),
  and their own sign-in, unlock and onboarding screens get their brand mark
  from the core.
- Upgrade: nothing to do. ZT Quests can drop its own `questsSuiteApp` for
  `ZtSuite.quests` once it moves its core pin.

### ZT Clock in "Other Zero-Trust apps" (`zero_trust_core`)

- `ZtSuite.clock` joins `ZtSuite.apps`, so the settings of every app list
  Zero-Trust Clock under "Other Zero-Trust apps" (English and Hebrew), and
  Clock's own sign-in, unlock and onboarding screens get its brand mark.
- Upgrade: nothing to do. An app shows the new row once it moves its core
  pin. ZT Clock can then drop its own `clockSuiteApp` for `ZtSuite.clock`.

### Companion apps and shared album files (`zero_trust_core`, database)

- `ZtAppConfig.dataAppId` (optional, defaults to `appId`): whose synced
  items, local store and attachments the app opens. ZT Gallery sets
  `appId: 'gallery', dataAppId: 'camera'` to show and add to the photos ZT
  Camera backs up, with the same keys. Shared spaces, crash reports and the
  brand still use `appId`. The release checks accept `dataAppId:` for the
  app id they run with (Gallery runs them as `camera`).
- Database `20261122120000_space_files_and_app_folders.sql`: zt-attachments
  now accepts any app folder (it accepted only notes, tasks, fitness and
  contacts, so ZT Camera's backup was refused), and files of a shared space
  under `<uploader id>/space_<space id hex>/`, readable by every member of
  that space and by nobody else. Live: run
  `sql/space-files-and-app-folders.sql` once.
- Upgrade: nothing to do. Apps that leave `dataAppId` out behave exactly as
  before.

## 0.13.0

The planning engine and the optional AI helper for ZT Calendar's Planner,
the web kit and the web deploy workflow, the Plans screen with the billing
backbone, optional "stay unlocked", settings for an app that works without
an account, ZT Family's location tables, and release checks for ZT Quests,
Family, Home, Camera and Clock. Apps move their core pin only when they
want one of these; nothing here forces an upgrade.

### Planner AI helper, off by default (database, edge function)

- Migration `20261119190000_planner_ai`: `zt_ai_config` (one row, owner
  only, `enabled` starts false) and `zt_ai_usage` (per user and month:
  requests, tokens and cost, never text).
- Edge function `supabase/functions/planner-ai`: checks the plan, the
  user's monthly limit and the project's monthly budget, forwards the
  request and records the counts. It also needs the `ANTHROPIC_API_KEY`
  secret; the steps to switch it on are in the function's README.
- Upgrade: nothing to do. The apps hide the helper while it is off.

### Plus includes the Planner and longer Family history (database)

- Migration `20261119180000_core_plus_planner_feature`: Plus gets the
  `planner` feature (the automatic Planner in ZT Calendar; "Find a time for
  a task" stays free).
- Migration `20261119100000_family_history_plus`: Plus gets the `family`
  feature. A circle's owner needs Plus to keep more than 7 days of history
  (up to 30); a circle keeps its window if the owner's Plus ends.

### Release checks know ZT Clock and ZT Camera (`zt_release_checks`)

- New suite app ids `clock` and `camera`, with vectors like the other apps.
  Nothing changes for the existing apps.

### Reusable web deploy workflow

- `.github/workflows/web-deploy.yml` (`workflow_call`): builds an app for
  the web with the web kit, self-hosted fonts and a `SHA256SUMS` of every
  file, and on a release publishes it to Cloudflare Pages. Apps add a
  ten-line workflow that calls it, plus the repository secrets
  `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
- Until an app's repository has both secrets, the publish step is skipped
  with a warning and the run stays green, so a release that only ships
  Android is not marked as failed. The site is still built and kept as an
  artifact.
- `tool/fetch_sqlite3mc_wasm.sh` stops with a clear message when the app's
  locked `sqlite3` package is not the version the wasm file was built for.
  A mismatch used to build fine and then never open the store in the
  browser.
- The web kit's content security policy allows `api.pwnedpasswords.com`,
  so the breached password check at sign-up works in a browser (only the
  first five characters of a hash are sent, as on the phone).

### ZT Family: hourly event cap holds for requests sent together (database)

- Migration `20261118130000_family_events_cap_lock`. `family_events_guard()`
  takes a lock per member and circle before counting, so two inserts sent at
  the same moment can no longer both pass the 1200 an hour cap.

### Settings for an app that works without an account (`zero_trust_core`)

- `ZtSettingsPage(accountOptional: true)`: while nobody is signed in, the
  rows that need an account are hidden (password, sign out, sync, plan,
  storage, auto-lock, biometrics, lock now, recovery key, export, delete
  account) and Appearance, the app's own rows, About and the other apps
  stay. `onSignIn` adds "Sign in or create an account" under Account.
  Crash reports need no account, so that row stays too (alone under
  Security) in apps that set up a reporter.
  Made for ZT Clock, which rings alarms without an account. New strings
  `signInOrCreateAccount` and `signInToBackUpAndSync`, English and Hebrew.
- Upgrade: nothing to do. Both are off by default, so every other app's
  settings screen is unchanged.

### The planning engine for ZT Calendar's Planner (`zt_scheduler`, new package)

- New pure Dart package `packages/zt_scheduler`: `plan()` fits tasks and
  habits into the free time around a calendar's events and returns the
  blocks to add, move and remove. No AI, no network, no storage: it runs
  on the device and the same inputs always give the same plan.
- Rules: done, locked and current blocks stay; habits go nearest their
  ideal time; tasks go most important first, then nearest due date, in
  whole blocks where they fit; a task short of time for its due date may
  use more blocks in a day and go ahead of tasks with time to spare;
  what doesn't fit is planned after the due date and reported.
- Blocks stay where they are from one plan to the next unless they must
  move, and a moved block keeps its id, so the app updates one event.
  Planning again from a plan's own blocks changes nothing.
- Tested with 74 tests: named scenarios for every rule, and randomized
  calendars checked against the rules. New CI job `zt_scheduler`.
- Upgrade: nothing to do in apps. Nothing uses the package yet; ZT
  Calendar will depend on it when the Planner screens are built. See
  `packages/zt_scheduler/README.md`.
### Web kit, platform capabilities and the web lock policy (`zero_trust_core`)

- `tool/apply_web_kit.sh` writes a web app's `index.html` (strict Content
  Security Policy, loading screen), `manifest.json`, `zt_boot.js`,
  `flutter_bootstrap.js`, `_headers` and the pinned `sqlite3mc.wasm` from
  the templates in `web-kit/`.
- Fonts: Flutter on the web fetched Noto fonts from Google Fonts for Hebrew,
  emoji and other scripts. The kit serves them from the app's own site
  (`fallback-fonts/`, filled by `tool/fetch_fallback_fonts.sh build/web`),
  so a web app calls no third party at all.
- `ZtCapabilities` / `ztCapabilitiesProvider`: what the running platform can
  do (widgets, reminders, biometrics, on-device speech and OCR, camera
  scanning, phone integration), so apps hide phone-only features on the web
  and desktop.
- Web lock policy: password on every visit by default. Settings gains, in a
  browser only, "Remember on this browser" (opt-in; the key is kept sealed
  by a non-extractable browser key, `WebSessionKeyStore`) and "Sign out and
  remove data from this browser" (`ztWipeBrowserStorage`). New strings in
  English and Hebrew. Phones and desktop apps look and behave as before.
- `accountServiceProvider` now takes its session key store from
  `ztPlatformSessionKeyStore()`.
- Upgrade: nothing for phone apps. A web app runs the two scripts above and
  gates phone-only features with `ztCapabilitiesProvider`.
### ZT Family: release checks and location tables (`zt_release_checks`, database)

- New suite app id `family` (ZT Family). Its data key, signing key and a
  synced item were made with core and checked independently with Python
  (hashlib, hmac, cryptography), like the other apps' vectors. Nothing
  changes for the existing apps.
- Migration `20261118120000_family_location_tables`. Two tables for the
  sealed location updates of a family circle (a shared space of app
  `family`): `family_latest` (one row per member device, what the map
  reads) and `family_events` (history: points, arrivals, check-ins, SOS),
  plus `family_settings` (days of history a circle keeps, 7 by default,
  1 to 30, set by an owner with `family_set_history_days`). Ciphertext
  only. Only the circle's members read them; everyone writes only as
  themselves (the server sets the sender and the time, so nothing can be
  backdated or put in someone else's name); rows must be sealed under the
  circle's current key; events can't be edited; a member's rows go when
  they leave, are removed or delete their account. `family_purge_history`
  runs hourly (pg_cron) and deletes history past the window and devices
  silent for 30 days. Both tables are in the realtime publication.
- Upgrade: nothing to do in the existing apps. Live database: paste
  `family-location-tables.sql` once (needs the shared spaces migration).

### Release checks know ZT Home (`zt_release_checks`)

- New suite app id `home` (ZT Home, the smart home app). Its data key,
  signing key and a synced item were made with core and checked
  independently with Python (cryptography: HKDF, AES-GCM, Ed25519), like the
  other apps' vectors. Nothing changes for the existing apps.

### Unlimited plan for the owner (`zero_trust_core`, database)

- Migration `20261118090000_core_unlimited_plan`. New hidden plan
  `unlimited`, ranked above Plus, never sold: the project owner gives it
  by hand with `zt_grant_plan('<user id>', 'unlimited', null, 'owner')`.
  No storage limit (every limit is 2^53 - 1) and every feature, also ones
  added later: its `features` are `*`, which `zt_has_feature()` now treats
  as "all of them". The 1 MiB cap per synced item stays, as on every plan.
- Nobody can give it to themselves: plans, subscriptions and
  `zt_grant_plan` stay closed to apps. A bought Plus on the same account
  changes nothing, because the highest-ranked plan wins.
- Dart: `ZtPlan.has()` is true for every feature on that plan
  (`ZtPlan.hasEverything`, `ZtPlan.everyFeature`). `ZtStorageUsage` gains
  `itemsUnlimited` and `attachmentsUnlimited`; the Storage row then reads
  "2.4 MB used, no limit" without a bar. `ZtPlansScreen` hides the Plus
  offer for an account on a plan other than Plus.
- Upgrade: nothing to do in apps. Gate paid features with `plan.has(...)`
  and `zt_has_feature(...)` only, never by comparing the plan id, so the
  Unlimited plan keeps including them. Live database: paste
  `core-unlimited-plan.sql` once (needs the plans migrations).

### Sign-up says when the email could not be sent (`zero_trust_core`)

- When the account server can't send a confirmation, reset or change-email
  message (its mail provider refused or failed), sign-up and Forgot password
  now show "We couldn't send the email. The problem is on our side, not
  yours. Try again later." instead of "Our server isn't responding right
  now". New string `errEmailNotSent`, English and Hebrew. No app changes
  needed.

### Billing backbone and Plans screen (`zero_trust_core`, database)

- Migration `20261117090000_core_billing_backbone`. New `zt_billing_products`
  (what each store sells, inactive until launch; Play products
  `zt_plus:monthly` and `zt_plus:yearly` are seeded switched off) and
  `zt_billing_events` (every store notification, stored once). Neither is
  writable by apps.
- `zt_apply_billing_event(...)`, callable only with the service role (store
  webhooks and verification edge functions). It is idempotent (a repeated
  event returns `duplicate`), ignores events older than what is already
  stored (`stale`), refuses to move a purchase to another account
  (`owner_mismatch`) and records the result on the event row.
- Reconcile helpers for a nightly job: `zt_billing_due_for_check`,
  `zt_billing_expire_lapsed` (manual grants are left alone) and
  `zt_billing_purge_events` (13 months). Owner views `zt_billing_summary`
  and `zt_billing_problems`.
- `zt_subscriptions` gains `product_id` and `provider_updated_at`.
- Dart: `ZtBillingStore` interface with `ztBillingStoreProvider` (null by
  default, so nothing can be bought until a store is wired in) and
  `FakeBillingStore` for tests and demos.
- `ZtPlansScreen`: current plan, Plus benefits, prices from the store,
  buy, pending and failed states, Manage subscription, Restore purchases,
  and the "renews automatically, no free trial" note. English and Hebrew.
- Upgrade: nothing to do in apps yet. Live database: paste
  `core-billing-backbone.sql` once (needs the plans migrations).

### Settings links default to zerotrust.bz (`zero_trust_core`)

- `ZtSettingsPage` now shows Help and feedback, Privacy policy and Terms
  of use whenever `onOpenUrl` is set. Without their URLs they open
  https://zerotrust.bz/support/, /privacy/ and /terms/
  (`ztSupportUrl`, `ztPrivacyPolicyUrl`, `ztTermsUrl`).
### Install channel and "Support the project" (`zero_trust_core`)

- New `ZtInstallChannel` (`direct`, `play`, `appStore`), set at build time
  with `--dart-define=ZT_CHANNEL=...` and readable as
  `ZtAppConfig.channel`. A build without the flag counts as a store build
  (`play`, or `appStore` on Apple), so nothing that store rules forbid can
  appear by accident.
- Settings → About shows **Support the project** (GitHub Sponsors) only
  in `direct` builds with `onOpenUrl` set. Google Play and the App Store
  forbid links to other ways of paying, so store builds never show it.
  Turn it off with `ZtSettingsPage(showSponsor: false)`.
- Upgrade: add `--dart-define=ZT_CHANNEL=direct` to the APK build in each
  app's release workflow (the GitHub release APK), and leave it off for the
  Play `.aab`. No other change needed.

### Release checks know ZT Quests (`zt_release_checks`)

- New suite app id `quests` (ZT Quests). Its data key, signing key and a
  synced item were made with core and checked independently with Python
  (hashlib, hmac, cryptography), like the other apps' vectors. Nothing
  changes for the existing apps.

### Optional "stay unlocked" (`zero_trust_core`)

- Settings → Auto-lock has a new last choice, **Never, even after closing
  the app**. It keeps the key in the phone's key store
  (`SecureSessionKeyStore`) so `ZtUnlockScreen` opens the vault on its own
  after the app is closed. Opt-in: the default and the existing choices
  (Immediately, 1, 5, 15 min, Never) are unchanged.
- Turning it on explains the trade-off and asks for the fingerprint or
  password. Only offered on phones with a screen lock; dropped if the
  screen lock is removed. "Lock now", sign-out, account deletion and any
  other choice remove the kept key.
- "Export my data" now asks for the fingerprint or password
  (`ztConfirmIdentity`). Changing the password, a new recovery key and
  deleting the account already asked.
- New: `SessionKeyStore`, `AccountService(sessionKeys:)`,
  `rememberSession`, `resumeSession`, `forgetSession`,
  `stayUnlockedAvailable`, `ztStayUnlockedProvider`.

**Upgrade note:** move the core pin. Apps that build `ZtUnlockScreen` and
`ZtSettingsPage` need no other change.

## 0.12.0

Release checks every app runs in CI, Google Play's location disclosure for
place reminders, more widget kit icons, and the database side of ZT
Calendar booking pages. `zero_trust_core` itself has no code change, so
apps do not need to move their core pin for this release.

### Release checks for every app (`packages/zt_release_checks`)

A new pure-Dart package that each app runs in CI with
`dart run zt_release_checks --app <id> --database`: fixed key and sync
vectors for all nine apps run inside the app's own dependencies, cross-app
and pre-core sign-in, app setup checks (no cryptography_flutter, pinned
core, encrypted SQLite, INTERNET permission, no committed secrets) and the
database rules plus every table and function the app calls, built from the
app's pinned core. No change to `zero_trust_core` or the database.

**Upgrade note:** add `zt_release_checks` as a dev dependency (any commit
from this one on) and the CI steps from the package README.

### Place reminder disclosure

- zt_places: the place-reminder permission banner now reads as Google
  Play's background location "prominent disclosure" (what the location is
  for, that it is used while the app is closed or not in use, and that it
  stays on the phone). Notes and Tasks need it before their Play review.

### Widget kit

- **Widget kit: more icons and lists** (roadmap W4, W6, W7, W9). New kit
  icons checklist, image, message, pin, dropdown and chevron start/end
  (mirrored in Hebrew), an accent ring for "today", and a README section on
  scrolling list widgets (`RemoteViewsCompat`). Resources only: apps copy
  them with `apply.sh`, no Dart change.

### Calendar booking pages (database only)

- New tables and public functions for ZT Calendar booking pages (roadmap
  K15): `supabase/migrations/20261112090000_calendar_booking_pages.sql`.
- Free slot fixes: buffers after meetings that already ended, and days when
  the clocks change (`20261112100000_booking_slots_buffer_and_dst.sql`).

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
