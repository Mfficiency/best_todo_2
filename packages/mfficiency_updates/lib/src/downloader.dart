import 'downloader_stub.dart' if (dart.library.io) 'downloader_io.dart' as impl;

/// Downloads update APKs into the app's cache, silently (no notification,
/// no dialog). The default writes `<name>.part`, renames it when complete
/// and continues an interrupted `.part` with an HTTP Range request.
abstract class ApkDownloader {
  const ApkDownloader();

  /// The default, on dart:io (on the web: nothing to download).
  /// [directory]: where the APKs go (default: `<cache>/updates`).
  factory ApkDownloader.io({
    Future<String> Function()? directory,
    Duration connectionTimeout,
    Duration responseTimeout,
    Duration idleTimeout,
  }) = impl.IoApkDownloader;

  /// Downloads [url] as [fileName], replacing other builds' files. Returns
  /// the complete file's path, or null on failure (a partial download stays
  /// and the next call continues it). [onProgress]: 0..1, null when the
  /// size is unknown.
  Future<String?> download(
    Uri url,
    String fileName, {
    void Function(double? fraction)? onProgress,
  });

  /// Whether a downloaded APK is still there (Android may clear the cache).
  bool exists(String path);

  /// The complete APK [fileName] from an earlier download (also from before
  /// the app was restarted), or null.
  Future<String?> downloaded(String fileName);

  /// Turns a private release asset (its API `url`) into a short-lived
  /// signed download link: GitHub answers the authenticated request with a
  /// redirect to storage that needs no login. Null on failure.
  Future<Uri?> signedAssetUrl(Uri assetApiUrl, String token);
}
