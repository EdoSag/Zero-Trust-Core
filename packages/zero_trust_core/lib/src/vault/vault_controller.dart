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
  const VaultUnlocked({required this.appKey});

  /// This app's data key, HKDF'd from the DEK. The DEK itself is not kept.
  final Uint8List appKey;
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
  Future<void> unlock(Uint8List dek) async {
    final appKey = await KeyHierarchy.appKey(dek, _config.appId);
    dek.fillRange(0, dek.length, 0);
    _zero();
    state = VaultUnlocked(appKey: appKey);
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
    if (s is VaultUnlocked) s.appKey.fillRange(0, s.appKey.length, 0);
  }
}

final vaultControllerProvider =
    NotifierProvider<VaultController, VaultState>(VaultController.new);
