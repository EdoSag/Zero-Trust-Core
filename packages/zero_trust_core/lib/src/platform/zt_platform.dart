/// What differs between phone/desktop (`dart:io`, native SQLite) and the
/// browser (SQLite as WebAssembly, IndexedDB, downloads). Everything else in
/// the core is the same code on every platform.
library;

export 'zt_database.dart';
export 'zt_platform_io.dart'
    if (dart.library.js_interop) 'zt_platform_web.dart';
