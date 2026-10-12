import 'http_stub.dart' if (dart.library.io) 'http_io.dart' as impl;

/// A request GitHub or the manifest server answered with an error status
/// ([status]), or that failed without one (offline, timeout: null).
class UpdateHttpException implements Exception {
  const UpdateHttpException(this.status, [this.cause, this.headers = const {}]);
  final int? status;
  final Object? cause;

  /// Response headers that matter for GitHub's rate limit, lower-case names:
  /// `retry-after`, `x-ratelimit-remaining`, `x-ratelimit-reset`. Adapters
  /// that can't read headers leave it empty (see [isRateLimit]).
  final Map<String, String> headers;

  /// GitHub's rate limit: 429, or a 403 that says so (`x-ratelimit-remaining:
  /// 0` or `retry-after`). [anonymous]: the request carried no token, where
  /// a 403 from the API is always the limit (so an adapter without headers
  /// is covered too).
  bool isRateLimit({bool anonymous = false}) {
    if (status == 429) return true;
    if (status != 403) return false;
    return anonymous ||
        headers['x-ratelimit-remaining']?.trim() == '0' ||
        headers.containsKey('retry-after');
  }

  /// When GitHub accepts requests again ([isRateLimit]): `retry-after`
  /// (seconds) after [now], else `x-ratelimit-reset` (epoch seconds); null
  /// when neither says (or it lies in the past).
  DateTime? rateLimitReset(DateTime now) {
    final after = int.tryParse(headers['retry-after']?.trim() ?? '');
    if (after != null) return now.add(Duration(seconds: after));
    final reset = int.tryParse(headers['x-ratelimit-reset']?.trim() ?? '');
    if (reset == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(reset * 1000);
    return at.isAfter(now) ? at : null;
  }

  /// The headers [UpdateHttpException.headers] keeps.
  static const rateLimitHeaders = [
    'retry-after',
    'x-ratelimit-remaining',
    'x-ratelimit-reset',
  ];

  @override
  String toString() => 'UpdateHttpException($status)';
}

/// The JSON requests of a check (releases list, manifest). Apps with their
/// own HTTP client (cache, offline handling, a web preview) pass an adapter;
/// the default uses dart:io.
abstract class UpdateHttp {
  const UpdateHttp();

  /// The default: dart:io's HttpClient (not on the web). [userAgent]: the
  /// `User-Agent` header (GitHub asks for one naming the app).
  factory UpdateHttp.io({Duration timeout, String? userAgent}) =
      impl.IoUpdateHttp;

  /// Adapter for an app's own client: [get] returns the decoded JSON and
  /// throws [UpdateHttpException] for an error status.
  factory UpdateHttp.from(
    Future<Object?> Function(
      Uri url,
      Map<String, String> headers,
      Duration? cacheFor,
    ) get,
  ) = _FunctionHttp;

  /// GETs [url] and decodes the JSON body. [cacheFor]: an answer this young
  /// may come from a cache (the older-versions list). Throws
  /// [UpdateHttpException].
  Future<Object?> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? cacheFor,
  });
}

class _FunctionHttp extends UpdateHttp {
  const _FunctionHttp(this._get);
  final Future<Object?> Function(
    Uri url,
    Map<String, String> headers,
    Duration? cacheFor,
  ) _get;

  @override
  Future<Object?> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? cacheFor,
  }) =>
      _get(url, headers, cacheFor);
}
