import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

ProviderContainer containerFor(ZtAppConfig config) => ProviderContainer(
      overrides: [ztAppConfigProvider.overrideWithValue(config)],
    );

void main() {
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
