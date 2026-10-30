import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where other apps' APKs download: their own folder, so the updater's
/// clean-up and theirs never delete each other's files.
Future<String> otherAppsDir() async =>
    '${(await getTemporaryDirectory()).path}/other_apps';

/// Moves a downloaded APK into `<cache>/updates/`, the only folder the
/// plugin hands to Android's installer; older `app-*` APKs there go.
Future<String?> stageApk(String path) async {
  try {
    final dir = Directory('${(await getTemporaryDirectory()).path}/updates')
      ..createSync(recursive: true);
    final name = path.split(Platform.pathSeparator).last;
    for (final f in dir.listSync().whereType<File>()) {
      final n = f.path.split(Platform.pathSeparator).last;
      if (n.startsWith('app-') && n != name) f.deleteSync();
    }
    return File(path).renameSync('${dir.path}/$name').path;
  } on Object {
    return null;
  }
}
