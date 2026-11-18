import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:zt_crypto/zt_crypto.dart';

import 'biometric_key_store.dart';
import 'session_key_store.dart';

/// [SessionKeyStore] for "Remember on this browser": the DEK is kept in the
/// browser's IndexedDB, sealed with an AES-GCM key the browser made as
/// **non-extractable**. Pages of this site can ask the browser to use that
/// key, but no script can read its bytes, so a copied IndexedDB file or a
/// dump of the page's storage does not give the DEK away.
///
/// It is weaker than the phone's hardware key store: anyone who can open
/// this browser profile, and any script that runs inside this site, can
/// ask the browser to unseal the DEK. So it is off unless the user turns it
/// on, and the default on the web stays "password on every visit".
class WebSessionKeyStore implements SessionKeyStore {
  const WebSessionKeyStore();

  static const _dbName = 'zt_session_keys';
  static const _storeName = 'keys';

  /// Browsers only expose Web Crypto on https (and localhost).
  @override
  Future<bool> isAvailable() async {
    try {
      return web.window.isSecureContext;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> save(String userId, BiometricSecret secret) async {
    final subtle = web.window.crypto.subtle;
    final key = await subtle
        .generateKey(
          _AesKeyGen(name: 'AES-GCM', length: 256),
          false, // Not extractable: usable by this site, readable by nobody.
          ['encrypt'.toJS, 'decrypt'.toJS].toJS,
        )
        .toDart as web.CryptoKey;
    final iv = Uint8List(12).toJS;
    web.window.crypto.getRandomValues(iv);
    final plain = Uint8List.fromList(utf8.encode(jsonEncode({
      'dek': ZtBase64.encode(secret.dek),
      'legacy': secret.legacyDek,
    })));
    final JSArrayBuffer sealed;
    try {
      sealed = await subtle.encrypt(_gcm(iv, userId), key, plain.toJS).toDart
          as JSArrayBuffer;
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
    await _write((store) =>
        store.put(_Record(key: key, iv: iv, data: sealed), userId.toJS));
  }

  @override
  Future<BiometricSecret?> read(String userId) async {
    try {
      final db = await _open();
      final JSAny? found;
      try {
        found = await _done(db
            .transaction(_storeName.toJS, 'readonly')
            .objectStore(_storeName)
            .get(userId.toJS));
      } finally {
        db.close();
      }
      if (found == null) return null;
      final record = found as _Record;
      final plain = (await web.window.crypto.subtle
              .decrypt(_gcm(record.iv, userId), record.key, record.data)
              .toDart as JSArrayBuffer)
          .toDart
          .asUint8List();
      try {
        final json =
            (jsonDecode(utf8.decode(plain)) as Map).cast<String, Object?>();
        return (
          dek: ZtBase64.decode(json['dek']! as String),
          legacyDek: json['legacy'] as bool? ?? false,
        );
      } finally {
        plain.fillRange(0, plain.length, 0);
      }
    } on Object {
      return null; // Unreadable or gone: the user unlocks with the password.
    }
  }

  @override
  Future<void> clear(String userId) async {
    try {
      await _write((store) => store.delete(userId.toJS));
    } on Object {
      // Already gone, or the browser has no storage (private window).
    }
  }

  /// The account id is bound in, so one account's record can't be swapped
  /// in for another's.
  static _AesGcm _gcm(JSUint8Array iv, String userId) => _AesGcm(
        name: 'AES-GCM',
        iv: iv,
        additionalData:
            Uint8List.fromList(utf8.encode('zt-session:$userId')).toJS,
      );

  static Future<web.IDBDatabase> _open() async {
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_storeName);
    }).toJS;
    return await _done(request) as web.IDBDatabase;
  }

  static Future<void> _write(
      web.IDBRequest Function(web.IDBObjectStore store) op) async {
    final db = await _open();
    try {
      final tx = db.transaction(_storeName.toJS, 'readwrite');
      final committed = Completer<void>();
      tx.oncomplete = ((web.Event _) => committed.complete()).toJS;
      void failed(web.Event _) {
        if (!committed.isCompleted) {
          committed.completeError(StateError('Browser storage refused'));
        }
      }

      tx.onerror = failed.toJS;
      tx.onabort = failed.toJS;
      op(tx.objectStore(_storeName));
      await committed.future;
    } finally {
      db.close();
    }
  }

  static Future<JSAny?> _done(web.IDBRequest request) {
    final result = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => result.complete(request.result)).toJS;
    request.onerror = ((web.Event _) =>
        result.completeError(StateError('Browser storage refused'))).toJS;
    return result.future;
  }
}

extension type _Record._(JSObject _) implements JSObject {
  external factory _Record({
    web.CryptoKey key,
    JSUint8Array iv,
    JSArrayBuffer data,
  });

  external web.CryptoKey get key;
  external JSUint8Array get iv;
  external JSArrayBuffer get data;
}

extension type _AesKeyGen._(JSObject _) implements JSObject {
  external factory _AesKeyGen({String name, int length});
}

extension type _AesGcm._(JSObject _) implements JSObject {
  external factory _AesGcm({
    String name,
    JSUint8Array iv,
    JSUint8Array additionalData,
  });
}
