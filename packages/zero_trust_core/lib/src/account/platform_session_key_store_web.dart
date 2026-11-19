import 'session_key_store.dart';
import 'web_session_key_store.dart';

SessionKeyStore ztPlatformSessionKeyStore() => const WebSessionKeyStore();
