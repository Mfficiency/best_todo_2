import 'package:flutter/material.dart';

import 'controller.dart';
import 'github_token_dialog.dart';

/// The texts of [UpdateTokenTile], English by default.
class UpdateTokenStrings {
  const UpdateTokenStrings({
    this.title = 'GitHub token',
    this.tokenSet = 'Token set',
    this.noToken = 'No token',
    this.summary = _summary,
    this.help = _help,
    this.tokenLabel = 'GitHub token',
    this.dialog = const GithubTokenStrings(),
  });

  final String title;
  final String tokenSet;
  final String noToken;

  /// One line under the field, for the repo ("owner/repo").
  final String Function(String repo) summary;

  /// The steps to get the token, for the repo.
  final String Function(String repo) help;
  final String tokenLabel;
  final GithubTokenStrings dialog;

  static String _summary(String repo) => 'Reads the releases of $repo (Contents: Read-only).';

  static String _help(String repo) =>
      'A private repository needs a token that can read it; a public one '
      'works without (a token only lifts GitHub\'s limit).\n'
      '1. Tap "Create a token on GitHub" (fine-grained token).\n'
      '2. Repository access: $repo, or all app repositories so one token works '
      'in every app.\n'
      '3. Permissions: Contents "Read-only" (add Issues "Read and write" and '
      'the same token also sends problem reports).\n'
      '4. Generate, copy and paste it above. It stays on this phone.';
}

/// Settings row "GitHub token" of the Updates section: "Token set" or "No
/// token"; a tap opens [GithubTokenDialog]. The token is saved as it is
/// typed or pasted ([writeToken]), then the controller reads it again and
/// checks at once; its answer shows under the field.
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListTile(
          key: const Key('updates.token'),
          leading: const Icon(Icons.key_outlined),
          title: Text(strings.title),
          subtitle: Text(controller.hasToken ? strings.tokenSet : strings.noToken),
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => GithubTokenDialog(
              title: strings.title,
              label: strings.tokenLabel,
              summary: strings.summary(repo),
              help: strings.help(repo),
              readToken: readToken,
              writeToken: writeToken,
              openUrl: openUrl,
              fieldKey: const Key('updates.token.field'),
              strings: strings.dialog,
              afterSave: () async {
                final r = await controller.reloadToken();
                if (!dialogContext.mounted) return null;
                return controller.statusLabel(controller.stringsOf(dialogContext), r);
              },
            ),
          ),
        ),
      );
}
