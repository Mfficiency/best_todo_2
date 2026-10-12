import 'http.dart';

/// Web: no dart:io. Apps that check for updates in a browser pass their
/// own [UpdateHttp].
class IoUpdateHttp extends UpdateHttp {
  const IoUpdateHttp({
    Duration timeout = const Duration(seconds: 20),
    String? userAgent,
  });

  @override
  Future<Object?> getJson(
    Uri url, {
    Map<String, String> headers = const {},
    Duration? cacheFor,
  }) async =>
      throw const UpdateHttpException(null, 'unsupported');
}
