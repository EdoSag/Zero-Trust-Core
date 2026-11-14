# zt_release_checks

The release checks every Zero-Trust app runs in CI, so a broken sign-in,
upgrade or sync is caught before a release instead of on a phone. One copy
here, the same checks in every app.

Run from the app folder after `flutter pub get`:

```sh
dart run zt_release_checks --app notes              # config + Flutter checks
dart run zt_release_checks --app notes --database   # + database, needs a throwaway Postgres (PGHOST etc.)
```

## What it checks

**Inside the app** (`templates/release_checks_test.dart`, copied into the
app's `test/` folder, run with the app's own dependencies, then removed):

- Keys: the email salt, sign-in secret, key-encryption key, pre-core data
  key, keys stored by core 0.7 (password and recovery key) and this app's
  data and signing keys all match fixed vectors. A dependency or core change
  that alters any of them would lock existing users out.
- Sync: an item sealed and signed by core 0.11 still opens in this app; a
  new item round-trips and is unreadable on the server; no other app's key
  can open or forge this app's data.
- Account: an account made in any of the nine apps signs in here with the
  same key; a pre-core account (both old salt formats) signs in, keeps its
  old data key and opens again after the upgrade; a wrong password never
  reaches the server.

**App setup** (no device, no network):

- `ZtAppConfig(appId: ...)` matches `--app` and is a suite app.
- `pubspec.yaml` version looks like `1.2.3+4`.
- No `cryptography_flutter` anywhere in `pubspec.lock` (it broke sign-in
  in Fitness and Notes, 2026-11-09).
- Core packages pinned to a full commit SHA or a `vX.Y.Z` tag, and all from
  the same commit.
- The encrypted SQLite build (`hooks: user_defines: sqlite3: source:
  sqlite3mc`).
- `android.permission.INTERNET` in the main manifest (release builds lack it
  otherwise; Notes, 2026-11-09).
- No `.env`, keystore or `key.properties` committed, and no Supabase secret
  key in tracked files.

**Database** (`--database`): builds the shared schema from the app's
*pinned* core on an empty Postgres, runs core's database tests (row level
security, key guards, quotas, sharing) each on a fresh copy, then checks
every table (`.from('x')`) and function (`.rpc('x')`) the app calls itself:
it must exist, tables must have row level security, functions must be
callable by signed-in users. Tables the migrations dropped (the pre-core
data) must be read by code that treats a missing table as "nothing to
import", so old users never see an error.

## Adding it to an app

```yaml
dev_dependencies:
  zt_release_checks:
    git:
      url: https://github.com/EdoSag/Zero-Trust-Core.git
      path: packages/zt_release_checks
      ref: <same tag or commit as zero_trust_core, or newer>
```

The package does not depend on `zero_trust_core`, so it can be newer than
the app's core pin. Add `test/zt_release_checks_test.dart` to `.gitignore`.
In `.github/workflows/android-apk.yml`, give the job a Postgres service and
run the checks plus the app's own tests before the APK is built; see any
app's workflow for the exact steps.

A new app: add its id to `suiteAppIds`, and its vectors to the template,
made with core and checked independently (see the template's header).
