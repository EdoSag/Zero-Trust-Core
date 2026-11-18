/// The [SessionKeyStore] for the platform the app runs on: the hardware
/// key store on phones, the browser's sealed copy on the web.
library;

export 'platform_session_key_store_io.dart'
    if (dart.library.js_interop) 'platform_session_key_store_web.dart';
