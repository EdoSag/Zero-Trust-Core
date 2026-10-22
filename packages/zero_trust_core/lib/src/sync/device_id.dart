import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zt_crypto/zt_crypto.dart';

/// Where this install keeps its device id.
abstract interface class DeviceIdStore {
  Future<String?> read();
  Future<void> write(String id);
}

class InMemoryDeviceIdStore implements DeviceIdStore {
  String? id;

  @override
  Future<String?> read() async => id;

  @override
  Future<void> write(String id) async => this.id = id;
}

/// [DeviceIdStore] in the platform keychain / keystore. Shared by every
/// account on the install: the id names the device, not the user.
class SecureDeviceIdStore implements DeviceIdStore {
  SecureDeviceIdStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'zt_device_id';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String id) => _storage.write(key: _key, value: id);
}

/// This install's id, created on first use: a random UUID (v4). Sync uses it
/// to break ties between edits made at the same instant.
Future<String> loadOrCreateDeviceId(DeviceIdStore store) async {
  final existing = await store.read();
  if (existing != null && existing.isNotEmpty) return existing;
  final b = Kdf.randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  final id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  await store.write(id);
  return id;
}
