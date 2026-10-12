import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

/// GitHub release JSON with one APK asset.
Map<String, Object?> release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'html_url': 'https://github.com/o/app/releases/tag/$tag',
      'body': 'notes',
      'assets': [
        {
          'name': 'app.apk',
          'url':
              'https://api.github.com/repos/o/app/releases/assets/${tag.hashCode}',
          'browser_download_url':
              'https://github.com/o/app/download/$tag/app.apk',
        },
      ],
    };

/// Answers every request with [status] and [body]; records the requests.
class FakeHttp extends UpdateHttp {
  FakeHttp(this.body, {this.status = 200});
  Object? body;
  int status;
  final requests = <(Uri, Map<String, String>)>[];

  @override
  Future<Object?> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? cacheFor,
  }) async {
    requests.add((url, headers));
    if (status != 200) throw UpdateHttpException(status);
    return body;
  }
}

/// Downloads into memory: a path per file name, instantly.
class FakeDownloader extends ApkDownloader {
  final files = <String>{};
  final urls = <Uri>[];
  bool fail = false;
  final signed = <(Uri, String)>[];

  @override
  Future<String?> download(
    Uri url,
    String fileName, {
    void Function(double? fraction)? onProgress,
  }) async {
    urls.add(url);
    await Future<void>.delayed(Duration.zero);
    onProgress?.call(0.5);
    if (fail) return null;
    files
      ..clear()
      ..add('/cache/$fileName');
    onProgress?.call(1);
    return '/cache/$fileName';
  }

  @override
  bool exists(String path) => files.contains(path);

  @override
  Future<String?> downloaded(String fileName) async =>
      files.contains('/cache/$fileName') ? '/cache/$fileName' : null;

  @override
  Future<Uri?> signedAssetUrl(Uri assetApiUrl, String token) async {
    signed.add((assetApiUrl, token));
    return Uri.parse('https://objects.example.com/apk?sig=1');
  }
}

/// The plugin's channel, answered in Dart: records the calls.
class FakeNative {
  FakeNative() {
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

  List<MethodCall> get installs =>
      calls.where((c) => c.method == 'installApk').toList();

  void dispose() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(UpdatePlatform.channelName),
        null,
      );
}

/// Lets the background download and the install call finish.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
