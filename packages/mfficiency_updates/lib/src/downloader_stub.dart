import 'downloader.dart';

/// Web: nothing to download or install.
class IoApkDownloader extends ApkDownloader {
  const IoApkDownloader({
    Future<String> Function()? directory,
    Duration connectionTimeout = const Duration(seconds: 15),
    Duration responseTimeout = const Duration(seconds: 30),
    Duration idleTimeout = const Duration(seconds: 60),
    String? userAgent,
  });

  @override
  Future<String?> download(
    Uri url,
    String fileName, {
    void Function(double? fraction)? onProgress,
  }) async =>
      null;

  @override
  bool exists(String path) => false;

  @override
  Future<String?> downloaded(String fileName) async => null;

  @override
  Future<Uri?> signedAssetUrl(Uri assetApiUrl, String token) async => null;
}
