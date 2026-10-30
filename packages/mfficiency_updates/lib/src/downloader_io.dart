import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'downloader.dart';

/// [ApkDownloader] on dart:io's HttpClient, into `<cache>/updates/`.
///
/// The APK is written as `<name>.part` and renamed when complete, so a file
/// under its name is always whole ([downloaded]). An interrupted `.part`
/// stays and the next download of the same file continues it with a Range
/// request (`If-Range` with the ETag or Last-Modified seen first, so a
/// replaced file starts over instead of being glued to the old one).
class IoApkDownloader extends ApkDownloader {
  IoApkDownloader({
    Future<String> Function()? directory,
    this.connectionTimeout = const Duration(seconds: 15),
    this.responseTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 60),
    this.userAgent,
  }) : _directory = directory;

  /// Sent as `User-Agent` (null: dart:io's own).
  final String? userAgent;

  HttpClient _client() {
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    if (userAgent case final ua?) client.userAgent = ua;
    return client;
  }

  final Future<String> Function()? _directory;
  final Duration connectionTimeout;
  final Duration responseTimeout;
  final Duration idleTimeout;

  Future<Directory> _dir() async {
    final custom = _directory;
    return Directory(
      custom != null
          ? await custom()
          : '${(await getTemporaryDirectory()).path}/updates',
    );
  }

  @override
  Future<String?> download(
    Uri url,
    String fileName, {
    void Function(double? fraction)? onProgress,
  }) async {
    final client = _client();
    try {
      final dir = await _dir();
      dir.createSync(recursive: true);
      final part = File('${dir.path}/$fileName.part');
      final meta = File('${dir.path}/$fileName.part.meta');
      // Only this file's partial download stays; other builds' go. By name:
      // listSync's paths use the platform separator ("\\" on Windows).
      final keep = {'$fileName.part', '$fileName.part.meta'};
      for (final f in dir.listSync()) {
        if (!keep.contains(f.path.split(RegExp(r'[\\/]')).last)) {
          f.deleteSync(recursive: true);
        }
      }
      // A second round only when the server can't continue the .part.
      for (var round = 0; round < 2; round++) {
        final outcome = await _get(client, url, part, meta, onProgress);
        if (outcome == _Outcome.restart) {
          _delete(part, meta);
          continue;
        }
        if (outcome == _Outcome.failed) return null;
        if (meta.existsSync()) meta.deleteSync();
        return part.renameSync('${dir.path}/$fileName').path;
      }
      return null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static void _delete(File part, File meta) {
    if (part.existsSync()) part.deleteSync();
    if (meta.existsSync()) meta.deleteSync();
  }

  Future<_Outcome> _get(
    HttpClient client,
    Uri url,
    File part,
    File meta,
    void Function(double? fraction)? onProgress,
  ) async {
    final have = part.existsSync() ? part.lengthSync() : 0;
    final validator = meta.existsSync() ? meta.readAsStringSync().trim() : '';
    final request = await client.getUrl(url).timeout(responseTimeout);
    if (have > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      if (validator.isNotEmpty) {
        request.headers.set(HttpHeaders.ifRangeHeader, validator);
      }
    }
    final HttpClientResponse response;
    try {
      response = await request.close().timeout(responseTimeout);
    } on Object {
      return _Outcome.failed; // offline: the .part stays for next time
    }
    final int start;
    final int total;
    if (have > 0 && response.statusCode == HttpStatus.partialContent) {
      // "bytes 1000-4999/5000"
      final range = RegExp(
        r'bytes (\d+)-\d+/(\d+|\*)',
      ).firstMatch(
          response.headers.value(HttpHeaders.contentRangeHeader) ?? '');
      final from = int.tryParse(range?.group(1) ?? '');
      if (from != have) {
        await _drain(response);
        return _Outcome.restart;
      }
      start = have;
      total = int.tryParse(range!.group(2)!) ??
          (response.contentLength < 0 ? -1 : have + response.contentLength);
    } else if (response.statusCode == HttpStatus.ok) {
      start = 0; // no range (or the file changed): from the beginning
      total = response.contentLength;
      final v = response.headers.value(HttpHeaders.etagHeader) ??
          response.headers.value(HttpHeaders.lastModifiedHeader);
      if (v == null) {
        if (meta.existsSync()) meta.deleteSync();
      } else {
        meta.writeAsStringSync(v);
      }
    } else if (have > 0 &&
        response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      await _drain(response);
      return _Outcome.restart;
    } else {
      await _drain(response);
      return _Outcome.failed;
    }
    var received = start;
    final sink = part.openWrite(
      mode: start > 0 ? FileMode.writeOnlyAppend : FileMode.writeOnly,
    );
    var complete = false;
    try {
      await for (final chunk in response.timeout(idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(total > 0 ? received / total : null);
      }
      complete = true;
    } on Object {
      complete = false; // cut off: continue from here next time
    } finally {
      await sink.close();
    }
    if (!complete) return _Outcome.failed;
    if (total > 0 && received != total) {
      // Too long can't be continued; too short (cut off cleanly) can.
      if (received > total) _delete(part, meta);
      return _Outcome.failed;
    }
    return _Outcome.done;
  }

  static Future<void> _drain(HttpClientResponse r) =>
      r.drain<void>().catchError((_) {});

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  Future<String?> downloaded(String fileName) async {
    try {
      final file = File('${(await _dir()).path}/$fileName');
      return file.existsSync() && file.lengthSync() > 0 ? file.path : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<Uri?> signedAssetUrl(Uri assetApiUrl, String token) async {
    final client = _client();
    try {
      final request = await client.getUrl(assetApiUrl);
      request
        ..followRedirects = false
        ..headers.set('Authorization', 'Bearer $token')
        ..headers.set('Accept', 'application/octet-stream')
        ..headers.set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(connectionTimeout);
      // Don't download the APK body; only the redirect matters.
      unawaited(_drain(response));
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.isRedirect && location != null) {
        return Uri.tryParse(location);
      }
      return null;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

enum _Outcome { done, failed, restart }
