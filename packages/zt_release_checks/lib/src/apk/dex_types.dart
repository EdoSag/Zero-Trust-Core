import 'dart:typed_data';

/// The names of the classes a DEX file (an Android app's code) mentions.
///
/// Only the two tables needed for that are read: the list of types, and the
/// strings holding their names. A name looks like
/// `Lcom/example/tracker/Client;`.
///
/// The DEX format keeps both tables sorted, so "is there any class under
/// this package?" is a binary search, not a walk over tens of thousands of
/// names.
class DexTypes {
  DexTypes._(
    this._bytes,
    this._data,
    this.typeCount,
    this._typeIdsOffset,
    this._stringIdsOffset,
    this._stringCount,
  );

  /// Throws [FormatException] if [bytes] is not a DEX file.
  factory DexTypes.parse(Uint8List bytes) {
    if (bytes.length < 0x70 ||
        bytes[0] != 0x64 || // d
        bytes[1] != 0x65 || // e
        bytes[2] != 0x78 || // x
        bytes[3] != 0x0A) {
      throw const FormatException('not a DEX file');
    }
    final data = ByteData.sublistView(bytes);
    final stringCount = data.getUint32(0x38, Endian.little);
    final stringIdsOffset = data.getUint32(0x3C, Endian.little);
    final typeCount = data.getUint32(0x40, Endian.little);
    final typeIdsOffset = data.getUint32(0x44, Endian.little);
    if (stringIdsOffset + stringCount * 4 > bytes.length ||
        typeIdsOffset + typeCount * 4 > bytes.length) {
      throw const FormatException('DEX tables are outside the file');
    }
    return DexTypes._(
      bytes,
      data,
      typeCount,
      typeIdsOffset,
      stringIdsOffset,
      stringCount,
    );
  }

  final Uint8List _bytes;
  final ByteData _data;

  /// How many types (classes, mostly) the file names.
  final int typeCount;
  final int _typeIdsOffset;
  final int _stringIdsOffset;
  final int _stringCount;

  /// Where the name of type [index] starts in the file, past its length.
  int _nameStart(int index) {
    final stringIndex = _data.getUint32(
      _typeIdsOffset + index * 4,
      Endian.little,
    );
    if (stringIndex >= _stringCount) {
      throw const FormatException('DEX type points outside the strings');
    }
    var at = _data.getUint32(_stringIdsOffset + stringIndex * 4, Endian.little);
    // The name is preceded by its length as a variable-size number: skip it.
    while (true) {
      if (at >= _bytes.length) {
        throw const FormatException('DEX string is outside the file');
      }
      if (_bytes[at++] & 0x80 == 0) break;
    }
    return at;
  }

  /// The name of type [index], for example `Lcom/example/Client;`.
  String nameAt(int index) {
    final start = _nameStart(index);
    var end = start;
    while (end < _bytes.length && _bytes[end] != 0) {
      end++;
    }
    // Class names that matter here are ASCII; anything else is kept as is.
    return String.fromCharCodes(_bytes, start, end);
  }

  /// Compares the name of type [index] with [prefix]: negative when the name
  /// sorts before it, zero when the name starts with it, positive otherwise.
  int _compare(int index, Uint8List prefix) {
    var at = _nameStart(index);
    for (var i = 0; i < prefix.length; i++, at++) {
      final byte = at < _bytes.length ? _bytes[at] : 0;
      if (byte == 0) return -1; // The name ended first.
      final difference = byte - prefix[i];
      if (difference != 0) return difference;
    }
    return 0;
  }

  /// Whether any type's name starts with [prefix] (ASCII bytes such as
  /// `Lcom/example/tracker/`).
  bool hasPrefix(Uint8List prefix) {
    var low = 0;
    var high = typeCount;
    while (low < high) {
      final middle = (low + high) >> 1;
      final order = _compare(middle, prefix);
      if (order == 0) return true;
      if (order < 0) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return false;
  }

  /// Whether any type's name has [part] somewhere in it (ASCII bytes such
  /// as `/TrackerManager`). Walks every name: for the few signatures that
  /// are not the start of a package.
  bool hasPart(Uint8List part) {
    if (part.isEmpty) return true;
    for (var i = 0; i < typeCount; i++) {
      final start = _nameStart(i);
      var end = start;
      while (end < _bytes.length && _bytes[end] != 0) {
        end++;
      }
      for (var at = start; at + part.length <= end; at++) {
        var same = true;
        for (var j = 0; j < part.length; j++) {
          if (_bytes[at + j] != part[j]) {
            same = false;
            break;
          }
        }
        if (same) return true;
      }
    }
    return false;
  }

  /// The same answer as [hasPrefix], found by walking every name. Slower;
  /// kept to check the fast way against in tests and on odd files.
  bool hasPrefixSlow(Uint8List prefix) {
    for (var i = 0; i < typeCount; i++) {
      if (_compare(i, prefix) == 0) return true;
    }
    return false;
  }
}
