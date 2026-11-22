import 'dart:async';

import 'package:flutter/foundation.dart';

import 'shared_spaces.dart';
import 'space_codec.dart';

/// S-10: one family space for the whole suite.
///
/// The ZT Family circle (a shared space with app `family`) is the family
/// space of every Zero-Trust app. ZT Family creates it and manages members
/// and invites; other apps open the same circle
/// (`ztFamilySpacesProvider`) and keep their family items in it, so the
/// family's shared calendar, lists and Meds live in one place and ZT
/// Family's hub can show them together.
///
/// Rules every app follows in the circle:
/// - Item ids are `<app>/<kind>/<id>` ([itemId]); ids without a known app
///   prefix belong to ZT Family itself (`family.circle`, `family.place/…`).
/// - The item's `kind` is app-qualified (`calendar.event`).
/// - Each item carries a common summary under [summaryKey]
///   ([ZtFamilySummary]) so the hub can list it without the app's model.
/// - Every app checks the circle with the same [policy].
abstract final class ZtFamilySpace {
  /// The shared-space app of the family circle.
  static const app = 'family';

  /// What only admins, or only the member it belongs to, may write. The
  /// same in every app: a different rule in one app would make it reject
  /// items the others accept. Change it only here.
  static const policy = SpacePolicy(
    adminOnlyKinds: {'family.circle'},
    ownedPrefixes: {'family.me/'},
  );

  /// The json key of the common summary on every app's family item.
  static const summaryKey = 'zt';

  static final _appPattern = RegExp(r'^[a-z][a-z_]{0,23}$');
  static final _kindPattern = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

  /// The id of an item [app] keeps in the circle: `<app>/<kind>/<id>`.
  static String itemId(String app, String kind, String id) {
    if (!_appPattern.hasMatch(app) || app == ZtFamilySpace.app) {
      throw ArgumentError.value(app, 'app');
    }
    if (!_kindPattern.hasMatch(kind)) throw ArgumentError.value(kind, 'kind');
    final full = '$app/$kind/$id';
    if (id.isEmpty || full.length > 200) throw ArgumentError.value(id, 'id');
    return full;
  }

  /// The app an item of the circle belongs to, or null for ZT Family's own
  /// items.
  static String? appOf(String itemId) {
    final slash = itemId.indexOf('/');
    if (slash <= 0) return null;
    final app = itemId.substring(0, slash);
    if (!_appPattern.hasMatch(app) || app == ZtFamilySpace.app) return null;
    final rest = itemId.substring(slash + 1);
    final kindEnd = rest.indexOf('/');
    if (kindEnd <= 0 || kindEnd == rest.length - 1) return null;
    return _kindPattern.hasMatch(rest.substring(0, kindEnd)) ? app : null;
  }

  /// Whether [itemId] is one of [app]'s items.
  static bool belongsTo(String itemId, String app) => appOf(itemId) == app;
}

/// What ZT Family's hub shows for any app's item, read-only:
/// `{"t": title, "at": start, "due": due, "done": bool, "list": id,
/// "kind": "calendar.event"}`. Who wrote it comes from the signed item,
/// not from here.
@immutable
class ZtFamilySummary {
  const ZtFamilySummary({
    required this.title,
    required this.kind,
    this.at,
    this.due,
    this.done,
    this.list,
  });

  final String title;

  /// App-qualified, like the item's own `kind`: `tasks.item`.
  final String kind;

  /// When it happens (an event's start, a dose's time).
  final DateTime? at;

  /// When it is due (a task).
  final DateTime? due;

  /// Done or taken; null when it can't be done.
  final bool? done;

  /// The list or calendar it belongs to, by item id in the same circle.
  final String? list;

  Map<String, Object?> toJson() => {
        't': title,
        'kind': kind,
        if (at != null) 'at': at!.toUtc().toIso8601String(),
        if (due != null) 'due': due!.toUtc().toIso8601String(),
        if (done != null) 'done': done,
        if (list != null) 'list': list,
      };

  /// [json] is the item's whole json; reads its [ZtFamilySpace.summaryKey].
  /// Null when the item has no usable summary.
  static ZtFamilySummary? of(Map<String, Object?>? json) {
    final s = json?[ZtFamilySpace.summaryKey];
    if (s is! Map) return null;
    final title = s['t'];
    final kind = s['kind'];
    if (title is! String || kind is! String) return null;
    DateTime? time(Object? v) => v is String ? DateTime.tryParse(v) : null;
    final done = s['done'];
    final list = s['list'];
    return ZtFamilySummary(
      title: title,
      kind: kind,
      at: time(s['at']),
      due: time(s['due']),
      done: done is bool ? done : null,
      list: list is String ? list : null,
    );
  }

  /// [json] with this summary added, ready to save in the circle.
  Map<String, Object?> addTo(Map<String, Object?> json) =>
      {...json, ZtFamilySpace.summaryKey: toJson()};
}

/// Where an app keeps its notes about family spaces (S-10): its own synced
/// store, plus the account's suite notes, which carry them to the
/// account's other apps.
///
/// - The app's own copy is read first (works offline). An app without one
///   (it never joined the circle itself) takes ZT Family's from the suite
///   notes and keeps a copy.
/// - ZT Family ([publish]) also copies its own notes up to the suite notes,
///   so circles made before S-10 reach the other apps too.
/// - Writes go to both. The suite notes are best effort: offline, the
///   app's own copy still works and is copied up later.
class ZtFamilyPrivateStore implements SpacePrivateStore {
  ZtFamilyPrivateStore(
      {required this.own, required this.suite, this.publish = false});

  final SpacePrivateStore own;

  /// Null where the vault has no suite key (tests building it by hand).
  final SpacePrivateStore? suite;

  /// True in ZT Family: its own notes are the source the others read.
  final bool publish;

  final Set<String> _published = {};

  @override
  Future<Map<String, Object?>?> read(String id) async {
    final mine = await own.read(id);
    if (mine != null) {
      if (publish) unawaited(_publish(id, mine));
      return mine;
    }
    final suite = this.suite;
    if (suite == null) return null;
    Map<String, Object?>? shared;
    try {
      shared = await suite.read(id);
    } on Object {
      return null;
    }
    if (shared != null) {
      try {
        await own.write(id, shared);
      } on Object {
        // Read again from the suite notes next time.
      }
    }
    return shared;
  }

  Future<void> _publish(String id, Map<String, Object?> json) async {
    final suite = this.suite;
    if (suite == null || !_published.add(id)) return;
    try {
      Map<String, Object?>? there;
      try {
        there = await suite.read(id);
      } on FormatException {
        there = null; // not signed by this account: replace it
      }
      if (there == null) await suite.write(id, json);
    } on Object {
      _published.remove(id); // try again next time
    }
  }

  @override
  Future<void> write(String id, Map<String, Object?> json) async {
    await own.write(id, json);
    try {
      await suite?.write(id, json);
      _published.add(id);
    } on Object {
      // Copied up later by [read] in ZT Family.
    }
  }

  @override
  Future<void> remove(String id) async {
    await own.remove(id);
    _published.remove(id);
    try {
      await suite?.remove(id);
    } on Object {
      // Best effort.
    }
  }
}
