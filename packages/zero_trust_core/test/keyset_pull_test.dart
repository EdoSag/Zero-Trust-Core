import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zero_trust_core/src/sync/keyset_pull.dart';

/// Answers like PostgREST for the one query shape a pull makes: rows after a
/// (synced_at, item_id) cursor, in the order asked for, up to the limit.
class _Table {
  _Table(this.rows);
  final List<Map<String, Object?>> rows;
  final requests = <Uri>[];

  http.Client get client => MockClient((request) async {
        requests.add(request.url);
        final q = request.url.queryParameters;
        var out = [...rows];

        final gt = q['synced_at'];
        if (gt != null) {
          final after = DateTime.parse(gt.substring('gt.'.length));
          out = out.where((r) => _at(r).isAfter(after)).toList();
        }
        final or = q['or'];
        if (or != null) {
          final m = RegExp(r'^\(synced_at\.gt\."(.+?)",'
                  r'and\(synced_at\.eq\."(.+?)",item_id\.gt\."(.+?)"\)\)$')
              .firstMatch(or)!;
          final after = DateTime.parse(m[1]!);
          final id = m[3]!;
          out = out
              .where((r) =>
                  _at(r).isAfter(after) ||
                  (_at(r).isAtSameMomentAs(after) &&
                      (r['item_id']! as String).compareTo(id) > 0))
              .toList();
        }

        final order = q['order']!.split(',');
        expect(order.map((o) => o.split('.').first), ['synced_at', 'item_id']);
        final descending = order.first.split('.')[1] == 'desc';
        out.sort((a, b) {
          final c = _at(a).compareTo(_at(b));
          final byId =
              (a['item_id']! as String).compareTo(b['item_id']! as String);
          return descending ? -(c != 0 ? c : byId) : (c != 0 ? c : byId);
        });
        out = out.take(int.parse(q['limit']!)).toList();
        return http.Response(jsonEncode(out), 200,
            headers: {'content-type': 'application/json'}, request: request);
      });

  static DateTime _at(Map<String, Object?> row) =>
      DateTime.parse(row['synced_at']! as String);
}

void main() {
  final start = DateTime.utc(2026, 11, 23, 7);

  /// [count] rows a millisecond apart, like one import.
  List<Map<String, Object?>> imported(int count) => [
        for (var i = 0; i < count; i++)
          {
            'item_id': 'item-${i.toString().padLeft(5, '0')}',
            'synced_at': start.add(Duration(milliseconds: i)).toIso8601String(),
          },
      ];

  Future<List<Map<String, dynamic>>> pull(_Table table,
      {DateTime? since, int pageSize = 500}) {
    final client =
        PostgrestClient('http://localhost/rest/v1', httpClient: table.client);
    return ztPullRows(
      () => client.from('vault_items').select('item_id, synced_at'),
      since: since,
      pageSize: pageSize,
    );
  }

  test('a pull bigger than one page gets every row once, oldest first',
      () async {
    final table = _Table(imported(1234));
    final rows = await pull(table);
    expect(rows.map((r) => r['item_id']), table.rows.map((r) => r['item_id']));
    expect(table.requests, hasLength(3));
    for (final request in table.requests) {
      expect(request.queryParameters['order'],
          'synced_at.asc.nullslast,item_id.asc.nullslast');
    }
  });

  test('only rows after the cursor are read', () async {
    final table = _Table(imported(700));
    final rows =
        await pull(table, since: start.add(const Duration(milliseconds: 99)));
    expect(rows, hasLength(600));
    expect(rows.first['item_id'], 'item-00100');
    expect(rows.last['item_id'], 'item-00699');
  });

  test('rows sharing one timestamp page by item id', () async {
    final at = start.toIso8601String();
    final table = _Table([
      for (var i = 0; i < 25; i++)
        {'item_id': 'item-${i.toString().padLeft(5, '0')}', 'synced_at': at},
    ]);
    final rows = await pull(table, pageSize: 10);
    expect(rows.map((r) => r['item_id']).toSet(), hasLength(25));
    expect(rows, hasLength(25));
  });

  test('a full last page ends with one empty request', () async {
    final table = _Table(imported(20));
    expect(await pull(table, pageSize: 10), hasLength(20));
    expect(table.requests, hasLength(3));
  });
}
