import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

ProviderContainer containerFor(ZtAppConfig config, {PreferencesStore? prefs}) =>
    ProviderContainer(
      overrides: [
        ztAppConfigProvider.overrideWithValue(config),
        ztPreferencesStoreProvider
            .overrideWithValue(prefs ?? InMemoryPreferencesStore()),
      ],
    );

const _fiveMinutes = ZtAppConfig(
    appId: 'tasks',
    displayName: 'Zero-Trust Tasks',
    autoLockAfter: Duration(minutes: 5));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  void goBackground() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void comeBack() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  setUp(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  test('unlock derives the app key, zeroes the DEK, lock zeroes the key',
      () async {
    final c = containerFor(
        const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'));
    addTearDown(c.dispose);
    final dek = Uint8List.fromList(List.filled(32, 9));
    final expected =
        await KeyHierarchy.appKey(Uint8List.fromList(dek), 'notes');

    await c.read(vaultControllerProvider.notifier).unlock(dek);
    final state = c.read(vaultControllerProvider) as VaultUnlocked;
    expect(state.appKey, expected);
    expect(dek.every((b) => b == 0), isTrue);

    final heldKey = state.appKey;
    c.read(vaultControllerProvider.notifier).lock();
    expect(c.read(vaultControllerProvider), isA<VaultLocked>());
    expect(heldKey.every((b) => b == 0), isTrue);
  });

  test('forgetLegacyKey zeroes the legacy key and keeps the app key', () async {
    final c = containerFor(
        const ZtAppConfig(appId: 'notes', displayName: 'Zero-Trust Notes'));
    addTearDown(c.dispose);
    await c
        .read(vaultControllerProvider.notifier)
        .unlock(Uint8List.fromList(List.filled(32, 7)), legacyDek: true);
    final before = c.read(vaultControllerProvider) as VaultUnlocked;
    final legacy = before.legacyKey!;
    expect(legacy.every((b) => b == 7), isTrue);

    c.read(vaultControllerProvider.notifier).forgetLegacyKey();
    final after = c.read(vaultControllerProvider) as VaultUnlocked;
    expect(after.legacyKey, isNull);
    expect(identical(after.appKey, before.appKey), isTrue);
    expect(legacy.every((b) => b == 0), isTrue);
  });

  test('auto-locks after inactivity and touch() postpones it', () {
    fakeAsync((async) {
      final c = containerFor(const ZtAppConfig(
          appId: 'tasks',
          displayName: 'Zero-Trust Tasks',
          autoLockAfter: Duration(minutes: 5)));
      c.read(vaultControllerProvider.notifier).unlock(Uint8List(32));
      async.flushMicrotasks();
      expect(c.read(vaultControllerProvider), isA<VaultUnlocked>());

      async.elapse(const Duration(minutes: 4));
      c.read(vaultControllerProvider.notifier).touch();
      async.elapse(const Duration(minutes: 4));
      expect(c.read(vaultControllerProvider), isA<VaultUnlocked>());

      async.elapse(const Duration(minutes: 2));
      expect(c.read(vaultControllerProvider), isA<VaultLocked>());
      c.dispose();
    });
  });

  test('locks on return after the delay away, though no timer ran', () async {
    // A suspended app runs no timers; only the clock moves.
    var now = DateTime(2026, 10, 25, 9);
    await withClock(Clock(() => now), () async {
      final c = containerFor(_fiveMinutes);
      addTearDown(c.dispose);
      await c.read(vaultControllerProvider.notifier).unlock(Uint8List(32));

      goBackground();
      now = now.add(const Duration(minutes: 4, seconds: 59));
      comeBack();
      expect(c.read(vaultControllerProvider), isA<VaultUnlocked>());

      goBackground();
      now = now.add(const Duration(minutes: 5));
      comeBack();
      expect(c.read(vaultControllerProvider), isA<VaultLocked>());
    });
  });

  test('returning restarts the idle timer', () {
    fakeAsync((async) {
      final c = containerFor(_fiveMinutes);
      c.read(vaultControllerProvider.notifier).unlock(Uint8List(32));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 3));
      goBackground();
      async.elapse(const Duration(minutes: 1));
      comeBack();
      async.elapse(const Duration(minutes: 4));
      expect(c.read(vaultControllerProvider), isA<VaultUnlocked>());
      async.elapse(const Duration(minutes: 2));
      expect(c.read(vaultControllerProvider), isA<VaultLocked>());
      c.dispose();
    });
  });

  test('"Immediately" locks as soon as the app is hidden', () async {
    final c = containerFor(_fiveMinutes);
    addTearDown(c.dispose);
    await c.read(ztAutoLockProvider.notifier).set(Duration.zero);
    await c.read(vaultControllerProvider.notifier).unlock(Uint8List(32));
    goBackground();
    expect(c.read(vaultControllerProvider), isA<VaultLocked>());
  });

  test('"Never" turns off both idle and background locking', () {
    fakeAsync((async) {
      final c = containerFor(_fiveMinutes);
      c.read(ztAutoLockProvider.notifier).set(null);
      c.read(vaultControllerProvider.notifier).unlock(Uint8List(32));
      async.flushMicrotasks();
      goBackground();
      async.elapse(const Duration(hours: 3));
      comeBack();
      expect(c.read(vaultControllerProvider), isA<VaultUnlocked>());
      c.dispose();
    });
  });

  test('the auto-lock choice is saved and applies to the running timer', () {
    fakeAsync((async) {
      final prefs = InMemoryPreferencesStore();
      final c = containerFor(_fiveMinutes, prefs: prefs);
      c.listen(ztAutoLockProvider, (_, __) {});
      c.read(vaultControllerProvider.notifier).unlock(Uint8List(32));
      async.flushMicrotasks();
      expect(c.read(ztAutoLockProvider), const Duration(minutes: 5));

      c.read(ztAutoLockProvider.notifier).set(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(prefs.values['auto_lock'], '60');
      async.elapse(const Duration(seconds: 61));
      expect(c.read(vaultControllerProvider), isA<VaultLocked>());
      c.dispose();

      // A new launch reads it back; "Never" is stored too.
      final next = containerFor(_fiveMinutes, prefs: prefs);
      next.listen(ztAutoLockProvider, (_, __) {});
      async.flushMicrotasks();
      expect(next.read(ztAutoLockProvider), const Duration(minutes: 1));
      next.read(ztAutoLockProvider.notifier).set(null);
      async.flushMicrotasks();
      expect(prefs.values['auto_lock'], 'never');
      next.dispose();
    });
  });

  test('theme uses the shared brand seed in light and dark', () {
    final light = ZtTheme.light();
    final dark = ZtTheme.dark(accent: Colors.teal);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(light.colorScheme.primary,
        ColorScheme.fromSeed(seedColor: ZtTheme.brandSeed).primary);
    expect(dark.colorScheme.secondary, Colors.teal);
  });
}
