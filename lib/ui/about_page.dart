import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../main.dart';
import '../services/update_service.dart';
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
              const _UpdateSection(),
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

/// "Check for updates" → newest GitHub release → download the APK with a
/// progress bar → hand it to the Android installer. On web/desktop (or a
/// release without an APK asset) the download button opens the release page
/// in the browser instead.
class _UpdateSection extends StatefulWidget {
  const _UpdateSection();

  @override
  State<_UpdateSection> createState() => _UpdateSectionState();
}

class _UpdateSectionState extends State<_UpdateSection> {
  _UpdatePhase _phase = _UpdatePhase.idle;
  UpdateInfo? _update;
  String? _apkPath;
  String _note = '';
  int _received = 0;
  int? _total;

  bool get _installsInPlace =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      _update?.apkUrl != null;

  Future<void> _check() async {
    setState(() {
      _phase = _UpdatePhase.checking;
      _note = '';
    });
    try {
      final info = await UpdateService.instance.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _update = info;
        _phase = info == null ? _UpdatePhase.upToDate : _UpdatePhase.available;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.error;
        _note = 'Update check failed: $e';
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final info = _update;
    if (info == null) return;
    if (!_installsInPlace) {
      await launchUrl(Uri.parse(info.htmlUrl),
          mode: LaunchMode.externalApplication);
      return;
    }
    setState(() {
      _phase = _UpdatePhase.downloading;
      _received = 0;
      _total = info.apkSizeBytes;
      _note = '';
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

  @override
  Widget build(BuildContext context) {
    final info = _update;
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
      case _UpdatePhase.available:
        children.add(Text(
          'Version ${info?.version} is available.',
          textAlign: TextAlign.center,
        ));
        children.add(const SizedBox(height: 8));
        children.add(ElevatedButton.icon(
          onPressed: _downloadAndInstall,
          icon: const Icon(Icons.download),
          label: Text(_installsInPlace
              ? 'Download & install${_sizeLabel(info?.apkSizeBytes)}'
              : 'Open release page'),
        ));
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
          'Version ${info?.version} downloaded.',
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
          'Updates come straight from the app\'s GitHub releases — no store '
          'needed.',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (children.isNotEmpty) const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}
