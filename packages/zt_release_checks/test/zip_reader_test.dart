import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zt_release_checks/src/apk/zip_reader.dart';

import 'support/fake_files.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('zip_test'));
  tearDown(() => temp.deleteSync(recursive: true));

  T withZip<T>(List<int> bytes, T Function(ZipReader zip) run) {
    final file = File(writeFile(temp, 'a.zip', bytes)).openSync();
    try {
      return run(ZipReader(file));
    } finally {
      file.closeSync();
    }
  }

  final text = List<int>.generate(5000, (i) => 65 + i % 7);

  test('lists every entry with its sizes', () {
    final zip = fakeZip([
      FakeEntry('classes.dex', text),
      const FakeEntry('res/a.png', [1, 2, 3], deflate: false),
    ]);
    withZip(zip, (reader) {
      final entries = reader.entries();
      expect(entries.map((e) => e.name), ['classes.dex', 'res/a.png']);
      expect(entries[0].method, 8);
      expect(entries[0].uncompressedSize, 5000);
      expect(entries[0].compressedSize, lessThan(5000));
      expect(entries[1].method, 0);
      expect(entries[1].compressedSize, 3);
    });
  });

  test('reads packed and stored entries back as they went in', () {
    final zip = fakeZip([
      FakeEntry('classes.dex', text),
      const FakeEntry('res/a.png', [1, 2, 3], deflate: false),
    ]);
    withZip(zip, (reader) {
      final entries = reader.entries();
      expect(reader.read(entries[0]), text);
      expect(reader.read(entries[1]), [1, 2, 3]);
    });
  });

  test('finds the directory behind a comment at the end', () {
    final zip = fakeZip([
      FakeEntry('classes.dex', text),
    ], comment: List.filled(300, 0x20));
    withZip(zip, (reader) => expect(reader.entries(), hasLength(1)));
  });

  test('an empty zip has no entries', () {
    withZip(fakeZip(const []), (reader) => expect(reader.entries(), isEmpty));
  });

  test('refuses a file that is not a zip', () {
    withZip(
      List.filled(500, 7),
      (reader) => expect(reader.entries, throwsFormatException),
    );
    withZip(const [
      1,
      2,
      3,
    ], (reader) => expect(reader.entries, throwsFormatException));
  });

  test('refuses a directory that points outside the file', () {
    final zip = fakeZip([FakeEntry('classes.dex', text)]);
    // The directory's offset, in the end record: push it past the end.
    ByteData.sublistView(
      zip,
    ).setUint32(zip.length - 6, 0x00FFFFFF, Endian.little);
    withZip(zip, (reader) => expect(reader.entries, throwsFormatException));
  });

  test('refuses an entry whose own header is damaged', () {
    final zip = fakeZip([FakeEntry('classes.dex', text)]);
    withZip(zip, (reader) {
      final entry = reader.entries().single;
      expect(
        () => reader.read(
          ZipEntry(
            name: entry.name,
            method: entry.method,
            compressedSize: entry.compressedSize,
            uncompressedSize: entry.uncompressedSize,
            localHeaderOffset: 7,
          ),
        ),
        throwsFormatException,
      );
    });
  });
}
