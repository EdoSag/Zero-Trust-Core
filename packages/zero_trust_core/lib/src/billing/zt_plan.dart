import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a subscription was bought (`zt_subscriptions.source`, core 0.11).
enum ZtPlanSource {
  /// Given by the project owner (beta testers, family, support).
  manual,
  googlePlay,
  appStore,
  web;

  static ZtPlanSource? parse(Object? value) => switch (value) {
        'manual' => manual,
        'google_play' => googlePlay,
        'app_store' => appStore,
        'web' => web,
        _ => null,
      };
}

/// The state of the subscription behind a paid plan.
enum ZtPlanStatus {
  active,

  /// A renewal payment failed and the store is retrying; the plan is kept.
  grace,

  /// Will not renew; the plan is kept until [ZtPlan.periodEnd].
  canceled;

  static ZtPlanStatus? parse(Object? value) => switch (value) {
        'active' => active,
        'grace' => grace,
        'canceled' => canceled,
        _ => null,
      };
}

/// The signed-in account's plan (`zt_my_plan()`, core 0.11). Every account
/// is on [freeId] until it buys or is given a paid plan.
class ZtPlan {
  const ZtPlan({
    required this.id,
    this.names = const {},
    this.features = const {},
    this.status,
    this.source,
    this.periodEnd,
  });

  static const freeId = 'free';
  static const free = ZtPlan(id: freeId);

  factory ZtPlan.fromJson(Map<String, dynamic> json) {
    final names = json['names'];
    final features = json['features'];
    final end = json['current_period_end'];
    return ZtPlan(
      id: json['plan'] as String? ?? freeId,
      names: names is Map
          ? {
              for (final e in names.entries)
                if (e.value is String) '${e.key}': e.value as String,
            }
          : const {},
      features:
          features is List ? features.whereType<String>().toSet() : const {},
      status: ZtPlanStatus.parse(json['status']),
      source: ZtPlanSource.parse(json['source']),
      periodEnd: end is String ? DateTime.tryParse(end) : null,
    );
  }

  /// `free`, `plus`, ...: stable, for code. Show [nameFor] to people.
  final String id;

  /// The plan's name by language code, from the server.
  final Map<String, String> names;

  /// Switches beyond storage, e.g. `drive`, `vpn`. Free has none.
  final Set<String> features;

  /// Null on the free plan.
  final ZtPlanStatus? status;
  final ZtPlanSource? source;

  /// When the paid period ends; null for free or a grant with no end.
  final DateTime? periodEnd;

  bool get isFree => id == freeId;

  bool has(String feature) => features.contains(feature);

  /// The name in [languageCode], else English, else the id. Null for the
  /// free plan, whose name the apps translate themselves.
  String? nameFor(String languageCode) =>
      isFree ? null : names[languageCode] ?? names['en'] ?? id;
}

/// Reads [ZtPlan]. Supabase in production; a fake in tests.
abstract interface class PlanSource {
  Future<ZtPlan?> fetch();
}

class SupabasePlanSource implements PlanSource {
  SupabasePlanSource([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Null when signed out.
  @override
  Future<ZtPlan?> fetch() async {
    final json = await _client.rpc<dynamic>('zt_my_plan');
    if (json is! Map) return null;
    return ZtPlan.fromJson(json.cast<String, dynamic>());
  }
}

final ztPlanSourceProvider =
    Provider<PlanSource>((ref) => SupabasePlanSource());

/// The account's plan, fetched each time it is first watched. Apps gate
/// paid features with `ref.watch(ztPlanProvider).value?.has('drive')`; the
/// server checks again (`zt_has_feature`), so this is only for the UI.
final ztPlanProvider = FutureProvider.autoDispose<ZtPlan?>(
    (ref) => ref.watch(ztPlanSourceProvider).fetch());
