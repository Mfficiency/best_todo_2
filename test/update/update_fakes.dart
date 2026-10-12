/// Fakes for the updates package (`mfficiency_updates`) as BestToDo uses
/// it: GitHub's releases list through [UpdateHttp.from], an
/// in-memory APK downloader, [MemoryUpdateStore] and the plugin's
/// `mfficiency_updates` method channel answered in Dart. Nothing touches
/// the network or the disk, so it all runs inside `testWidgets`.
library;

import 'dart:async';

import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/services/pre_update_backup.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// One release of the app with [tag] as GitHub's releases list has it.
Map<String, Object?> release(String tag,
        {bool prerelease = false, bool draft = false, bool apk = true}) =>
    {
      'tag_name': tag,
      'name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'html_url': 'https://github.com/Mfficiency/best_todo_2/releases/tag/$tag',
      'body': 'notes',
      'assets': [
        if (apk)
          {
            'name': '$tag.apk',
            'url': 'https://api.github.com/repos/Mfficiency/best_todo_2/'
                'releases/assets/${tag.hashCode}',
            'browser_download_url':
                'https://github.com/Mfficiency/best_todo_2/releases/download/'
                    '$tag/$tag.apk',
          },
      ],
    };

/// The releases list; [requests] records every URL asked for.
class FakeGithub {
  List<Map<String, Object?>> releases = [];

  /// Non-null: every request fails with this HTTP status.
  int? failStatus;
  final requests = <Uri>[];

  late final UpdateHttp http = UpdateHttp.from((url, headers, cacheFor) async {
    requests.add(url);
    final status = failStatus;
    if (status != null) throw UpdateHttpException(status);
    return releases;
  });
}

/// Downloads into memory, instantly unless [hold] is set.
class FakeDownloader extends ApkDownloader {
  final files = <String>{};
  final urls = <Uri>[];
  bool fail = false;

  /// While set, a download stops at 50 % until it is completed.
  Completer<void>? hold;

  @override
  Future<String?> download(
    Uri url,
    String fileName, {
    void Function(double? fraction)? onProgress,
  }) async {
    urls.add(url);
    await Future<void>.delayed(Duration.zero);
    onProgress?.call(0.5);
    await hold?.future;
    if (fail) return null;
    files
      ..clear()
      ..add('/cache/updates/$fileName');
    onProgress?.call(1);
    return '/cache/updates/$fileName';
  }

  @override
  bool exists(String path) => files.contains(path);

  @override
  Future<String?> downloaded(String fileName) async =>
      files.contains('/cache/updates/$fileName')
          ? '/cache/updates/$fileName'
          : null;

  @override
  Future<Uri?> signedAssetUrl(Uri assetApiUrl, String token) async => null;
}

/// The plugin's channel (`mfficiency_updates`), answered in Dart.
class FakeInstaller {
  FakeInstaller() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(UpdatePlatform.channelName),
      (call) async {
        calls.add(call);
        return switch (call.method) {
          'installApk' => installOutcome,
          'canInstallApks' => true,
          'installTime' => installTime?.millisecondsSinceEpoch,
          'openUrl' => true,
          _ => null,
        };
      },
    );
  }

  final calls = <MethodCall>[];
  String installOutcome = 'ok';
  DateTime? installTime;

  /// The APK paths handed to Android's installer, in order.
  List<String> get installs => [
        for (final c in calls)
          if (c.method == 'installApk') (c.arguments as Map)['path'] as String,
      ];

  void dispose() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel(UpdatePlatform.channelName), null);
}

/// A controller for [app] the way `AppUpdates.create` builds it
/// ([AppUpdates.controllerFor]), on the fakes; also set as the running
/// app's [AppUpdates.controller]. BestToDo's pre-update backup before an
/// install is skipped (no disk) unless [backup] is set.
UpdateController fakeController({
  UpdatesApp app = UpdatesApp.todo,
  required FakeGithub github,
  required FakeDownloader downloader,
  UpdateStore? store,
  String version = '0.2.106',
  int build = 1000,
  DateTime Function()? clock,
  bool backup = false,
}) {
  if (!backup) PreUpdateBackup.skipForTest();
  final c = AppUpdates.controllerFor(
    app,
    version: version,
    build: build,
    store: store ?? MemoryUpdateStore(),
    http: github.http,
    downloader: downloader,
    platform: UpdatePlatform(supported: true),
    clock: clock,
  );
  AppUpdates.controller = c;
  return c;
}
