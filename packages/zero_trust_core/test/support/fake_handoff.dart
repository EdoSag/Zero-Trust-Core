import 'package:flutter/foundation.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// A phone with apps on it, for "sign in once per phone" (S-2): what the
/// Android plugin does, in memory. Apps signed with the same key reach each
/// other; others neither see nor reach them.
class FakePhone {
  /// Package -> signing key.
  final Map<String, String> installed = {};
  final Map<String, FakeHandoffChannel> _channels = {};

  /// Everything sent, for checking what travelled in the clear.
  final List<ZtHandoffMessage> sent = [];

  FakeHandoffChannel install(String package, {String signature = 'edo'}) {
    installed[package] = signature;
    return _channels[package] = FakeHandoffChannel._(this, package);
  }

  bool _siblings(String a, String b) =>
      a != b && installed[a] != null && installed[a] == installed[b];

  /// What another app could do: open [to] with any message, claiming to
  /// be [from].
  void deliver(String to, ZtHandoffMessage message) =>
      _channels[to]?._receive(message);
}

class FakeHandoffChannel implements ZtHandoffChannel {
  FakeHandoffChannel._(this.phone, this.package);
  final FakePhone phone;
  final String package;
  final _inbox = <ZtHandoffMessage>[];
  final _arrivals = _Ping();

  @override
  Listenable get arrivals => _arrivals;

  void _receive(ZtHandoffMessage m) {
    // As the plugin does: only from a sibling.
    if (!phone._siblings(package, m.from)) return;
    _inbox.add(m);
    _arrivals.ping();
  }

  @override
  Future<List<String>> siblings(List<String> packages) async => [
        for (final p in packages)
          if (phone._siblings(package, p)) p
      ];

  @override
  Future<bool> send({
    required String to,
    required String kind,
    required String mode,
    required Uint8List payload,
  }) async {
    if (!phone._siblings(package, to)) return false;
    final m = ZtHandoffMessage(
        kind: kind,
        from: package,
        mode: mode,
        payload: Uint8List.fromList(payload),
        at: DateTime.now());
    phone.sent.add(m);
    // The other app opens a moment later.
    Future<void>.delayed(Duration.zero, () => phone.deliver(to, m));
    return true;
  }

  @override
  Future<List<ZtHandoffMessage>> take() async {
    final out = List.of(_inbox);
    _inbox.clear();
    return out;
  }
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}
