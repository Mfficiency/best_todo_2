import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'http.dart';

/// [UpdateHttp] on dart:io's HttpClient, with a small in-memory cache for
/// requests that allow one.
class IoUpdateHttp extends UpdateHttp {
  IoUpdateHttp({this.timeout = const Duration(seconds: 20), this.userAgent});
  final Duration timeout;

  /// Sent as `User-Agent` (null: dart:io's own).
  final String? userAgent;
  final _cache = <Uri, (DateTime, Object?)>{};

  @override
  Future<Object?> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? cacheFor,
  }) async {
    final hit = _cache[url];
    if (cacheFor != null &&
        hit != null &&
        DateTime.now().difference(hit.$1) < cacheFor) {
      return hit.$2;
    }
    final client = HttpClient()..connectionTimeout = timeout;
    if (userAgent case final ua?) client.userAgent = ua;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UpdateHttpException(response.statusCode, null, {
          for (final h in UpdateHttpException.rateLimitHeaders)
            if (response.headers.value(h) case final v?) h: v,
        });
      }
      final json = jsonDecode(body);
      _cache[url] = (DateTime.now(), json);
      return json;
    } on UpdateHttpException {
      rethrow;
    } on Object catch (e) {
      throw UpdateHttpException(null, e);
    } finally {
      client.close(force: true);
    }
  }
}
