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
```

```dart
ProviderScope(
  overrides: [ztAppConfigProvider.overrideWithValue(
    const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'))],
  child: MaterialApp(theme: ZtTheme.light(), darkTheme: ZtTheme.dark(), home: ...),
);
```

## Tests

```bash
(cd packages/zt_crypto && dart pub get && dart test)
(cd packages/zero_trust_core && flutter pub get && flutter test)
```
