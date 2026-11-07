import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Runs before every test file. The real secure storage does file I/O on
/// Windows that never completes inside `testWidgets`, and the updater reads
/// its optional token from it ([AppUpdates.readToken]); an empty in-memory
/// store keeps every test that starts the updater from hanging. A test that
/// needs a token sets its own values.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FlutterSecureStorage.setMockInitialValues({});
  await testMain();
}
