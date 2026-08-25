import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../main.dart';
import '../services/update_service.dart';
import 'subpage_app_bar.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key, this.autoCheckForUpdate = false})
      : super(key: key);

  /// When true, the update section runs its check as soon as this page
  /// opens instead of waiting for a tap — used when the auto-update prompt
  /// (Settings → Updates) has already been confirmed, so the user lands
  /// straight on the available build instead of an extra "Check for
  /// updates" tap.
  final bool autoCheckForUpdate;

  @override
  Widget build(BuildContext context) {
    final mode = Config.isDev ? 'Development' : 'Production';
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'About'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FutureBuilder<void>(
                future: Config.ensureVersionLoaded(),
                builder: (context, snapshot) {
                  return Text(
                    'BestToDo v${Config.versionWithBuild}\nRunning in $mode mode',
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'BestToDo is a lightweight, privacy-focused task manager designed to help you stay productive without the clutter.\n'
                'It emphasizes:\n\n'
                '- Speed: launches in under a second.\n'
                '- Minimal interactions: built for the fewest clicks possible.\n'
                '- Privacy first: no ads, no tracking, no data collection.\n'
                '- Open source: transparent code you can trust.\n\n'
                'With simple swipes you can reschedule tasks for tomorrow, next week, or later. Notes and labels help keep things organized while keeping the interface clean and intuitive.\n\n'
                'BestToDo is a product of Mfficiency, created to make everyday productivity tools faster, leaner, and user-controlled.',
                textAlign: TextAlign.left,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  MyApp.of(context)?.restartIntro();
                },
                icon: const Icon(Icons.replay),
                label: const Text('Replay Introduction'),
              ),
              const SizedBox(height: 8),
              Text(
                'Shows the welcome slides again, ending with the simple/full '
                'mode choice.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _UpdateSection(autoCheck: autoCheckForUpdate),
            ],
          ),
        ),
      ),
    );
  }
}

enum _UpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  readyToInstall,
  error,
}

/// "Check for updates" → the two APKs kept in the repo's `github_releases/`
/// folder → download one with a progress bar → hand it to the Android
/// installer. The main button takes the newest build; a second button reinstalls
/// the one kept for a rollback. On web/desktop (or a release without an APK
/// asset) the buttons open the download page in the browser instead.
class _UpdateSection extends StatefulWidget {
  const _UpdateSection({this.autoCheck = false});

  /// Runs [_UpdateSectionState._check] right away instead of waiting for the
  /// "Check for updates" tap.
  final bool autoCheck;

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  UpdateCheck? _result;

  @override
  void initState() {
    super.initState();
    if (widget.autoCheck) unawaited(_check());
  }

  /// The build currently being downloaded/installed — the newest one, or the
  /// rollback build when that button was tapped.
  UpdateInfo? _target;
  String? _apkPath;
  String _note = '';
  int _received = 0;
  int? _total;

  bool _installsInPlace(UpdateInfo? info) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      info?.apkUrl != null;

  Future<void> _check() async {
    setState(() {
      _phase = _UpdatePhase.checking;
      _note = '';
    });
    try {
      final result = await UpdateService.instance.checkReleases();
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase =
            result.hasUpdate ? _UpdatePhase.available : _UpdatePhase.upToDate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _note = 'Update check failed: $e';
      });
    }
  }

  Future<void> _downloadAndInstall(UpdateInfo? info,
      {bool rollback = false}) async {
    if (info == null) return;
    if (!_installsInPlace(info)) {
      await launchUrl(Uri.parse(info.htmlUrl),
          mode: LaunchMode.externalApplication);
      return;
    }
    _target = info;
    setState(() {
      _phase = _UpdatePhase.downloading;
      _received = 0;
      _total = info.apkSizeBytes;
      // Android's package installer refuses to replace an app with an older
      // build, so say so up front rather than leaving the user with a bare
      // "App not installed" from the system UI.
      _note = rollback
          ? 'Going back to ${info.version}. Android blocks downgrades: if the '
              'install is refused, uninstall the current version first — that '
              'clears the app\'s data, so export a backup before you do.'
          : '';
    });
    try {
      final file = await UpdateService.instance.downloadApk(
        info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total ?? _total;
          });
        },
      );
      if (!mounted) return;
      _apkPath = file.path;
      setState(() => _phase = _UpdatePhase.readyToInstall);
      await _install();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _note = 'Download failed: $e';
      });
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null) return;
    try {
      final result = await UpdateService.instance.installApk(path);
      if (!mounted) return;
      if (result == 'needs-permission') {
        setState(() {
          _note = 'Allow installs from BestToDo in the settings screen that '
              'just opened, then tap Install again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = 'Install failed: $e');
    }
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return ' (${mb.toStringAsFixed(1)} MB)';
  }

  /// "Go back to x.y.z+b" — offered whenever the repo folder still keeps a
  /// build other than the running one, both when an update is available and
  /// when the app is already up to date.
  List<Widget> _rollbackControls(BuildContext context, UpdateInfo previous) {
    return [
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => _downloadAndInstall(previous, rollback: true),
        icon: const Icon(Icons.settings_backup_restore),
        label: Text(_installsInPlace(previous)
            ? 'Go back to ${previous.version}${_sizeLabel(previous.apkSizeBytes)}'
            : 'Open previous version'),
      ),
      const SizedBox(height: 4),
      Text(
        'Reinstalls the previous build, the oldest one the repo still keeps.',
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final info = result?.latest;
    final previous = result?.rollback;
    final children = <Widget>[];

    switch (_phase) {
      case _UpdatePhase.idle:
      case _UpdatePhase.checking:
        break;
      case _UpdatePhase.upToDate:
        children.add(Text(
          'You are on the latest version (v${Config.versionWithBuild}).',
          textAlign: TextAlign.center,
        ));
        if (previous != null) {
          children.addAll(_rollbackControls(context, previous));
        }
      case _UpdatePhase.available:
        children.add(Text(
          'Version ${info?.version} is available.',
          textAlign: TextAlign.center,
        ));
        children.add(const SizedBox(height: 8));
        children.add(ElevatedButton.icon(
          onPressed: () => _downloadAndInstall(info),
          icon: const Icon(Icons.download),
          label: Text(_installsInPlace(info)
              ? 'Download & install${_sizeLabel(info?.apkSizeBytes)}'
              : 'Open release page'),
        ));
        if (previous != null) {
          children.addAll(_rollbackControls(context, previous));
        }
      case _UpdatePhase.downloading:
        final total = _total;
        final progress = (total != null && total > 0) ? _received / total : null;
        children.add(Text(
          total != null && total > 0
              ? 'Downloading… ${((_received / total) * 100).toStringAsFixed(0)}%'
              : 'Downloading…',
          textAlign: TextAlign.center,
        ));
        children.add(const SizedBox(height: 8));
        children.add(LinearProgressIndicator(value: progress));
      case _UpdatePhase.readyToInstall:
        children.add(Text(
          'Version ${_target?.version} downloaded.',
          textAlign: TextAlign.center,
        ));
        children.add(const SizedBox(height: 8));
        children.add(ElevatedButton.icon(
          onPressed: _install,
          icon: const Icon(Icons.install_mobile),
          label: const Text('Install update'),
        ));
      case _UpdatePhase.error:
        children.add(Text(
          _note,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ));
    }

    if (_note.isNotEmpty && _phase != _UpdatePhase.error) {
      children.add(const SizedBox(height: 8));
      children.add(Text(_note, textAlign: TextAlign.center));
    }

    final busy =
        _phase == _UpdatePhase.checking || _phase == _UpdatePhase.downloading;
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: busy ? null : _check,
          icon: _phase == _UpdatePhase.checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update),
          label: const Text('Check for updates'),
        ),
        const SizedBox(height: 8),
        Text(
          'Updates come straight from the app\'s GitHub repo, which keeps the '
          'last two builds — no store needed.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (children.isNotEmpty) const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}
