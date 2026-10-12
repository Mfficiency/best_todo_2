import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../main.dart';
import '../services/update_service.dart';
import 'auto_update_dialog.dart';
import 'subpage_app_bar.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

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
                    'BestToDo v${Config.versionWithChannel}\nRunning in $mode mode',
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
              const UpdateSection(),
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
  error,
}

/// "Check for updates" → this app's builds on GitHub (any channel) → the
/// newest one, or one version back. Download & install / Go back to
/// download **silently** in the background (one SnackBar says so, a line of
/// passive text follows it here); once the APK is complete Android's own
/// "Update this app?" is the only confirmation — through the running app's
/// [AutoUpdateFlow] when there is one. On web/desktop (or a release without
/// an APK asset) the buttons open the download page in the browser instead.
///
/// [service] defaults to [UpdateService.instance] (BestToDo's own updates);
/// Best Music's [MusicAboutPage] passes its own [UpdateService.forApp]
/// instance instead, with [appName] to match — see
/// [UpdateService.checkReleases]'s doc comment for why the two apps need
/// separate instances rather than sharing the default one.
class UpdateSection extends StatefulWidget {
  const UpdateSection({super.key, this.service, this.appName = 'BestToDo'});

  final UpdateService? service;
  final String appName;

  @override
  State<UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<UpdateSection> {
  UpdateService get _service => widget.service ?? UpdateService.instance;
  _UpdatePhase _phase = _UpdatePhase.idle;
  UpdateCheck? _result;
  String _note = '';

  /// The download this page started itself when no [AutoUpdateFlow] runs
  /// for [_service] (tests, an app without one).
  final ValueNotifier<UpdateDownload?> _localDownload = ValueNotifier(null);

  /// The running app's automatic update, when it is about [_service].
  AutoUpdateFlow? get _flow {
    final flow = AutoUpdateFlow.current;
    return flow != null && identical(flow.service, _service) ? flow : null;
  }

  ValueListenable<UpdateDownload?> get _downloads =>
      _flow?.downloading ?? _localDownload;

  @override
  void dispose() {
    _localDownload.dispose();
    super.dispose();
  }

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
      final result = await _service.checkReleases();
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

  /// Downloads [info] silently in the background — no progress dialog, no
  /// notification, one SnackBar — and opens Android's install confirm once
  /// it is complete.
  Future<void> _downloadAndInstall(UpdateInfo? info,
      {bool rollback = false}) async {
    if (info == null) return;
    if (!_installsInPlace(info)) {
      await launchUrl(Uri.parse(info.htmlUrl),
          mode: LaunchMode.externalApplication);
      return;
    }
    setState(() {
      // Android's package installer refuses to replace an app with an older
      // build, so say so up front rather than leaving the user with a bare
      // "App not installed" from the system UI.
      _note = rollback
          ? 'Going back to ${info.version}. Android blocks downgrades: if the '
              'install is refused, uninstall the current version first — that '
              'clears the app\'s data, so export a backup before you do.'
          : '';
    });
    final flow = _flow;
    if (flow != null) {
      await flow.install(info);
      return;
    }
    if (_localDownload.value?.version == info.version) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(updateDownloadingSnack)));
    _localDownload.value =
        (version: info.version, received: 0, total: info.apkSizeBytes);
    try {
      // Handed off to Android's DownloadManager (see UpdateService), so the
      // transfer keeps going even if this page — or the app — is backgrounded,
      // and rides out a Wi-Fi/mobile handover mid-download.
      await for (final progress in _service.downloadInBackground(info)) {
        if (!mounted) return;
        if (progress.status == DownloadStatus.failed) {
          setState(() {
            _phase = _UpdatePhase.error;
            _note = 'Download failed${progress.reason != null ? ' (${progress.reason})' : ''}';
          });
          return;
        }
        if (progress.status == DownloadStatus.successful) {
          _localDownload.value = null;
          final path = progress.localPath;
          if (path != null) await _install(path);
        } else {
          _localDownload.value = (
            version: info.version,
            received: progress.bytesDownloaded,
            total: progress.bytesTotal ?? info.apkSizeBytes,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _note = 'Download failed: $e';
      });
    } finally {
      if (mounted) _localDownload.value = null;
    }
  }

  Future<void> _install(String path) async {
    try {
      final result = await _service.installApk(path);
      if (!mounted) return;
      if (result == 'needs-permission') {
        setState(() {
          _note = 'Allow installs from ${widget.appName} in the settings '
              'screen that just opened, then tap Install again.';
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

    final busy = _phase == _UpdatePhase.checking;
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
        // A running download: passive text only, nothing pops up.
        ValueListenableBuilder<UpdateDownload?>(
          valueListenable: _downloads,
          builder: (context, download, _) {
            if (download == null) return const SizedBox.shrink();
            final percent = updateDownloadPercent(download);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Downloading ${download.version} in the background'
                '${percent == null ? '…' : '… $percent'}\n'
                "You'll be asked to install it when it's ready.",
                key: const Key('about.update.downloading'),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ],
    );
  }
}
