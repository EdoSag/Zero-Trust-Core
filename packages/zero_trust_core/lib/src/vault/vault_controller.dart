import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_crypto/zt_crypto.dart';

import '../config/zt_app_config.dart';
import '../config/zt_preferences.dart';

sealed class VaultState {
  const VaultState();
}

class VaultLocked extends VaultState {
  const VaultLocked();
}

class VaultUnlocked extends VaultState {
  const VaultUnlocked({required this.appKey, this.legacyKey, this.identity});

  /// This app's data key, HKDF'd from the DEK. Encrypt all new data with it.
  final Uint8List appKey;

  /// Only for accounts upgraded from a pre-core app version: the key their
  /// existing local and cloud data was encrypted with. Use it to read (and
  /// re-encrypt under [appKey]) data written before the upgrade.
  final Uint8List? legacyKey;

  /// The account's sharing identity (the same in every app and on every
  /// device), for shared spaces. Null only where a test builds the state
  /// by hand.
  final ZtIdentity? identity;
}

/// Holds the unlocked key in memory, zeroes it on lock, and auto-locks
/// after the delay the user picked ([ztAutoLockProvider], defaulting to
/// [ZtAppConfig.autoLockAfter]):
/// - after that long without interaction (apps call [touch] on input);
/// - when the app comes back after being in the background that long, or
///   as soon as it leaves the screen when the delay is zero.
class VaultController extends Notifier<VaultState> {
  Timer? _timer;
  DateTime? _hiddenAt;
  int _systemUi = 0;

  /// The longest a [whileShowingSystemUi] action keeps the vault open while
  /// the app is in the background. Past this the usual auto-lock applies on
  /// return, so a file picker left open on a desk doesn't keep it unlocked.
  static const systemUiGrace = Duration(minutes: 15);

  @override
  VaultState build() {
    final lifecycle = AppLifecycleListener(onHide: _hidden, onShow: _shown);
    ref.onDispose(() {
      _timer?.cancel();
      lifecycle.dispose();
    });
    // A new choice in settings applies from now.
    ref.listen(ztAutoLockProvider, (_, __) => touch());
    return const VaultLocked();
  }

  ZtAppConfig get _config => ref.read(ztAppConfigProvider);
  Duration? get _autoLock => ref.read(ztAutoLockProvider);

  void _hidden() {
    _hiddenAt = clock.now();
    if (_autoLock == Duration.zero && _systemUi == 0) lock();
  }

  void _shown() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    var after = _autoLock;
    if (state is! VaultUnlocked || hiddenAt == null || after == null) return;
    if (_systemUi > 0 && after < systemUiGrace) after = systemUiGrace;
    // Timers don't run while the OS suspends the app, so check the clock.
    if (clock.now().difference(hiddenAt) >= after) {
      lock();
    } else {
      touch();
    }
  }

  /// Takes ownership of [dek]: derives this app's key, then zeroes [dek].
  /// With [legacyDek] (from `UnlockResult.legacyDek`) a copy is kept as
  /// [VaultUnlocked.legacyKey] so pre-upgrade data stays readable.
  Future<void> unlock(Uint8List dek, {bool legacyDek = false}) async {
    final appKey = await KeyHierarchy.appKey(dek, _config.appId);
    final identity = await ZtIdentity.fromDek(dek);
    final legacyKey = legacyDek ? Uint8List.fromList(dek) : null;
    dek.fillRange(0, dek.length, 0);
    _zero();
    state =
        VaultUnlocked(appKey: appKey, legacyKey: legacyKey, identity: identity);
    touch();
  }

  /// Zeroes and drops [VaultUnlocked.legacyKey] once the app no longer needs
  /// it (its legacy import finished), so it isn't kept in memory for the
  /// rest of the session.
  void forgetLegacyKey() {
    final s = state;
    if (s is! VaultUnlocked) return;
    final legacy = s.legacyKey;
    if (legacy == null) return;
    legacy.fillRange(0, legacy.length, 0);
    state = VaultUnlocked(appKey: s.appKey, identity: s.identity);
  }

  /// Runs [action], which shows system UI over the app (a file or photo
  /// picker, a permission prompt, the share sheet, the camera), without the
  /// vault locking because the app went to the background meanwhile. The
  /// idle timer is paused too. If the app stays in the background longer
  /// than [systemUiGrace], the vault still locks when it comes back.
  ///
  /// ```dart
  /// final file = await ref.read(vaultControllerProvider.notifier)
  ///     .whileShowingSystemUi(() => FilePicker.pickFiles());
  /// ```
  Future<R> whileShowingSystemUi<R>(Future<R> Function() action) async {
    _systemUi++;
    _timer?.cancel();
    try {
      return await action();
    } finally {
      _systemUi--;
      if (_systemUi == 0 && _hiddenAt == null) touch();
    }
  }

  /// Whether a [whileShowingSystemUi] action is running.
  bool get showingSystemUi => _systemUi > 0;

  void touch() {
    if (_systemUi > 0) return;
    _timer?.cancel();
    final after = _autoLock;
    if (state is VaultUnlocked && after != null && after > Duration.zero) {
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
      s.identity?.destroy();
    }
  }
}

final vaultControllerProvider =
    NotifierProvider<VaultController, VaultState>(VaultController.new);
