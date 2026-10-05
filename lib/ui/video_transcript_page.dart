import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/obsidian_research_note.dart';
import '../services/video_summary_service.dart';
import '../services/video_transcript_service.dart';
import 'estimated_progress_bar.dart';
import 'music_settings_page.dart';
import 'subpage_app_bar.dart';

/// The video a transcript or summary page is about.
class VideoRef {
  const VideoRef({
    required this.videoId,
    required this.title,
    required this.channel,
    this.published,
  });

  final String videoId;
  final String title;
  final String channel;
  final DateTime? published;

  String get url => 'https://www.youtube.com/watch?v=$videoId';
}

String _timestamp(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

String _transcriptMarkdown(VideoRef video, VideoTranscript transcript) {
  final b = StringBuffer()
    ..writeln('# ${video.title}')
    ..writeln()
    ..writeln('[${video.channel}](${video.url})')
    ..writeln();
  for (final p in transcript.paragraphs()) {
    b
      ..writeln('**${_timestamp(p.start)}** ${p.text}')
      ..writeln();
  }
  return b.toString();
}

Widget _errorView(BuildContext context, Object error, VoidCallback onRetry) {
  final theme = Theme.of(context);
  final message = error is TranscriptUnavailableException
      ? "This video has no transcript we could get — YouTube and the "
          'backup sites (Invidious) had no captions for it.'
      : error.toString();
  return ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Icon(Icons.subtitles_off_outlined,
          size: 48, color: theme.colorScheme.outline),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
      if (error is TranscriptUnavailableException) ...[
        const SizedBox(height: 12),
        Text(error.attempts.join('\n'),
            textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      Center(
        child: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ),
    ],
  );
}

/// A video's full transcript, paragraph by paragraph with timestamps, with
/// Copy/Share and a "Quick summary" button.
class VideoTranscriptPage extends StatefulWidget {
  const VideoTranscriptPage({super.key, required this.video, this.service});

  final VideoRef video;
  final VideoTranscriptService? service;

  @override
  State<VideoTranscriptPage> createState() => _VideoTranscriptPageState();
}

class _VideoTranscriptPageState extends State<VideoTranscriptPage> {
  late final VideoTranscriptService _service =
      widget.service ?? VideoTranscriptService.instance;
  VideoTranscript? _transcript;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _transcript = _service.cached(widget.video.videoId);
    if (_transcript == null) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final t = await _service.fetch(widget.video.videoId);
      if (mounted) setState(() => _transcript = t);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final transcript = _transcript;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Transcript',
        actions: [
          if (transcript != null) ...[
            IconButton(
              tooltip: 'Copy transcript',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(
                    text: _transcriptMarkdown(widget.video, transcript)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transcript copied')));
                }
              },
            ),
            IconButton(
              tooltip: 'Share transcript',
              icon: const Icon(Icons.share),
              onPressed: () => SharePlus.instance.share(ShareParams(
                text: _transcriptMarkdown(widget.video, transcript),
                subject: '${widget.video.title} (transcript)',
              )),
            ),
          ],
        ],
      ),
      body: _error != null
          ? _errorView(context, _error!, _load)
          : transcript == null
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: EstimatedProgressBar(
                      active: true, expected: Duration(seconds: 5)),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(widget.video.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      '${transcript.source} · '
                      '${transcript.languageName.isNotEmpty ? transcript.languageName : transcript.languageCode}'
                      '${transcript.autoGenerated ? ' (auto-generated)' : ''}'
                      ' · ${transcript.wordCount} words',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => VideoSummaryPage(
                                  video: widget.video,
                                  transcriptService: _service))),
                      icon: const Icon(Icons.summarize_outlined),
                      label: const Text('Quick summary'),
                    ),
                    const Divider(height: 32),
                    for (final p in transcript.paragraphs())
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SelectableText.rich(TextSpan(children: [
                          TextSpan(
                            text: '${_timestamp(p.start)}  ',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                          TextSpan(text: p.text),
                        ])),
                      ),
                  ],
                ),
    );
  }
}

/// "Quick summary" of a video: fetches its transcript, summarizes it
/// (Claude with an API key, on-device otherwise) and offers Share and Save
/// to Obsidian (into the research folder).
class VideoSummaryPage extends StatefulWidget {
  const VideoSummaryPage({
    super.key,
    required this.video,
    this.transcriptService,
    this.summaryService,
  });

  final VideoRef video;
  final VideoTranscriptService? transcriptService;
  final VideoSummaryService? summaryService;

  @override
  State<VideoSummaryPage> createState() => _VideoSummaryPageState();
}

class _VideoSummaryPageState extends State<VideoSummaryPage> {
  late final VideoTranscriptService _transcripts =
      widget.transcriptService ?? VideoTranscriptService.instance;
  late final VideoSummaryService _summaries =
      widget.summaryService ?? VideoSummaryService.instance;

  VideoSummary? _summary;
  Object? _error;
  String _step = 'Getting the transcript…';

  /// Set when Claude failed and the on-device summary is shown instead.
  String? _claudeError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _summary = null;
      _claudeError = null;
      _step = 'Getting the transcript…';
    });
    try {
      final transcript = await _transcripts.fetch(widget.video.videoId);
      if (!mounted) return;
      setState(() => _step = Config.claudeApiKey.trim().isEmpty
          ? 'Summarizing…'
          : 'Claude is summarizing…');
      VideoSummary summary;
      try {
        summary = await _summaries.summarize(
          title: widget.video.title,
          channel: widget.video.channel,
          transcript: transcript,
        );
      } on VideoSummaryException catch (e) {
        _claudeError = e.message;
        summary = VideoSummaryService.extractiveSummary(transcript);
      }
      if (mounted) setState(() => _summary = summary);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _note(VideoSummary summary) => ObsidianResearchNote.markdown(
        title: widget.video.title,
        channel: widget.video.channel,
        url: widget.video.url,
        published: widget.video.published,
        summary: summary,
      );

  Future<void> _share(VideoSummary summary) => SharePlus.instance
      .share(ShareParams(text: _note(summary), subject: widget.video.title));

  Future<void> _saveToObsidian(VideoSummary summary) async {
    final uri = ObsidianResearchNote.saveUri(
        title: widget.video.title, content: _note(summary));
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't open Obsidian — use Share instead")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Quick summary'),
      body: _error != null
          ? _errorView(context, _error!, _load)
          : summary == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_step, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      const EstimatedProgressBar(
                          active: true, expected: Duration(seconds: 20)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(widget.video.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(widget.video.channel,
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        onPressed: () => _saveToObsidian(summary),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Save to Obsidian'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _share(summary),
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: _note(summary)));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Summary copied')));
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                    ]),
                    if (!summary.byClaude)
                      Card(
                        margin: const EdgeInsets.only(top: 12),
                        child: ListTile(
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: Text(_claudeError != null
                              ? 'Claude failed — showing a quick on-device summary'
                              : 'Quick on-device summary'),
                          subtitle: Text(_claudeError ??
                              'Add a Claude API key in Settings for a '
                                  'proper written summary.'),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const MusicSettingsPage(
                                    initialSection:
                                        MusicSettingsSection.summaries)));
                            if (mounted) unawaited(_load());
                          },
                        ),
                      ),
                    const Divider(height: 32),
                    if (summary.overview.isNotEmpty) ...[
                      Text('Summary', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      SelectableText(summary.overview),
                      const SizedBox(height: 16),
                    ],
                    if (summary.keyPoints.isNotEmpty) ...[
                      Text('Key points', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      for (final p in summary.keyPoints)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('•  '),
                              Expanded(child: SelectableText(p)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                    ],
                    if (summary.conclusion.isNotEmpty) ...[
                      Text('Conclusion', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Card(
                        color: theme.colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(summary.conclusion),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => VideoTranscriptPage(
                                  video: widget.video, service: _transcripts))),
                      icon: const Icon(Icons.subtitles_outlined),
                      label: const Text('Full transcript'),
                    ),
                  ],
                ),
    );
  }
}
