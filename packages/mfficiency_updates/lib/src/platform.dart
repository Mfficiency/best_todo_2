import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart' as os;

/// The Android side of the plugin (channel `mfficiency_updates`): installs
/// through a PackageInstaller session, the "install unknown apps" switch,
/// the install time. Off Android every call answers "not supported".
///
/// [openUrl] opens links (a release page, or the APK link off a phone);
/// the default asks the Android plugin, so on the desktop or the web pass
/// the app's own opener (e.g. url_launcher's `launchUrl`).
class UpdatePlatform {
  UpdatePlatform({
    bool? supported,
    MethodChannel? channel,
    Future<bool> Function(String url)? openUrl,
  })  : isSupported = supported ?? (!kIsWeb && os.isAndroid),
        _channel = channel ?? const MethodChannel(channelName),
        _openUrl = openUrl;

  static const channelName = 'mfficiency_updates';

  /// A phone that can download and install APKs. False in the browser and
  /// in widget tests: no automatic checks or downloads there.
  final bool isSupported;
  final MethodChannel _channel;
  final Future<bool> Function(String url)? _openUrl;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Hands the APK to a PackageInstaller session: Android shows only its
  /// "Update this app?". Returns "ok", "needs-permission" (the "install
  /// unknown apps" switch was opened instead) or "failed".
  Future<String> installApk(String path) async =>
      await _call<String>('installApk', {'path': path}) ?? 'failed';

  /// Whether the one-time "install unknown apps" switch is on for this app.
  Future<bool> canInstallApks() async =>
      await _call<bool>('canInstallApks') ?? false;

  /// Opens the "install unknown apps" switch of this app.
  Future<bool> openInstallSettings() async =>
      await _call<bool>('openInstallSettings') ?? false;

  /// When this build was installed or last updated (Android's
  /// PackageInfo.lastUpdateTime); null off Android.
  Future<DateTime?> installTime() async {
    final ms = await _call<int>('installTime');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Opens [url] in the browser (a release page without an APK, or any
  /// update off a phone): the opener passed to the constructor, else the
  /// Android plugin. False when it couldn't (or threw).
  Future<bool> openUrl(String url) async {
    final open = _openUrl;
    if (open == null) {
      return await _call<bool>('openUrl', {'url': url}) ?? false;
    }
    try {
      return await open(url);
    } on Object {
      return false;
    }
  }

  /// The applicationId (package name); null off Android.
  Future<String?> appId() => _call<String>('appId');

  /// Copies the file at [path] to the public Downloads folder as
  /// `Download/<folder>/<name>`, where it stays when the app is
  /// uninstalled, and keeps the newest [keep] of this install's files there
  /// (older ones are deleted). Returns where it went ("Download/…"), or
  /// throws [PlatformException] (`no-storage`: Android 9 or older without
  /// the storage permission).
  Future<String> saveToDownloads(
    String path, {
    required String folder,
    required String name,
    int keep = 10,
  }) async {
    final where = await _channel.invokeMethod<String>('saveToDownloads', {
      'path': path,
      'folder': folder,
      'name': name,
      'keep': keep,
    });
    if (where == null) {
      throw PlatformException(code: 'failed', message: 'nothing saved');
    }
    return where;
  }

  /// Lets the user pick a file (Android's file picker, starting in
  /// Downloads) and copies it to the app's cache: its path, or null when
  /// nothing was picked.
  Future<String?> pickFile() => _call<String>('pickFile');

  /// Closes the app and starts it again (after a restore).
  Future<void> restartApp() => _call<void>('restartApp');
}
