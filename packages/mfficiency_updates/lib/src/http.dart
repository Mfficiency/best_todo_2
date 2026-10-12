import 'http_stub.dart' if (dart.library.io) 'http_io.dart' as impl;

/// A request GitHub or the manifest server answered with an error status
/// ([status]), or that failed without one (offline, timeout: null).
class UpdateHttpException implements Exception {
  const UpdateHttpException(this.status, [this.cause]);
  final int? status;
  final Object? cause;

  @override
  String toString() => 'UpdateHttpException($status)';
}

/// The JSON requests of a check (releases list, manifest). Apps with their
/// own HTTP client (cache, offline handling, a web preview) pass an adapter;
/// the default uses dart:io.
abstract class UpdateHttp {
  const UpdateHttp();

  /// The default: dart:io's HttpClient (not on the web).
  factory UpdateHttp.io({Duration timeout}) = impl.IoUpdateHttp;

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
