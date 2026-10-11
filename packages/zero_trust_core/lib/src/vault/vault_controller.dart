import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_crypto/zt_crypto.dart';

import '../config/zt_app_config.dart';

sealed class VaultState {
  const VaultState();
}

class VaultLocked extends VaultState {
  const VaultLocked();
}

class VaultUnlocked extends VaultState {
  const VaultUnlocked({required this.appKey, this.legacyKey});

  /// This app's data key, HKDF'd from the DEK. Encrypt all new data with it.
  final Uint8List appKey;

  /// Only for accounts upgraded from a pre-core app version: the key their
  /// existing local and cloud data was encrypted with. Use it to read (and
  /// re-encrypt under [appKey]) data written before the upgrade.
  final Uint8List? legacyKey;
}

/// Holds the unlocked key in memory, zeroes it on lock, and locks after
/// [ZtAppConfig.autoLockAfter] of inactivity. Apps call [touch] on user
/// interaction and [lock] when they go to the background.
class VaultController extends Notifier<VaultState> {
  Timer? _timer;

  @override
  VaultState build() {
    ref.onDispose(() => _timer?.cancel());
    return const VaultLocked();
  }

  ZtAppConfig get _config => ref.read(ztAppConfigProvider);

  /// Takes ownership of [dek]: derives this app's key, then zeroes [dek].
  /// With [legacyDek] (from `UnlockResult.legacyDek`) a copy is kept as
  /// [VaultUnlocked.legacyKey] so pre-upgrade data stays readable.
  Future<void> unlock(Uint8List dek, {bool legacyDek = false}) async {
    final appKey = await KeyHierarchy.appKey(dek, _config.appId);
    final legacyKey = legacyDek ? Uint8List.fromList(dek) : null;
    dek.fillRange(0, dek.length, 0);
    _zero();
    state = VaultUnlocked(appKey: appKey, legacyKey: legacyKey);
    touch();
  }

  void touch() {
    _timer?.cancel();
    final after = _config.autoLockAfter;
    if (state is VaultUnlocked && after != null) {
      _timer = Timer(after, lock);
    }
  }

  void lock() {
    _timer?.cancel();
    _zero();
    state = const VaultLocked();
  }

  void _zero() {
    final s = state;
    if (s is VaultUnlocked) {
      s.appKey.fillRange(0, s.appKey.length, 0);
      s.legacyKey?.fillRange(0, s.legacyKey!.length, 0);
    }
  }
}

final vaultControllerProvider =
    NotifierProvider<VaultController, VaultState>(VaultController.new);
