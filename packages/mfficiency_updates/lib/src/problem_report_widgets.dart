import 'dart:async';

import 'package:flutter/material.dart';

import 'problem_report.dart';

/// Every text of the problem report, English by default.
class ProblemReportStrings {
  const ProblemReportStrings({
    this.title = 'Report a problem to Claude',
    this.intro =
        'Describe what went wrong. Claude gets this and the app\'s logs, '
            'fixes the code, and the fix arrives as an update.',
    this.descriptionLabel = 'What happened? What did you expect?',
    this.includeLogs = 'Include the app\'s logs',
    this.logLines = _logLines,
    this.send = 'Send to Claude',
    this.viaToken = _viaToken,
    this.viaBrowser =
        'No GitHub token set: Send opens GitHub in the browser with the '
            'report filled in (logs shortened). Settings › Problem reports '
            'sends it straight from the app.',
    this.sent = _sent,
    this.openedInBrowser =
        'Opened on GitHub: tap "Create" there to hand it to Claude.',
    this.badToken =
        'GitHub refused the token. It needs "Issues: Read and write" on '
            'this app\'s repository (Settings › Problem reports).',
    this.failed = 'Couldn\'t send the report. Check the connection and try '
        'again.',
    this.notConfigured = 'Problem reports aren\'t set up for this app.',
    this.settingsTitle = 'Problem reports to Claude',
    this.settingsTokenSet = 'GitHub token set: reports go straight to Claude',
    this.settingsNoToken =
        'No token: reports open GitHub in the browser. Tap to set up',
    this.setupTitle = 'Problem reports to Claude',
    this.setupHelp = _setupHelp,
    this.tokenLabel = 'GitHub token (Issues: Read and write)',
    this.createToken = 'Create a token on GitHub',
    this.removeToken = 'Remove token',
    this.close = 'Close',
  });

  final String title;
  final String intro;
  final String descriptionLabel;
  final String includeLogs;
  final String Function(int lines) logLines;
  final String send;
  final String Function(String repo) viaToken;
  final String viaBrowser;
  final String Function(int? number) sent;
  final String openedInBrowser;
  final String badToken;
  final String failed;
  final String notConfigured;
  final String settingsTitle;
  final String settingsTokenSet;
  final String settingsNoToken;
  final String setupTitle;

  /// The steps to get the token, for the repo ("owner/repo").
  final String Function(String repo) setupHelp;
  final String tokenLabel;
  final String createToken;
  final String removeToken;
  final String close;

  static String _logLines(int lines) => lines == 1 ? '1 line' : '$lines lines';
  static String _viaToken(String repo) =>
      'Goes straight to GitHub as an issue in $repo.';
  static String _sent(int? number) => number == null
      ? 'Sent. Claude is on it; the fix comes as an update.'
      : 'Sent as issue #$number. Claude is on it; the fix comes as an update.';
  static String _setupHelp(String repo) =>
      'Double-tap the version in the menu to report a problem. The report '
      '(your description and the app\'s logs) becomes an issue in $repo on '
      'GitHub. Claude reads it, fixes the code, merges the fix into dev and '
      'the next update brings it.\n'
      '\n'
      'To send reports straight from the app, paste a GitHub token below:\n'
      '1. Tap "Create a token on GitHub" (or GitHub › Settings › Developer '
      'settings › Personal access tokens › Fine-grained tokens › Generate new '
      'token).\n'
      '2. Name it e.g. "Problem reports", pick an expiry.\n'
      '3. Repository access: "Only select repositories" › $repo. Pick all your '
      'app repositories instead and the same token works in every app.\n'
      '4. Permissions › Repository permissions › Issues: "Read and write". '
      'Add Contents: "Read-only" too and the same token also downloads the '
      'other apps (About › Other apps).\n'
      '5. Generate token, copy it and paste it here. It stays on this phone.\n'
      '\n'
      'Without a token, Send opens GitHub in the browser with the report '
      'filled in; tap "Create" there.\n'
      '\n'
      'Once per repository (on GitHub, not in the app): Claude needs its own '
      'key to work on the issues. On a computer with Claude Code run '
      '"claude setup-token" (Claude Pro or Max) and save the result under '
      '$repo › Settings › Secrets and variables › Actions as '
      'CLAUDE_CODE_OAUTH_TOKEN. Or an API key from console.anthropic.com as '
      'ANTHROPIC_API_KEY.';
}

/// Opens the "Report a problem to Claude" sheet on a double tap on [child]
/// (the app's name or version in its menu). Single taps still reach
/// [child], a little later (Flutter waits to see whether a second one comes).
class ProblemReportTrigger extends StatelessWidget {
  const ProblemReportTrigger({
    super.key,
    required this.reporter,
    required this.child,
    this.strings = const ProblemReportStrings(),
  });

  final ProblemReporter? reporter;
  final Widget child;
  final ProblemReportStrings strings;

  @override
  Widget build(BuildContext context) {
    final r = reporter;
    if (r == null) return child;
    return GestureDetector(
      key: const Key('problemReport.trigger'),
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => showProblemReport(context, r, strings: strings),
      child: child,
    );
  }
}

/// The report sheet: a field for the description, logs on/off, Send.
Future<void> showProblemReport(
  BuildContext context,
  ProblemReporter reporter, {
  ProblemReportStrings strings = const ProblemReportStrings(),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ProblemReportSheet(
      reporter: reporter,
      strings: strings,
      onDone: (text) => messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text))),
    ),
  );
}

class ProblemReportSheet extends StatefulWidget {
  const ProblemReportSheet({
    super.key,
    required this.reporter,
    this.strings = const ProblemReportStrings(),
    this.onDone,
  });

  final ProblemReporter reporter;
  final ProblemReportStrings strings;

  /// Called with the message to show once the sheet closed after sending.
  final void Function(String message)? onDone;

  @override
  State<ProblemReportSheet> createState() => _ProblemReportSheetState();
}

class _ProblemReportSheetState extends State<ProblemReportSheet> {
  final _text = TextEditingController();
  late final Future<String> _logs = widget.reporter.logs();
  late Future<String?> _token = widget.reporter.token();
  var _includeLogs = true;
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = widget.strings;
    setState(() {
      _sending = true;
      _error = null;
    });
    final result = await widget.reporter.send(
      _text.text,
      includeLogs: _includeLogs,
    );
    if (!mounted) return;
    final done = switch (result.outcome) {
      ProblemReportOutcome.sent => s.sent(result.issueNumber),
      ProblemReportOutcome.openedInBrowser => s.openedInBrowser,
      _ => null,
    };
    if (done != null) {
      Navigator.of(context).pop();
      widget.onDone?.call(done);
      return;
    }
    setState(() {
      _sending = false;
      _token = widget.reporter.token();
      _error = switch (result.outcome) {
        ProblemReportOutcome.badToken => s.badToken,
        ProblemReportOutcome.notConfigured => s.notConfigured,
        _ => s.failed,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final canSend = !_sending &&
        widget.reporter.isConfigured &&
        (_text.text.trim().isNotEmpty || _includeLogs);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(s.intro, style: muted),
            const SizedBox(height: 16),
            TextField(
              key: const Key('problemReport.text'),
              controller: _text,
              autofocus: true,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: s.descriptionLabel,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            FutureBuilder<String>(
              future: _logs,
              builder: (context, snap) {
                final lines = snap.data == null || snap.data!.trim().isEmpty
                    ? 0
                    : '\n'.allMatches(snap.data!.trimRight()).length + 1;
                return SwitchListTile(
                  key: const Key('problemReport.logs'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.includeLogs),
                  subtitle: snap.hasData ? Text(s.logLines(lines)) : null,
                  value: _includeLogs,
                  onChanged:
                      _sending ? null : (v) => setState(() => _includeLogs = v),
                );
              },
            ),
            if (_error case final error?) ...[
              Text(
                error,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              key: const Key('problemReport.send'),
              onPressed: canSend ? _send : null,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(s.send),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<String?>(
              future: _token,
              builder: (context, snap) => Text(
                !widget.reporter.isConfigured
                    ? s.notConfigured
                    : snap.data == null
                        ? s.viaBrowser
                        : s.viaToken(widget.reporter.config.githubRepo),
                style: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings row: whether a token is set; a tap opens the explanation and
/// the token field.
class ProblemReportSettingsTile extends StatelessWidget {
  const ProblemReportSettingsTile({
    super.key,
    required this.reporter,
    this.strings = const ProblemReportStrings(),
  });

  final ProblemReporter reporter;
  final ProblemReportStrings strings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: reporter,
        builder: (context, _) => FutureBuilder<String?>(
          future: reporter.token(),
          builder: (context, snap) => ListTile(
            key: const Key('problemReport.settings'),
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(strings.settingsTitle),
            subtitle: Text(
              snap.data == null
                  ? strings.settingsNoToken
                  : strings.settingsTokenSet,
            ),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => ProblemReportSetupDialog(
                  reporter: reporter, strings: strings),
            ),
          ),
        ),
      );
}

/// The steps to get a token and its field. No Save button: the token is
/// saved as it is pasted or typed.
class ProblemReportSetupDialog extends StatefulWidget {
  const ProblemReportSetupDialog({
    super.key,
    required this.reporter,
    this.strings = const ProblemReportStrings(),
  });

  final ProblemReporter reporter;
  final ProblemReportStrings strings;

  @override
  State<ProblemReportSetupDialog> createState() =>
      _ProblemReportSetupDialogState();
}

class _ProblemReportSetupDialogState extends State<ProblemReportSetupDialog> {
  final _token = TextEditingController();
  var _hasToken = false;
  Future<void> _saving = Future.value();

  @override
  void initState() {
    super.initState();
    widget.reporter.token().then((t) {
      if (!mounted || t == null) return;
      setState(() {
        _hasToken = true;
        _token.text = t;
      });
    });
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  void _save(String value) {
    // One write at a time, in order.
    _saving = _saving.then((_) => widget.reporter.setToken(value));
    setState(() => _hasToken = value.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final repo = widget.reporter.config.githubRepo;
    return AlertDialog(
      title: Text(s.setupTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(s.setupHelp(repo)),
          const SizedBox(height: 12),
          TextButton.icon(
            key: const Key('problemReport.createToken'),
            onPressed: () =>
                widget.reporter.openUrl(ProblemReportConfig.tokenPage),
            icon: const Icon(Icons.open_in_new),
            label: Text(s.createToken),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('problemReport.token'),
            controller: _token,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _save,
            decoration: InputDecoration(
              labelText: s.tokenLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        if (_hasToken)
          TextButton(
            onPressed: () {
              _token.clear();
              _save('');
            },
            child: Text(s.removeToken),
          ),
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            await _saving;
            nav.pop();
          },
          child: Text(s.close),
        ),
      ],
    );
  }
}
