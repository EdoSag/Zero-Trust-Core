import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads every row the server received after [since] (all rows when null),
/// oldest first, a page at a time.
///
/// [rows] starts a new query on the table, with the columns chosen and the
/// rows narrowed to one account's app or one shared space; it is called once
/// per page. The table must have `synced_at` and `item_id` columns.
///
/// The cursor is the last row's (synced_at, item_id), so rows sharing a
/// timestamp (a backfill, one transaction) page correctly however many there
/// are. It only works going forward, and `order` sorts newest first unless
/// told otherwise: without `ascending: true` a pull of more than a page read
/// the newest page twice and never reached the older rows.
Future<List<Map<String, dynamic>>> ztPullRows(
  PostgrestFilterBuilder<PostgrestList> Function() rows, {
  DateTime? since,
  int pageSize = 500,
}) async {
  final out = <Map<String, dynamic>>[];
  String? afterAt = since?.toUtc().toIso8601String();
  String? afterId;
  while (true) {
    var query = rows();
    if (afterAt != null && afterId == null) {
      query = query.gt('synced_at', afterAt);
    } else if (afterAt != null) {
      query = query.or('synced_at.gt."$afterAt",'
          'and(synced_at.eq."$afterAt",item_id.gt."$afterId")');
    }
    final page = await query
        .order('synced_at', ascending: true)
        .order('item_id', ascending: true)
        .limit(pageSize);
    out.addAll(page);
    if (page.length < pageSize) return out;
    // Normalised to `...Z` so no `+00:00` ends up in the filter string.
    afterAt = DateTime.parse(page.last['synced_at'] as String)
        .toUtc()
        .toIso8601String();
    afterId = page.last['item_id'] as String;
  }
}
