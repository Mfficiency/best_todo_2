import 'package:package_info_plus/package_info_plus.dart';

/// Single source of truth for the running app's version. Read from the platform
/// at runtime via package_info_plus, so **no version string is ever hard-coded**
/// in the app — bumping pubspec.yaml is enough.
///
/// Usage: `await AppVersion.ensureLoaded()` early (or let a FutureBuilder await
/// it), then read [AppVersion.version] / [AppVersion.versionWithBuild].
class AppVersion {
  AppVersion._();

  static String _version = 'unknown';
  static String _build = '';
  static Future<void>? _future;

  /// e.g. `1.4.2`.
  static String get version => _version;

  /// e.g. `1.4.2+87`, falling back to just the version when no build number.
  static String get versionWithBuild =>
      _build.isEmpty ? _version : '$_version+$_build';

  /// Whether this is a debug/profile build (vs a release `--release` build).
  static const bool isDev = !bool.fromEnvironment('dart.vm.product');

  /// Loads version info once and memoizes it.
  static Future<void> ensureLoaded() => _future ??= _load();

  static Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
      _build = info.buildNumber;
    } catch (_) {
      // Platform channel absent (pure unit tests): keep the defaults.
    }
  }

  /// Lets each widget test load version info fresh in its own async zone (a
  /// future completed in a prior test's zone never fires its continuation when
  /// awaited in the next). Mirror of the host app's Config.resetVersionForTest.
  static void resetForTest() {
    _future = null;
    _version = 'unknown';
    _build = '';
  }

  /// Injects a fixed version for tests that assert on the displayed string.
  static void setForTest(String version, [String build = '']) {
    _version = version;
    _build = build;
    _future = Future<void>.value();
  }
}
