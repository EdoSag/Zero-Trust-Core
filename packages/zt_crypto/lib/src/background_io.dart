import 'dart:async';
import 'dart:isolate';

Future<T> runInBackground<T>(FutureOr<T> Function() work) => Isolate.run(work);
