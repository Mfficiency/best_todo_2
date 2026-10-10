import '../config.dart';
import 'video_summary_service.dart';

/// Builds the Markdown research note for a video summary and the
/// `obsidian://new` link that saves it straight into the Obsidian vault's
/// research folder (Best Music Settings → Transcripts & summaries).
class ObsidianResearchNote {
  ObsidianResearchNote._();

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _yaml(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// A file name Obsidian (and Android/Windows) accepts for [title].
  static String fileName(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|#^\[\]]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final short =
        cleaned.length > 100 ? cleaned.substring(0, 100).trim() : cleaned;
    return short.isEmpty ? 'Video summary' : short;
  }

  /// The note: Obsidian Properties (frontmatter) followed by the summary.
  static String markdown({
    required String title,
    required String channel,
    required String url,
    required VideoSummary summary,
    DateTime? published,
    DateTime? now,
  }) {
    final b = StringBuffer()
      ..writeln('---')
      ..writeln('title: ${_yaml(title)}')
      ..writeln('source: $url')
      ..writeln('channel: ${_yaml(channel)}');
    if (published != null) b.writeln('published: ${_date(published)}');
    b
      ..writeln('created: ${_date(now ?? DateTime.now())}')
      ..writeln('tags:')
      ..writeln('  - research')
      ..writeln('  - video')
      ..writeln('---')
      ..writeln()
      ..writeln('# $title')
      ..writeln()
      ..writeln('[$channel]($url)')
      ..writeln()
      ..writeln(summary.toMarkdown());
    return b.toString();
  }

  /// `obsidian://new?vault=…&file=<folder>/<name>&content=…` — Obsidian
  /// creates the note in that folder and opens it. Percent-encoded by hand:
  /// [Uri.queryParameters] writes spaces as `+`, which Obsidian keeps.
  static Uri saveUri({
    required String title,
    required String content,
    String? vault,
    String? folder,
  }) {
    final v = (vault ?? Config.obsidianVault).trim();
    final f = (folder ?? Config.obsidianResearchFolder)
        .trim()
        .replaceAll(RegExp(r'^/+|/+$'), '');
    final path = f.isEmpty ? fileName(title) : '$f/${fileName(title)}';
    final params = [
      if (v.isNotEmpty) 'vault=${Uri.encodeComponent(v)}',
      'file=${Uri.encodeComponent(path)}',
      'content=${Uri.encodeComponent(content)}',
    ];
    return Uri.parse('obsidian://new?${params.join('&')}');
  }
}
