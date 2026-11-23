import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zt_crypto/zt_crypto.dart';

import '../account/account_handoff.dart';
import '../config/zt_suite.dart';

/// What the asking app wants (S-2).
enum ZtHandoffMode {
  /// Not signed in yet: needs a session of its own and the key.
  signIn,

  /// Signed in to the same account, locked: needs only the key.
  unlock,
}

/// Why the other app didn't hand its account over.
enum ZtHandoffRefusal {
  /// The person said no there, or cancelled the fingerprint or password.
  declined,

  /// That app isn't signed in itself.
  signedOut,

  /// It tried and failed (offline, or the server refused).
  failed,
}

/// Another Zero-Trust app on this phone, signed with the same key.
@immutable
class ZtHandoffApp {
  const ZtHandoffApp(this.app, this.package);
  final ZtSuiteApp app;

  /// Its Android application id.
  final String package;

  /// As under the launcher icon: "ZT Notes".
  String get label => 'ZT ${app.name}';

  @override
  bool operator ==(Object other) =>
      other is ZtHandoffApp && other.package == package;

  @override
  int get hashCode => package.hashCode;
}

/// Another app asks this one for the account (S-2). Answer with
/// [ZtSignInHandoff.answer] or [ZtSignInHandoff.refuse].
class ZtHandoffRequest {
  ZtHandoffRequest._(this.from, this.mode, this._secret);
  final ZtHandoffApp from;
  final ZtHandoffMode mode;
  final Uint8List _secret;
}

/// The other app said no; [reason] says why.
class ZtHandoffRefused implements Exception {
  const ZtHandoffRefused(this.app, this.reason);
  final ZtHandoffApp app;
  final ZtHandoffRefusal reason;
  @override
  String toString() => 'ZtHandoffRefused(${app.package}, ${reason.name})';
}

/// The person stopped waiting for the other app.
class ZtHandoffCancelled implements Exception {
  const ZtHandoffCancelled();
  @override
  String toString() => 'ZtHandoffCancelled';
}

/// One message between the apps, as the platform delivers it. Only apps
/// signed with this app's key get through (checked on Android).
@immutable
class ZtHandoffMessage {
  const ZtHandoffMessage({
    required this.kind,
    required this.from,
    required this.mode,
    required this.payload,
    required this.at,
  });

  /// `request` or `answer`.
  final String kind;
  final String from;
  final String mode;
  final Uint8List payload;

  /// When it was sent.
  final DateTime at;
}

/// How messages travel between the apps. On Android, over the apps' launch
/// intents (see `ZtSignInHandoffPlugin`); elsewhere there are none.
abstract class ZtHandoffChannel {
  /// The platform's channel: Android's, or one with no apps elsewhere.
  factory ZtHandoffChannel.platform() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? MethodChannelZtHandoffChannel()
          : const _NoHandoffChannel();

  /// Those of [packages] that are installed and signed with this app's key
  /// (never this app).
  Future<List<String>> siblings(List<String> packages);

  /// Opens app [to] with a message. False when it can't be reached.
  Future<bool> send({
    required String to,
    required String kind,
    required String mode,
    required Uint8List payload,
  });

  /// Messages that came in since the last call.
  Future<List<ZtHandoffMessage>> take();

  /// Notifies when a message comes in.
  Listenable get arrivals;
}

class _NoHandoffChannel implements ZtHandoffChannel {
  const _NoHandoffChannel();
  @override
  Future<List<String>> siblings(List<String> packages) async => const [];
  @override
  Future<bool> send({
    required String to,
    required String kind,
    required String mode,
    required Uint8List payload,
  }) async =>
      false;
  @override
  Future<List<ZtHandoffMessage>> take() async => const [];
  @override
  Listenable get arrivals => const _Never();
}

class _Never implements Listenable {
  const _Never();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

/// [ZtHandoffChannel] over the core's Android plugin.
class MethodChannelZtHandoffChannel implements ZtHandoffChannel {
  MethodChannelZtHandoffChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') _arrivals.ping();
    });
  }

  static const _channel = MethodChannel('bz.zerotrust.core/sign_in_handoff');
  final _arrivals = _Pinger();

  @override
  Listenable get arrivals => _arrivals;

  @override
  Future<List<String>> siblings(List<String> packages) async {
    try {
      return (await _channel
              .invokeListMethod<String>('siblings', {'packages': packages})) ??
          const [];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Future<bool> send({
    required String to,
    required String kind,
    required String mode,
    required Uint8List payload,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('send', {
            'to': to,
            'kind': kind,
            'mode': mode,
            'payload': payload,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<ZtHandoffMessage>> take() async {
    final List<Map<Object?, Object?>>? raw;
    try {
      raw = await _channel.invokeListMethod<Map<Object?, Object?>>('take');
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
    return [
      for (final m in raw ?? const <Map<Object?, Object?>>[])
        if (m['kind'] is String &&
            m['from'] is String &&
            m['mode'] is String &&
            m['payload'] is Uint8List &&
            m['at'] is int)
          ZtHandoffMessage(
            kind: m['kind'] as String,
            from: m['from'] as String,
            mode: m['mode'] as String,
            payload: m['payload'] as Uint8List,
            at: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
          ),
    ];
  }
}

class _Pinger extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// "Sign in once per phone" (S-2): one Zero-Trust app opens with the account
/// another app on the phone is already signed in to, instead of asking for
/// the password again.
///
/// The asking app ([ask]) sends a fresh random secret to the other app,
/// which only goes to an app signed with the same key. That app asks its
/// user (fingerprint or password), then answers with a [ZtHandoffGrant]
/// sealed (AES-256-GCM) under a key derived from the secret, sent back the
/// same way. Only the app holding the secret opens it, and only within
/// [timeout] of asking.
class ZtSignInHandoff {
  ZtSignInHandoff(
    this._channel, {
    this.timeout = const Duration(minutes: 3),
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random.secure() {
    _channel.arrivals.addListener(_drain);
    _drain();
  }

  final ZtHandoffChannel _channel;

  /// How long an answer, and an unanswered request, stay good.
  final Duration timeout;
  final DateTime Function() _now;
  final Random _random;

  _Pending? _pending;
  final _queued = <ZtHandoffRequest>[];
  late final StreamController<ZtHandoffRequest> _requests =
      StreamController<ZtHandoffRequest>.broadcast(onListen: _flushQueued);
  bool _draining = false;
  bool _again = false;
  bool _disposed = false;

  void _flushQueued() {
    final queued = List.of(_queued);
    _queued.clear();
    queued.forEach(_requests.add);
  }

  /// Requests from other apps. Ones that came in before anyone listened are
  /// delivered to the first listener.
  Stream<ZtHandoffRequest> get requests => _requests.stream;

  /// The other Zero-Trust apps on this phone that could hand over their
  /// account, in the suite's order.
  Future<List<ZtHandoffApp>> givers() async {
    final found = (await _channel
            .siblings([for (final a in ZtSuite.apps) a.androidPackage]))
        .toSet();
    return [
      for (final a in ZtSuite.apps)
        if (found.contains(a.androidPackage)) ZtHandoffApp(a, a.androidPackage),
    ];
  }

  /// Asks [giver] for the account and waits for its answer. Throws
  /// [ZtHandoffRefused] when it says no, [TimeoutException] when no answer
  /// comes within [timeout], [ZtHandoffCancelled] after [cancel]. The caller
  /// owns the grant and must [ZtHandoffGrant.wipe] it.
  Future<ZtHandoffGrant> ask(ZtHandoffApp giver, ZtHandoffMode mode) async {
    cancel();
    final secret = _randomBytes(32);
    final pending = _Pending(giver, mode, secret);
    _pending = pending;
    try {
      final sent = await _channel.send(
          to: giver.package, kind: 'request', mode: mode.name, payload: secret);
      if (!sent) throw ZtHandoffRefused(giver, ZtHandoffRefusal.failed);
      return await pending.answer.future.timeout(timeout);
    } finally {
      if (identical(_pending, pending)) _pending = null;
      secret.fillRange(0, secret.length, 0);
    }
  }

  /// Stops waiting in [ask].
  void cancel() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.answer.isCompleted) {
      pending.answer.completeError(const ZtHandoffCancelled());
    }
  }

  /// Hands [grant] to the app that asked. [grant] is left untouched.
  Future<bool> answer(ZtHandoffRequest request, ZtHandoffGrant grant) async {
    final plain = grant.encode();
    try {
      return await _reply(request, Uint8List.fromList([_granted, ...plain]));
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  /// Tells the app that asked that it won't get the account, and why.
  Future<bool> refuse(ZtHandoffRequest request, ZtHandoffRefusal reason) =>
      _reply(request, Uint8List.fromList([_refused, reason.index]));

  static const _granted = 1;
  static const _refused = 2;

  Future<bool> _reply(ZtHandoffRequest request, Uint8List plain) async {
    try {
      final sealed = await SealedBox.seal(plain, await _key(request._secret),
          aad: _aad(request.mode));
      return await _channel.send(
          to: request.from.package,
          kind: 'answer',
          mode: request.mode.name,
          payload: sealed);
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  Future<void> _drain() async {
    if (_draining) {
      _again = true;
      return;
    }
    _draining = true;
    try {
      do {
        _again = false;
        for (final m in await _channel.take()) {
          if (_disposed) return;
          if (m.kind == 'request') {
            _onRequest(m);
          } else if (m.kind == 'answer') {
            await _onAnswer(m);
          }
        }
      } while (_again && !_disposed);
    } on Object {
      // A broken message is dropped; the asking app times out.
    } finally {
      _draining = false;
    }
  }

  void _onRequest(ZtHandoffMessage m) {
    final app = ZtSuite.byPackage(m.from);
    final mode = _mode(m.mode);
    final age = _now().difference(m.at);
    if (app == null ||
        mode == null ||
        m.payload.length != 32 ||
        age > timeout ||
        age < const Duration(minutes: -1)) {
      return;
    }
    final request =
        ZtHandoffRequest._(ZtHandoffApp(app, m.from), mode, m.payload);
    if (_requests.hasListener) {
      _requests.add(request);
    } else {
      _queued.add(request);
    }
  }

  Future<void> _onAnswer(ZtHandoffMessage m) async {
    final pending = _pending;
    if (pending == null ||
        m.from != pending.giver.package ||
        m.mode != pending.mode.name) {
      return;
    }
    final Uint8List plain;
    try {
      plain = await SealedBox.open(m.payload, await _key(pending.secret),
          aad: _aad(pending.mode));
    } on Object {
      return; // Not sealed with this request's secret: not our answer.
    }
    if (!identical(_pending, pending) || pending.answer.isCompleted) {
      plain.fillRange(0, plain.length, 0);
      return;
    }
    try {
      if (plain.length == 2 && plain[0] == _refused) {
        final reason = plain[1] < ZtHandoffRefusal.values.length
            ? ZtHandoffRefusal.values[plain[1]]
            : ZtHandoffRefusal.failed;
        pending.answer.completeError(ZtHandoffRefused(pending.giver, reason));
        return;
      }
      if (plain.isEmpty || plain[0] != _granted) return;
      final grant = ZtHandoffGrant.decode(Uint8List.sublistView(plain, 1));
      final now = _now();
      if (grant.expiresAt.isBefore(now) ||
          grant.expiresAt.isAfter(now.add(timeout * 2)) ||
          (pending.mode == ZtHandoffMode.signIn && grant.tokenHash == null)) {
        grant.wipe();
        pending.answer.completeError(
            ZtHandoffRefused(pending.giver, ZtHandoffRefusal.failed));
        return;
      }
      pending.answer.complete(grant);
    } on FormatException {
      pending.answer.completeError(
          ZtHandoffRefused(pending.giver, ZtHandoffRefusal.failed));
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  static ZtHandoffMode? _mode(String name) {
    for (final m in ZtHandoffMode.values) {
      if (m.name == name) return m;
    }
    return null;
  }

  static Future<Uint8List> _key(Uint8List secret) =>
      Kdf.hkdf(secret, 'zt-sign-in-handoff-v1');

  static List<int> _aad(ZtHandoffMode mode) =>
      utf8.encode('zt-sign-in-handoff|${mode.name}');

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  void dispose() {
    _disposed = true;
    cancel();
    _channel.arrivals.removeListener(_drain);
    _requests.close();
  }
}

class _Pending {
  _Pending(this.giver, this.mode, this.secret);
  final ZtHandoffApp giver;
  final ZtHandoffMode mode;
  final Uint8List secret;
  final answer = Completer<ZtHandoffGrant>();
}

/// How the handoff messages travel. Tests override it.
final ztHandoffChannelProvider =
    Provider<ZtHandoffChannel>((ref) => ZtHandoffChannel.platform());

/// "Sign in once per phone" (S-2) for this app.
final ztSignInHandoffProvider = Provider<ZtSignInHandoff>((ref) {
  final handoff = ZtSignInHandoff(ref.watch(ztHandoffChannelProvider));
  ref.onDispose(handoff.dispose);
  return handoff;
});

/// The other Zero-Trust apps on this phone that can sign this one in.
final ztHandoffGiversProvider = FutureProvider<List<ZtHandoffApp>>(
    (ref) => ref.watch(ztSignInHandoffProvider).givers());
