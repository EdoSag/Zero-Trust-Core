import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the signed-in account stores on the server and may store
/// (`zt_my_storage()`, core 0.9). Sizes are of the encrypted data.
class ZtStorageUsage {
  const ZtStorageUsage({
    required this.itemBytes,
    required this.itemCount,
    required this.attachmentBytes,
    required this.maxBlobBytes,
    required this.maxItemBytes,
    required this.maxItems,
    required this.maxAttachmentBytes,
  });

  factory ZtStorageUsage.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ZtStorageUsage(
      itemBytes: n('item_bytes'),
      itemCount: n('item_count'),
      attachmentBytes: n('attachment_bytes'),
      maxBlobBytes: n('max_blob_bytes'),
      maxItemBytes: n('max_item_bytes'),
      maxItems: n('max_items'),
      maxAttachmentBytes: n('max_attachment_bytes'),
    );
  }

  /// Synced items, across every app.
  final int itemBytes;
  final int itemCount;
  final int attachmentBytes;

  /// The largest single item the server takes.
  final int maxBlobBytes;
  final int maxItemBytes;
  final int maxItems;
  final int maxAttachmentBytes;

  /// The fuller of the two limits, 0 to 1.
  double get fraction {
    double f(int used, int max) => max <= 0 ? 0 : (used / max).clamp(0, 1);
    final items = f(itemBytes, maxItemBytes);
    final count = f(itemCount, maxItems);
    return items > count ? items : count;
  }
}

/// Reads [ZtStorageUsage]. Supabase in production; a fake in tests.
abstract interface class StorageUsageSource {
  Future<ZtStorageUsage?> fetch();
}

class SupabaseStorageUsageSource implements StorageUsageSource {
  SupabaseStorageUsageSource([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Null when signed out.
  @override
  Future<ZtStorageUsage?> fetch() async {
    final json = await _client.rpc<dynamic>('zt_my_storage');
    if (json is! Map) return null;
    return ZtStorageUsage.fromJson(json.cast<String, dynamic>());
  }
}

final ztStorageUsageSourceProvider =
    Provider<StorageUsageSource>((ref) => SupabaseStorageUsageSource());

/// The account's storage, fetched each time it is first watched.
final ztStorageUsageProvider = FutureProvider.autoDispose<ZtStorageUsage?>(
    (ref) => ref.watch(ztStorageUsageSourceProvider).fetch());

/// "2.4 MB", in decimal units like the stores and file managers use.
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['kB', 'MB', 'GB', 'TB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final text = value >= 100 || value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
