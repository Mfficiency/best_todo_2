import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The texts every GitHub token dialog shares, English by default.
class GithubTokenStrings {
  const GithubTokenStrings({
    this.show = 'Show token',
    this.hide = 'Hide token',
    this.copy = 'Copy token',
    this.copied = 'Copied',
    this.howTo = 'How to get a token',
    this.createToken = 'Create a token on GitHub',
    this.removeToken = 'Remove token',
    this.close = 'Close',
  });

  final String show;
  final String hide;
  final String copy;
  final String copied;
  final String howTo;
  final String createToken;
  final String removeToken;
  final String close;
}

/// The one GitHub token dialog of every Mfficiency app (problem reports,
/// updates, other apps): the field first (show, copy), one short line
/// below it, the full steps folded under "How to get a token". Saved as
/// typed (no Save button); Close is always visible.
class GithubTokenDialog extends StatefulWidget {
  const GithubTokenDialog({
    super.key,
    required this.title,
    required this.label,
    required this.summary,
    required this.help,
    required this.readToken,
    required this.writeToken,
    required this.openUrl,
    this.tokenPage = defaultTokenPage,
    this.afterSave,
    this.fieldKey,
    this.strings = const GithubTokenStrings(),
  });

  static const defaultTokenPage = 'https://github.com/settings/personal-access-tokens/new';

  final String title;

  /// The field's label, e.g. "GitHub token (Issues: Read and write)".
  final String label;

  /// One short line under the field: what the token is for.
  final String summary;

  /// The full steps, folded away until "How to get a token" is tapped.
  final String help;
  final Future<String?> Function() readToken;

  /// Null removes the token.
  final Future<void> Function(String? token) writeToken;
  final Future<bool> Function(String url) openUrl;
  final String tokenPage;

  /// Runs after each save; its text (e.g. what a check answered) shows
  /// under the field.
  final Future<String?> Function()? afterSave;
  final Key? fieldKey;
  final GithubTokenStrings strings;

  @override
  State<GithubTokenDialog> createState() => _GithubTokenDialogState();
}

class _GithubTokenDialogState extends State<GithubTokenDialog> {
  final _field = TextEditingController();
  Future<void> _saving = Future.value();
  Timer? _debounce;
  Timer? _copiedReset;
  var _visible = false;
  var _copied = false;
  String? _status;

  bool get _hasToken => _field.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.readToken().then((t) {
      if (!mounted || t == null || t.trim().isEmpty) return;
      setState(() => _field.text = t);
    });
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(_save(_field.text));
    }
    _copiedReset?.cancel();
    _field.dispose();
    super.dispose();
  }

  /// One write at a time, in order.
  Future<void> _save(String value) {
    final token = value.trim().isEmpty ? null : value.trim();
    return _saving = _saving.then((_) async {
      await widget.writeToken(token);
      final status = await widget.afterSave?.call();
      if (mounted && status != null) setState(() => _status = status);
    });
  }

  void _changed(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _save(value));
  }

  Future<void> _flush() async {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      await _save(_field.text);
    }
    await _saving;
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _field.text.trim()));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    // scrollable: title and content scroll, the actions (Close) stay put.
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: widget.fieldKey,
            controller: _field,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _changed,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: 'github_pat_…',
              helperText: _status,
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const Key('githubToken.show'),
                    tooltip: _visible ? s.hide : s.show,
                    icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _visible = !_visible),
                  ),
                  IconButton(
                    key: const Key('githubToken.copy'),
                    tooltip: _copied ? s.copied : s.copy,
                    icon: Icon(_copied ? Icons.check : Icons.copy_outlined),
                    onPressed: _hasToken ? _copy : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(widget.summary, style: muted),
          Theme(
            // No divider lines around the fold.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const Key('githubToken.howTo'),
              title: Text(s.howTo),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(widget.help),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('githubToken.create'),
                  onPressed: () => widget.openUrl(widget.tokenPage),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(s.createToken),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_hasToken)
          TextButton(
            key: const Key('githubToken.remove'),
            onPressed: () {
              _debounce?.cancel();
              _field.clear();
              setState(() => _status = null);
              _save('');
            },
            child: Text(s.removeToken),
          ),
        TextButton(
          key: const Key('githubToken.close'),
          onPressed: () async {
            final nav = Navigator.of(context);
            await _flush();
            nav.pop();
          },
          child: Text(s.close),
        ),
      ],
    );
  }
}
