import 'dart:convert';
import 'dart:typed_data';

/// Optional on top of `AccountBackend`, like `AccountLifecycleBackend`: a
/// backend without it (an app's test fake) simply can't hand its session to
/// another app on the phone (S-2). The Supabase backend implements it.
abstract interface class AccountHandoffBackend {
  /// A one-time sign-in token for the signed-in account, for another app on
  /// this phone. Nothing is emailed.
  Future<String> handoffToken();

  /// Signs in with a token from [handoffToken], as a session of its own.
  Future<void> signInWithHandoffToken(String tokenHash);
}

/// What one Zero-Trust app gives another on the same phone so it opens
/// without the password (S-2): the account, its data key and, to sign in,
/// a one-time token for a session of its own. It only ever travels sealed
/// (see `ZtSignInHandoff`).
class ZtHandoffGrant {
  ZtHandoffGrant({
    required this.userId,
    required this.email,
    required this.dek,
    this.legacyDek = false,
    this.tokenHash,
    required this.expiresAt,
  });

  final String userId;
  final String email;

  /// The account's data key. Whoever holds the grant zeroes it when done
  /// ([wipe]).
  final Uint8List dek;
  final bool legacyDek;

  /// Null when the asking app is already signed in and only unlocks.
  final String? tokenHash;
  final DateTime expiresAt;

  static const int _version = 1;

  /// `version(1) | legacy(1) | dek length(1) | dek | JSON`, so the key sits
  /// in bytes that can be zeroed rather than in a string.
  Uint8List encode() {
    final rest = utf8.encode(jsonEncode({
      'user': userId,
      'email': email,
      if (tokenHash != null) 'token': tokenHash,
      'exp': expiresAt.millisecondsSinceEpoch,
    }));
    return Uint8List.fromList(
        [_version, legacyDek ? 1 : 0, dek.length, ...dek, ...rest]);
  }

  /// Throws [FormatException] on anything else.
  static ZtHandoffGrant decode(Uint8List bytes) {
    if (bytes.length < 3 || bytes[0] != _version) {
      throw const FormatException('Not a handoff grant');
    }
    final n = bytes[2];
    if (n < 16 || bytes.length < 3 + n) {
      throw const FormatException('Not a handoff grant');
    }
    final Object? json = jsonDecode(utf8.decode(bytes.sublist(3 + n)));
    if (json is! Map ||
        json['user'] is! String ||
        json['email'] is! String ||
        json['exp'] is! int ||
        (json['token'] != null && json['token'] is! String)) {
      throw const FormatException('Not a handoff grant');
    }
    return ZtHandoffGrant(
      userId: json['user'] as String,
      email: json['email'] as String,
      dek: Uint8List.fromList(bytes.sublist(3, 3 + n)),
      legacyDek: bytes[1] == 1,
      tokenHash: json['token'] as String?,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['exp'] as int),
    );
  }

  void wipe() => dek.fillRange(0, dek.length, 0);
}

/// The grant is for another account than the one this app is signed in to.
class ZtHandoffWrongAccount implements Exception {
  const ZtHandoffWrongAccount();
  @override
  String toString() => 'ZtHandoffWrongAccount';
}
