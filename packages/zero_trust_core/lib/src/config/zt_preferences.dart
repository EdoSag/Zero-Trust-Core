import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'zt_app_config.dart';

/// Small per-install settings the core keeps for every app (auto-lock).
abstract interface class PreferencesStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class InMemoryPreferencesStore implements PreferencesStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// [PreferencesStore] in the platform keychain / keystore, so a setting
/// like auto-lock can't be loosened by editing a plain file.
class SecurePreferencesStore implements PreferencesStore {
  SecurePreferencesStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: 'zt_pref_$key');

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: 'zt_pref_$key', value: value);
}

final ztPreferencesStoreProvider =
    Provider<PreferencesStore>((ref) => SecurePreferencesStore());

/// The auto-lock delay the user picked in settings, or the app's default
/// ([ZtAppConfig.autoLockAfter]) until they pick one. Null is "Never";
/// [Duration.zero] locks as soon as the app leaves the screen.
class AutoLockController extends Notifier<Duration?> {
  static const _key = 'auto_lock';

  /// What the settings picker offers.
  static const List<Duration?> choices = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    null,
  ];

  bool _chosen = false;

  @override
  Duration? build() {
    _load();
    return ref.watch(ztAppConfigProvider.select((c) => c.autoLockAfter));
  }

  Future<void> _load() async {
    final String? stored;
    try {
      stored = await ref.read(ztPreferencesStoreProvider).read(_key);
    } on Object {
      return; // Unreadable: keep the app's default.
    }
    if (stored == null || _chosen) return;
    state = stored == 'never' ? null : Duration(seconds: int.parse(stored));
  }

  Future<void> set(Duration? after) async {
    _chosen = true;
    state = after;
    await ref
        .read(ztPreferencesStoreProvider)
        .write(_key, after == null ? 'never' : '${after.inSeconds}');
  }
}

final ztAutoLockProvider =
    NotifierProvider<AutoLockController, Duration?>(AutoLockController.new);
