import 'dart:convert';
import 'dart:io';

import 'http.dart';
import 'problem_report.dart';

/// The default [ProblemReportPost]: dart:io's HttpClient.
ProblemReportPost postJson({
  Duration timeout = const Duration(seconds: 30),
  String? userAgent,
}) =>
    (url, headers, body) async {
      final client = HttpClient()..connectionTimeout = timeout;
      if (userAgent != null) client.userAgent = userAgent;
      try {
        final request = await client.postUrl(url).timeout(timeout);
        headers.forEach(request.headers.set);
        request.add(utf8.encode(jsonEncode(body)));
        final response = await request.close().timeout(timeout);
        final text =
            await response.transform(utf8.decoder).join().timeout(timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw UpdateHttpException(response.statusCode, text);
        }
        return text.isEmpty ? null : jsonDecode(text);
      } on UpdateHttpException {
        rethrow;
      } on Object catch (e) {
        throw UpdateHttpException(null, e);
      } finally {
        client.close(force: true);
      }
    };
