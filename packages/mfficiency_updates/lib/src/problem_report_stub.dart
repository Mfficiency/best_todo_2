import 'http.dart';
import 'problem_report.dart';

/// Web: no dart:io. Apps in a browser pass their own `post`, or the report
/// opens GitHub's new-issue page instead (no token).
ProblemReportPost postJson({
  Duration timeout = const Duration(seconds: 30),
  String? userAgent,
}) =>
    (url, headers, body) async =>
        throw const UpdateHttpException(null, 'unsupported');
