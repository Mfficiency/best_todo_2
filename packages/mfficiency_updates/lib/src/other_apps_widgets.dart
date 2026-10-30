import 'dart:async';

import 'package:flutter/material.dart';

import 'github_token_dialog.dart';
import 'other_apps.dart';

/// Every text of "Other apps", English by default.
class OtherAppsStrings {
  const OtherAppsStrings({
    this.title = 'Other apps',
    this.linkSubtitle = 'All the other Mfficiency apps, to install from here',
    this.intro = 'Install or update the other apps straight from here: the '
        'newest release downloads in the background, then Android asks.',
    this.install = 'Install',
    this.update = 'Update',
    this.open = 'Open',
    this.onGithub = 'Open on GitHub',
    this.checking = 'Checking…',
    this.notInstalled = 'Not installed',
    this.installed = _installed,
    this.newest = _newest,
    this.noRelease = 'No release to download yet',
    this.needsToken = 'Private: needs the GitHub token (key icon above), or '
        'download it on GitHub',
    this.failed = 'GitHub couldn\'t be reached. Pull down to try again.',
    this.downloading = _downloading,
    this.installing = 'Android asks next: tap Install there.',
    this.needsPermission =
        'Turn on "Allow from this source" in the screen that opened, come '
            'back and tap Install again. Only needed once.',
    this.actionFailed = 'That didn\'t work. Try again, or use Open on GitHub.',
    this.tokenTitle = 'GitHub token for the other apps',
    this.tokenHelp = 'Most of the apps live in private GitHub repositories, so '
        'downloading them needs a token that can read them:\n'
        '1. Tap "Create a token on GitHub" (or GitHub › Settings › '
        'Developer settings › Personal access tokens › Fine-grained '
        'tokens › Generate new token).\n'
        '2. Repository access: "All repositories" (or select every app '
        'repository).\n'
        '3. Permissions › Repository permissions › Contents: "Read-only". '
        'Add Issues: "Read and write" too and the same token also sends '
        'problem reports to Claude.\n'
        '4. Generate token, copy it and paste it above. It stays on this '
        'phone.\n'
        '\n'
        'Without a token, Open on GitHub shows the app\'s releases in the '
        'browser, where you are logged in.',
    this.tokenSummary =
        'Downloads the apps in private repositories (Contents: Read-only).',
    this.tokenLabel = 'GitHub token',
    this.tokenDialog = const GithubTokenStrings(),
    this.tokenTooltip = 'GitHub token',
  });

  final String title;
  final String linkSubtitle;
  final String intro;
  final String install;
  final String update;
  final String open;
  final String onGithub;
  final String checking;
  final String notInstalled;
  final String Function(String version) installed;
  final String Function(String release) newest;
  final String noRelease;
  final String needsToken;
  final String failed;
  final String Function(int? percent) downloading;
  final String installing;
  final String needsPermission;
  final String actionFailed;
  final String tokenTitle;
  final String tokenHelp;
  final String tokenSummary;
  final String tokenLabel;
  final GithubTokenStrings tokenDialog;
  final String tokenTooltip;

  static String _installed(String version) => 'Installed: $version';
  static String _newest(String release) => 'Newest: $release';
  static String _downloading(int? percent) =>
      percent == null ? 'Downloading…' : 'Downloading… $percent%';
}

/// The row at the bottom of About: opens [OtherAppsPage].
class OtherAppsLink extends StatelessWidget {
  const OtherAppsLink({
    super.key,
    required this.controller,
    this.strings = const OtherAppsStrings(),
  });

  final OtherAppsController controller;
  final OtherAppsStrings strings;

  @override
  Widget build(BuildContext context) => ListTile(
        key: const Key('otherApps.link'),
        leading: const Icon(Icons.apps),
        title: Text(strings.title),
        subtitle: Text(strings.linkSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                OtherAppsPage(controller: controller, strings: strings),
          ),
        ),
      );
}

/// Every other Mfficiency app: installed or not, its newest release, and
/// Install / Update / Open. Pull down asks GitHub again.
class OtherAppsPage extends StatefulWidget {
  const OtherAppsPage({
    super.key,
    required this.controller,
    this.strings = const OtherAppsStrings(),
  });

  final OtherAppsController controller;
  final OtherAppsStrings strings;

  @override
  State<OtherAppsPage> createState() => _OtherAppsPageState();
}

class _OtherAppsPageState extends State<OtherAppsPage>
    with WidgetsBindingObserver {
  OtherAppsController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(c.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android's installer: show what is installed now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(c.refreshInstalled());
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<OtherAppAction> Function() action) async {
    final s = widget.strings;
    final done = await action();
    if (!mounted) return;
    switch (done) {
      case OtherAppAction.installing:
        _say(s.installing);
      case OtherAppAction.needsPermission:
        _say(s.needsPermission);
      case OtherAppAction.failed:
        _say(s.actionFailed);
      case OtherAppAction.openedInBrowser || OtherAppAction.opened:
        break;
    }
  }

  Future<void> _editToken() async {
    final before = await c.ownToken();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => GithubTokenDialog(
        title: widget.strings.tokenTitle,
        label: widget.strings.tokenLabel,
        summary: widget.strings.tokenSummary,
        help: widget.strings.tokenHelp,
        readToken: c.ownToken,
        writeToken: c.setToken,
        openUrl: c.platform.openUrl,
        fieldKey: const Key('otherApps.token'),
        strings: widget.strings.tokenDialog,
      ),
    );
    if (await c.ownToken() != before) await c.load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          IconButton(
            tooltip: s.tokenTooltip,
            icon: const Icon(Icons.key_outlined),
            onPressed: _editToken,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => RefreshIndicator(
          onRefresh: () => c.load(force: true),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  s.intro,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final app in c.apps)
                _AppCard(
                  app: app,
                  state: c.stateOf(app),
                  strings: s,
                  onInstall: () => _run(() => c.install(app)),
                  onOpen: () => _run(() => c.open(app)),
                  onBrowse: () => _run(() => c.browse(app)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.state,
    required this.strings,
    required this.onInstall,
    required this.onOpen,
    required this.onBrowse,
  });

  final MfficiencyApp app;
  final OtherAppState state;
  final OtherAppsStrings strings;
  final VoidCallback onInstall;
  final VoidCallback onOpen;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final installed = state.installed;
    final release = state.release;
    final lines = <String>[
      installed == null
          ? s.notInstalled
          : s.installed('${installed.version} (${installed.build})'),
      switch (state.status) {
        OtherAppStatus.loading => s.checking,
        OtherAppStatus.noRelease => s.noRelease,
        OtherAppStatus.needsToken => s.needsToken,
        OtherAppStatus.failed => s.failed,
        OtherAppStatus.ready => s.newest(release!.label),
      },
      if (state.downloading)
        s.downloading(
          state.progress == null ? null : (state.progress! * 100).round(),
        ),
    ];
    final canDownload = state.status == OtherAppStatus.ready &&
        release?.apkUrl != null &&
        (installed == null || state.hasUpdate);
    final buttons = <Widget>[
      if (canDownload)
        FilledButton(
          key: Key('otherApps.install.${app.appId}'),
          onPressed: state.downloading ? null : onInstall,
          child: Text(installed == null ? s.install : s.update),
        ),
      if (installed != null)
        OutlinedButton(
          key: Key('otherApps.open.${app.appId}'),
          onPressed: onOpen,
          child: Text(s.open),
        ),
      if (!canDownload && installed == null ||
          state.status == OtherAppStatus.needsToken)
        TextButton(
          key: Key('otherApps.github.${app.appId}'),
          onPressed: onBrowse,
          child: Text(s.onGithub),
        ),
    ];
    return Card(
      key: Key('otherApps.app.${app.appId}'),
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(app.icon, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(app.description),
                      const SizedBox(height: 6),
                      for (final line in lines) Text(line, style: muted),
                    ],
                  ),
                ),
              ],
            ),
            if (state.downloading)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: state.progress),
              ),
            if (buttons.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: buttons),
              ),
          ],
        ),
      ),
    );
  }
}
