import 'dart:async';

import 'background_io.dart' if (dart.library.js_interop) 'background_web.dart'
    as impl;

/// Runs [work] off the calling isolate where the platform has isolates (all
/// native platforms), so a long computation such as the password KDF doesn't
/// freeze the UI. On the web it runs inline. [work] must only capture
/// values that can be sent between isolates.
Future<T> runInBackground<T>(FutureOr<T> Function() work) =>
    impl.runInBackground(work);
