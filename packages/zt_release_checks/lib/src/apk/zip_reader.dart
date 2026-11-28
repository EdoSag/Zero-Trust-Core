import 'dart:io';
import 'dart:typed_data';

/// One file inside a zip (an APK is a zip), as its directory describes it.
class ZipEntry {
  const ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });

  final String name;

  /// 0 = stored as is, 8 = deflate. APKs use nothing else.
  final int method;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
}

/// Reads single files out of a zip without loading the whole archive: the
/// directory at the end first, then only the entries asked for. An APK can
/// be hundreds of megabytes while the few files a scan needs are a fraction
/// of that.
///
/// Throws [FormatException] for anything that is not a plain zip.
class ZipReader {
  ZipReader(this._file) : _length = _file.lengthSync();

  final RandomAccessFile _file;
  final int _length;

  static const _endSignature = 0x06054b50;
  static const _directorySignature = 0x02014b50;
  static const _localSignature = 0x04034b50;

  /// The zip's directory: every entry, without its contents.
  List<ZipEntry> entries() {
    final end = _findEnd();
    final count = end.getUint16(10, Endian.little);
    final size = end.getUint32(12, Endian.little);
    final offset = end.getUint32(16, Endian.little);
    if (count == 0xFFFF || size == 0xFFFFFFFF || offset == 0xFFFFFFFF) {
      throw const FormatException('zip64 archives are not supported');
    }
    if (offset + size > _length) {
      throw const FormatException('zip directory is outside the file');
    }
    final bytes = _read(offset, size);
    final data = ByteData.sublistView(bytes);
    final out = <ZipEntry>[];
    var at = 0;
    for (var i = 0; i < count; i++) {
      if (at + 46 > size ||
          data.getUint32(at, Endian.little) != _directorySignature) {
        throw const FormatException('zip directory is damaged');
      }
      final nameLength = data.getUint16(at + 28, Endian.little);
      final extraLength = data.getUint16(at + 30, Endian.little);
      final commentLength = data.getUint16(at + 32, Endian.little);
      if (at + 46 + nameLength > size) {
        throw const FormatException('zip directory is damaged');
      }
      out.add(
        ZipEntry(
          // Names in an APK that matter here are plain ASCII.
          name: String.fromCharCodes(bytes, at + 46, at + 46 + nameLength),
          method: data.getUint16(at + 10, Endian.little),
          compressedSize: data.getUint32(at + 20, Endian.little),
          uncompressedSize: data.getUint32(at + 24, Endian.little),
          localHeaderOffset: data.getUint32(at + 42, Endian.little),
        ),
      );
      at += 46 + nameLength + extraLength + commentLength;
    }
    return out;
  }

  /// The contents of [entry], unpacked.
  Uint8List read(ZipEntry entry) {
    final header = ByteData.sublistView(_read(entry.localHeaderOffset, 30));
    if (header.getUint32(0, Endian.little) != _localSignature) {
      throw FormatException('zip entry ${entry.name} is damaged');
    }
    final start = entry.localHeaderOffset +
        30 +
        header.getUint16(26, Endian.little) +
        header.getUint16(28, Endian.little);
    final packed = _read(start, entry.compressedSize);
    switch (entry.method) {
      case 0:
        return packed;
      case 8:
        final unpacked = ZLibDecoder(raw: true).convert(packed);
        return unpacked is Uint8List ? unpacked : Uint8List.fromList(unpacked);
      default:
        throw FormatException(
          'zip entry ${entry.name} uses method ${entry.method}',
        );
    }
  }

  /// The "end of central directory" record. It sits at the very end, after
  /// an optional comment of up to 65535 bytes, so it is searched backwards.
  ByteData _findEnd() {
    const minimum = 22;
    if (_length < minimum) throw const FormatException('not a zip file');
    final tailLength = _length < minimum + 0xFFFF ? _length : minimum + 0xFFFF;
    final tail = _read(_length - tailLength, tailLength);
    final data = ByteData.sublistView(tail);
    for (var at = tailLength - minimum; at >= 0; at--) {
      if (data.getUint32(at, Endian.little) == _endSignature) {
        return ByteData.sublistView(tail, at, at + minimum);
      }
    }
    throw const FormatException('not a zip file');
  }

  Uint8List _read(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > _length) {
      throw const FormatException('zip points outside the file');
    }
    _file.setPositionSync(offset);
    final bytes = _file.readSync(length);
    if (bytes.length != length) {
      throw const FormatException('zip file ended early');
    }
    return bytes;
  }
}
