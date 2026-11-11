import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'place.dart';

enum ZtPlaceTrigger {
  arrive,
  leave;

  static ZtPlaceTrigger parse(Object? value) =>
      value == 'leave' ? ZtPlaceTrigger.leave : ZtPlaceTrigger.arrive;
}

/// One "remind me when I arrive at / leave [place]" for the OS to watch.
@immutable
class ZtPlaceReminder {
  const ZtPlaceReminder({
    required this.id,
    required this.place,
    required this.trigger,
    required this.title,
    this.body = '',
    this.payload = '',
  });

  /// Stable per reminder. A reminder fires once; to have it again, give the
  /// new one a new id (for example the item id plus when it was set).
  final String id;
  final ZtPlace place;
  final ZtPlaceTrigger trigger;

  /// Shown in the notification. This, [body] and the place are the only
  /// things the OS keeps (outside the vault), so keep them minimal.
  final String title;
  final String body;

  /// Handed back to the app on a tap or "Done" (for example the item id).
  final String payload;

  Map<String, Object?> toChannel() => {
        'id': id,
        'latitude': place.latitude,
        'longitude': place.longitude,
        'radius': place.radiusMeters,
        'trigger': trigger.name,
        'title': title,
        'body': body,
        'payload': payload,
      };

  @override
  bool operator ==(Object other) =>
      other is ZtPlaceReminder &&
      other.id == id &&
      other.place == place &&
      other.trigger == trigger &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, place, trigger, title, body, payload);
}

/// How each app's place notifications look.
@immutable
class ZtPlaceNotificationStyle {
  const ZtPlaceNotificationStyle({
    required this.channelId,
    required this.channelName,
    this.channelDescription = '',
    this.smallIcon,
    this.doneLabel,
    this.publicTitle,
  });

  final String channelId;
  final String channelName;
  final String channelDescription;

  /// A drawable (or mipmap) resource name in the app, e.g. 'ic_stat_notes'.
  /// The app icon when null or missing.
  final String? smallIcon;

  /// Adds a "Done" button; its taps arrive as [ZtPlaceEventType.done].
  final String? doneLabel;

  /// What the lock screen shows instead of the title ("Place reminder").
  final String? publicTitle;

  Map<String, Object?> toChannel() => {
        'channelId': channelId,
        'channelName': channelName,
        'channelDescription': channelDescription,
        'smallIcon': smallIcon ?? '',
        'doneLabel': doneLabel ?? '',
        'publicTitle': publicTitle ?? '',
      };
}

@immutable
class ZtPlacePermissions {
  const ZtPlacePermissions({
    this.precise = false,
    this.approximate = false,
    this.background = false,
    this.notifications = false,
    this.locationOn = false,
  });

  static const ZtPlacePermissions none = ZtPlacePermissions();
  static const ZtPlacePermissions all = ZtPlacePermissions(
      precise: true,
      approximate: true,
      background: true,
      notifications: true,
      locationOn: true);

  /// "Precise location" allowed (needed to watch places).
  final bool precise;
  final bool approximate;

  /// "Allow all the time": needed for reminders while the app is closed.
  final bool background;
  final bool notifications;

  /// The phone's location setting is on.
  final bool locationOn;

  /// Everything a place reminder needs to fire with the app closed.
  bool get ready => precise && background && notifications && locationOn;

  static ZtPlacePermissions fromChannel(Object? m) {
    if (m is! Map) return none;
    return ZtPlacePermissions(
      precise: m['fine'] == true,
      approximate: m['coarse'] == true,
      background: m['background'] == true,
      notifications: m['notifications'] == true,
      locationOn: m['locationOn'] == true,
    );
  }
}

enum ZtPlaceEventType {
  /// The reminder was shown.
  fired,

  /// The notification's "Done" button.
  done,

  /// The notification was tapped (the app was opened from it).
  tap,
}

@immutable
class ZtPlaceEvent {
  const ZtPlaceEvent(this.type, this.reminderId, this.payload);
  final ZtPlaceEventType type;
  final String reminderId;
  final String payload;

  static ZtPlaceEvent? fromChannel(Object? m, [ZtPlaceEventType? type]) {
    if (m is! Map) return null;
    final t = type ??
        ZtPlaceEventType.values.where((v) => v.name == m['type']).firstOrNull;
    final id = m['id'];
    if (t == null || id is! String) return null;
    final payload = m['payload'];
    return ZtPlaceEvent(t, id, payload is String ? payload : '');
  }

  @override
  bool operator ==(Object other) =>
      other is ZtPlaceEvent &&
      other.type == type &&
      other.reminderId == reminderId &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(type, reminderId, payload);

  @override
  String toString() => 'ZtPlaceEvent($type, $reminderId, $payload)';
}

/// Hands place reminders to the phone. Apps keep their reminders (and saved
/// places) in their own encrypted store and call [sync] with the full list
/// whenever it changes; this keeps the OS's list exactly that.
abstract interface class ZtPlaceReminders {
  /// Whether this platform can watch places (Android only for now).
  bool get supported;

  /// Makes the watched reminders exactly [reminders]. Ones that already
  /// fired stay fired. Returns how many are being watched.
  Future<int> sync(List<ZtPlaceReminder> reminders,
      {required ZtPlaceNotificationStyle style});

  /// Forgets every reminder (sign-out).
  Future<void> clear();

  Future<ZtPlacePermissions> permissions();

  /// Asks for precise location ("While using the app").
  Future<ZtPlacePermissions> requestLocation();

  /// Asks for "Allow all the time". On Android 11+ the phone opens its
  /// settings page for it.
  Future<ZtPlacePermissions> requestBackground();

  Future<ZtPlacePermissions> requestNotifications();

  /// The app's page in the phone's settings.
  Future<void> openSettings();

  /// Where the phone is now, from the phone's own location providers. Null
  /// when location is off, not allowed, or nothing came in time.
  Future<ZtLatLng?> currentLocation(
      {Duration timeout = const Duration(seconds: 20)});

  /// Fired, done and tap events, including ones that happened while the
  /// app was closed (collected on [collect]).
  Stream<ZtPlaceEvent> get events;

  /// Emits events the OS queued while the app wasn't running, and the tap
  /// that launched the app. Call after unlock and on resume.
  Future<void> collect();
}

/// The Android implementation.
class ZtPlaceRemindersAndroid implements ZtPlaceReminders {
  ZtPlaceRemindersAndroid() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'event':
          // Every event is queued natively (so none is lost while no app
          // code listens); this is a nudge to collect the queue now.
          await _takeQueued();
        case 'tap':
          final e =
              ZtPlaceEvent.fromChannel(call.arguments, ZtPlaceEventType.tap);
          if (e != null) _emit(e);
      }
      return null;
    });
  }

  static const _channel = MethodChannel('dev.sagron.zt_places');
  late final _events = StreamController<ZtPlaceEvent>.broadcast(
    onListen: _flushHeld,
  );

  /// Events taken from the native queue while nothing listened (before
  /// unlock, say). A broadcast stream would drop them, so they wait here
  /// for the first listener.
  final _held = <ZtPlaceEvent>[];

  void _emit(ZtPlaceEvent e) {
    if (_events.hasListener) {
      _events.add(e);
    } else {
      _held.add(e);
    }
  }

  void _flushHeld() {
    if (_held.isEmpty) return;
    final held = [..._held];
    _held.clear();
    // After the listener is attached, so it receives them.
    scheduleMicrotask(() => held.forEach(_emit));
  }

  @override
  bool get supported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<int> sync(List<ZtPlaceReminder> reminders,
      {required ZtPlaceNotificationStyle style}) async {
    if (!supported) return 0;
    final n = await _channel.invokeMethod<int>('sync', {
      'reminders': [for (final r in reminders) r.toChannel()],
      'config': style.toChannel(),
    });
    return n ?? 0;
  }

  @override
  Future<void> clear() async {
    if (supported) await _channel.invokeMethod<void>('clear');
  }

  Future<ZtPlacePermissions> _perm(String method) async {
    if (!supported) return ZtPlacePermissions.none;
    return ZtPlacePermissions.fromChannel(
        await _channel.invokeMethod<Object?>(method));
  }

  @override
  Future<ZtPlacePermissions> permissions() => _perm('permissions');

  @override
  Future<ZtPlacePermissions> requestLocation() => _perm('requestLocation');

  @override
  Future<ZtPlacePermissions> requestBackground() => _perm('requestBackground');

  @override
  Future<ZtPlacePermissions> requestNotifications() =>
      _perm('requestNotifications');

  @override
  Future<void> openSettings() async {
    if (supported) await _channel.invokeMethod<void>('openSettings');
  }

  @override
  Future<ZtLatLng?> currentLocation(
      {Duration timeout = const Duration(seconds: 20)}) async {
    if (!supported) return null;
    final m = await _channel.invokeMethod<Object?>(
        'currentLocation', {'timeoutMs': timeout.inMilliseconds});
    if (m is! Map) return null;
    final lat = m['latitude'];
    final lng = m['longitude'];
    if (lat is! num || lng is! num) return null;
    return ZtLatLng(lat.toDouble(), lng.toDouble());
  }

  @override
  Stream<ZtPlaceEvent> get events => _events.stream;

  Future<void> _takeQueued() async {
    final queued = await _channel.invokeMethod<List<Object?>>('takeEvents');
    for (final m in queued ?? const []) {
      final e = ZtPlaceEvent.fromChannel(m);
      if (e != null) _emit(e);
    }
  }

  @override
  Future<void> collect() async {
    if (!supported) return;
    await _takeQueued();
    final tap = await _channel.invokeMethod<Object?>('takeLaunchTap');
    final e = ZtPlaceEvent.fromChannel(tap, ZtPlaceEventType.tap);
    if (e != null) _emit(e);
  }
}

/// For tests and platforms without place reminders.
class ZtPlaceRemindersFake implements ZtPlaceReminders {
  ZtPlaceRemindersFake({
    this.supported = true,
    this.granted = ZtPlacePermissions.all,
    this.location,
  });

  @override
  final bool supported;
  ZtPlacePermissions granted;
  ZtLatLng? location;
  List<ZtPlaceReminder> watched = const [];
  ZtPlaceNotificationStyle? style;
  final Set<String> fired = {};
  final List<String> calls = [];
  final _events = StreamController<ZtPlaceEvent>.broadcast();

  @override
  Future<int> sync(List<ZtPlaceReminder> reminders,
      {required ZtPlaceNotificationStyle style}) async {
    this.style = style;
    final ids = {for (final r in reminders) r.id};
    fired.retainAll(ids);
    watched = [
      for (final r in reminders)
        if (!fired.contains(r.id)) r
    ];
    return watched.length;
  }

  /// Pretends the phone crossed into (or out of) a watched place.
  void fire(String id) {
    final r = watched.firstWhere((r) => r.id == id);
    fired.add(id);
    watched = [...watched]..remove(r);
    _events.add(ZtPlaceEvent(ZtPlaceEventType.fired, id, r.payload));
  }

  void emit(ZtPlaceEvent e) => _events.add(e);

  @override
  Future<void> clear() async {
    watched = const [];
    fired.clear();
  }

  @override
  Future<ZtPlacePermissions> permissions() async => granted;

  @override
  Future<ZtPlacePermissions> requestLocation() async {
    calls.add('requestLocation');
    return granted;
  }

  @override
  Future<ZtPlacePermissions> requestBackground() async {
    calls.add('requestBackground');
    return granted;
  }

  @override
  Future<ZtPlacePermissions> requestNotifications() async {
    calls.add('requestNotifications');
    return granted;
  }

  @override
  Future<void> openSettings() async => calls.add('openSettings');

  @override
  Future<ZtLatLng?> currentLocation(
          {Duration timeout = const Duration(seconds: 20)}) async =>
      location;

  @override
  Stream<ZtPlaceEvent> get events => _events.stream;

  @override
  Future<void> collect() async {}
}
