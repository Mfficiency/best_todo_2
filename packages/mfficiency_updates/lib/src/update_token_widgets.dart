import 'dart:async';

import 'package:flutter/material.dart';

import 'controller.dart';

/// The texts of [UpdateTokenTile], English by default.
class UpdateTokenStrings {
  const UpdateTokenStrings({
    this.title = 'GitHub token',
    this.tokenSet = 'Token set: updates are checked with it',
    this.noToken = 'No token: needed for a private repository. Tap to set up',
    this.help = _help,
    this.tokenLabel = 'GitHub token (Contents: Read-only)',
    this.createToken = 'Create a token on GitHub',
    this.removeToken = 'Remove token',
    this.close = 'Close',
  });

  final String title;
  final String tokenSet;
  final String noToken;

  /// The steps to get the token, for the repo ("owner/repo").
  final String Function(String repo) help;
  final String tokenLabel;
  final String createToken;
  final String removeToken;
  final String close;

  static String _help(String repo) =>
      'Updates come from the releases of $repo. A private repository needs a '
      'GitHub token that can read it (a public one works without, a token '
      'only lifts GitHub\'s limit):\n'
      '1. Tap "Create a token on GitHub" (fine-grained token).\n'
      '2. Repository access: $repo, or all app repositories so one token works '
      'in every app.\n'
      '3. Permissions: Contents "Read-only" (add Issues "Read and write" and '
      'the same token also sends problem reports).\n'
      '4. Generate, copy and paste it here. It stays on this phone.';
}

/// Settings row "GitHub token" of the Updates section: whether a token is
/// set; a tap opens the steps and the field. The token is saved as it is
/// typed or pasted ([writeToken]), then the controller reads it again and
/// checks at once; its answer shows below the field.
class UpdateTokenTile extends StatelessWidget {
  const UpdateTokenTile({
    super.key,
    required this.controller,
    required this.repo,
    required this.readToken,
    required this.writeToken,
    required this.openUrl,
    this.strings = const UpdateTokenStrings(),
  });

  final UpdateController controller;

  /// "owner/repo" the updates come from.
  final String repo;
  final Future<String?> Function() readToken;

  /// Null removes the token.
  final Future<void> Function(String? token) writeToken;
  final Future<bool> Function(String url) openUrl;
  final UpdateTokenStrings strings;

  static const tokenPage =
      'https://github.com/settings/personal-access-tokens/new';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListTile(
          key: const Key('updates.token'),
          leading: const Icon(Icons.key_outlined),
          title: Text(strings.title),
          subtitle:
              Text(controller.hasToken ? strings.tokenSet : strings.noToken),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _UpdateTokenDialog(tile: this),
          ),
        ),
      );
}

class _UpdateTokenDialog extends StatefulWidget {
  const _UpdateTokenDialog({required this.tile});
  final UpdateTokenTile tile;

  @override
  State<_UpdateTokenDialog> createState() => _UpdateTokenDialogState();
}

class _UpdateTokenDialogState extends State<_UpdateTokenDialog> {
  final _field = TextEditingController();
  Future<void> _saving = Future.value();
  Timer? _debounce;
  var _hasToken = false;
  String? _status;

  UpdateTokenTile get t => widget.tile;

  @override
  void initState() {
    super.initState();
    t.readToken().then((v) {
      if (!mounted || v == null || v.trim().isEmpty) return;
      setState(() {
        _hasToken = true;
        _field.text = v;
      });
    });
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      unawaited(_save(_field.text));
    }
    _field.dispose();
    super.dispose();
  }

  /// One write at a time, in order; then the controller checks with it.
  Future<void> _save(String value) {
    final token = value.trim().isEmpty ? null : value.trim();
    return _saving = _saving.then((_) async {
      await t.writeToken(token);
      final r = await t.controller.reloadToken();
      if (!mounted) return;
      setState(() => _status =
          t.controller.statusLabel(t.controller.stringsOf(context), r));
    });
  }

  void _changed(String value) {
    setState(() => _hasToken = value.trim().isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _save(value));
  }

  @override
  Widget build(BuildContext context) {
    final s = t.strings;
    return AlertDialog(
      title: Text(s.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(s.help(t.repo)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => t.openUrl(UpdateTokenTile.tokenPage),
            icon: const Icon(Icons.open_in_new),
            label: Text(s.createToken),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('updates.token.field'),
            controller: _field,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _changed,
            decoration: InputDecoration(
              labelText: s.tokenLabel,
              hintText: 'github_pat_…',
              helperText: _status,
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        if (_hasToken)
          TextButton(
            onPressed: () {
              _debounce?.cancel();
              _field.clear();
              setState(() => _hasToken = false);
              _save('');
            },
            child: Text(s.removeToken),
          ),
        TextButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            if (_debounce?.isActive ?? false) {
              _debounce!.cancel();
              await _save(_field.text);
            }
            await _saving;
            nav.pop();
          },
          child: Text(s.close),
        ),
      ],
    );
  }
}
