import 'dart:async';

Future<T> runInBackground<T>(FutureOr<T> Function() work) async => work();
