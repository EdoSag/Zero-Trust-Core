import 'dart:typed_data';

import 'item_sync_engine.dart';

/// One item from a pre-core app version, already decrypted by the app.
class LegacyRecord {
  const LegacyRecord({required this.itemId, required this.json});

  /// Must be stable across runs and devices (the old record's own id), so a
  /// retried or repeated import updates the same item instead of copying it.
  final String itemId;
  final Map<String, Object?> json;
}

/// Remembers which imports finished on this device.
abstract interface class LegacyImportLedger {
  Future<bool> legacyImportDone(String source);
  Future<void> markLegacyImportDone(String source);
}

class LegacyImportResult {
  const LegacyImportResult({
    this.imported = 0,
    this.skipped = 0,
    this.alreadyDone = false,
  });

  /// Records saved as new items.
  final int imported;

  /// Records whose item already existed, usually because another device
  /// imported them first.
  final int skipped;
  final bool alreadyDone;
}

/// Moves data written before the core (encrypted with the account's legacy
/// key) into this app's synced items, once per device.
///
/// The app supplies [read], which decrypts its old records with the legacy
/// key; the importer does the rest:
/// 1. syncs first, so items another device already imported (and maybe
///    edited since) are known and never overwritten with older content;
/// 2. saves each record not yet present through the sync engine, sealed
///    under the app key;
/// 3. records completion, after which the legacy key isn't needed and
///    `VaultController.forgetLegacyKey` drops it.
///
/// A failure anywhere leaves the import unfinished, and the next run picks
/// it up again; stable item ids make that safe.
class LegacyImporter {
  const LegacyImporter({required this.source, required this.read});

  /// Names the old data, for example `notes-drive-v1`. A new source (a
  /// second legacy format) runs on its own.
  final String source;

  /// Reads and decrypts the old records. Receives a copy of the legacy key,
  /// zeroed when the import finishes.
  final Future<List<LegacyRecord>> Function(Uint8List legacyKey) read;

  Future<LegacyImportResult> run({
    required ItemSyncEngine engine,
    required LegacyImportLedger ledger,
    required Uint8List? legacyKey,
  }) async {
    if (await ledger.legacyImportDone(source)) {
      return const LegacyImportResult(alreadyDone: true);
    }
    if (legacyKey == null) {
      // An account created on the core: there is no old data to read.
      await ledger.markLegacyImportDone(source);
      return const LegacyImportResult();
    }

    await engine.sync();
    final key = Uint8List.fromList(legacyKey);
    final List<LegacyRecord> records;
    try {
      records = await read(key);
    } finally {
      key.fillRange(0, key.length, 0);
    }

    var imported = 0;
    var skipped = 0;
    for (final record in records) {
      if (await engine.store.get(record.itemId) != null) {
        skipped++;
        continue;
      }
      await engine.save(record.itemId, record.json);
      imported++;
    }
    await ledger.markLegacyImportDone(source);
    return LegacyImportResult(imported: imported, skipped: skipped);
  }
}
