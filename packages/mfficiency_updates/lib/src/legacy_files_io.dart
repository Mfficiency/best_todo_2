import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Deletes the old updater's APKs: [files], and `<external files>/updates`
/// on Android. Failures only cost space.
Future<void> deleteLegacyFiles(
  List<String> files, {
  required bool externalUpdatesFolder,
}) async {
  for (final path in files) {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on Object {
      // Gone already, or not ours to delete.
    }
  }
  if (!externalUpdatesFolder || !Platform.isAndroid) return;
  try {
    final base = await getExternalStorageDirectory();
    final dir = base == null ? null : Directory('${base.path}/updates');
    if (dir != null && await dir.exists()) await dir.delete(recursive: true);
  } on Object {
    // Nothing there, or not allowed.
  }
}
