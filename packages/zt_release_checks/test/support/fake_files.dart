import 'dart:io';
import 'dart:typed_data';

/// Builds a DEX file that holds nothing but the tables a scan reads: the
/// strings, and the types that point at them. [otherStrings] are strings
/// that are not class names (method names and the like), mixed in so the
/// types do not simply sit at the start of the string table.
Uint8List fakeDex(
  List<String> classNames, {
  List<String> otherStrings = const ['<init>', 'toString', 'zzz'],
}) {
  final strings = {...classNames, ...otherStrings}.toList()..sort();
  final types = [...classNames]..sort();
  const header = 0x70;
  final stringIds = header;
  final typeIds = stringIds + strings.length * 4;
  var dataAt = typeIds + types.length * 4;

  final data = BytesBuilder();
  final offsets = <int>[];
  for (final string in strings) {
    offsets.add(dataAt);
    final bytes = [string.length, ...string.codeUnits, 0];
    data.add(bytes);
    dataAt += bytes.length;
  }

  final out = ByteData(header + strings.length * 4 + types.length * 4);
  const magic = [0x64, 0x65, 0x78, 0x0A, 0x30, 0x33, 0x35, 0x00];
  for (var i = 0; i < magic.length; i++) {
    out.setUint8(i, magic[i]);
  }
  out
    ..setUint32(0x38, strings.length, Endian.little)
    ..setUint32(0x3C, stringIds, Endian.little)
    ..setUint32(0x40, types.length, Endian.little)
    ..setUint32(0x44, typeIds, Endian.little);
  for (var i = 0; i < strings.length; i++) {
    out.setUint32(stringIds + i * 4, offsets[i], Endian.little);
  }
  for (var i = 0; i < types.length; i++) {
    out.setUint32(typeIds + i * 4, strings.indexOf(types[i]), Endian.little);
  }
  return Uint8List.fromList([...out.buffer.asUint8List(), ...data.toBytes()]);
}

/// A file to put in a [fakeZip].
class FakeEntry {
  const FakeEntry(this.name, this.bytes, {this.deflate = true});
  final String name;
  final List<int> bytes;
  final bool deflate;
}

/// Builds a zip the way an APK is built: each file with its own header,
/// then the directory, then the end record with an optional [comment].
Uint8List fakeZip(List<FakeEntry> entries, {List<int> comment = const []}) {
  final out = BytesBuilder();
  final directory = BytesBuilder();
  for (final entry in entries) {
    final packed = entry.deflate
        ? ZLibEncoder(raw: true).convert(entry.bytes)
        : entry.bytes;
    final offset = out.length;
    final name = entry.name.codeUnits;
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(8, entry.deflate ? 8 : 0, Endian.little)
      ..setUint32(18, packed.length, Endian.little)
      ..setUint32(22, entry.bytes.length, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      // Four bytes of "extra" data, as real APKs carry for alignment.
      ..setUint16(28, 4, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(const [0, 0, 0, 0])
      ..add(packed);
    final central = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(10, entry.deflate ? 8 : 0, Endian.little)
      ..setUint32(20, packed.length, Endian.little)
      ..setUint32(24, entry.bytes.length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    directory
      ..add(central.buffer.asUint8List())
      ..add(name);
  }
  final directoryOffset = out.length;
  final directoryBytes = directory.toBytes();
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, directoryBytes.length, Endian.little)
    ..setUint32(16, directoryOffset, Endian.little)
    ..setUint16(20, comment.length, Endian.little);
  out
    ..add(directoryBytes)
    ..add(end.buffer.asUint8List())
    ..add(comment);
  return out.toBytes();
}

/// Writes [bytes] to a new file in [directory] and returns its path.
String writeFile(Directory directory, String name, List<int> bytes) {
  final file = File('${directory.path}/$name')..writeAsBytesSync(bytes);
  return file.path;
}
