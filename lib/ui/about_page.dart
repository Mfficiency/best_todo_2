import 'package:flutter/material.dart';
import '../config.dart';
import '../main.dart';
import '../services/app_updates.dart';
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

/// "Check for updates" on the About page (BestToDo's and Best Music's), on
/// the running app's [AppUpdates.controller] (the shared updates package):
/// a tap checks GitHub (this app's builds of every channel, the highest
/// build wins); a newer build downloads **silently** in the background (one
/// SnackBar says so, the tile's subtitle shows the progress) and Android's
/// own "Update this app?" is the only confirm once it is complete. "Go back
/// to an older version" opens the package's version sheet for the highest
/// x.y.z below the running one (the same as tapping a version in the
/// Changelog). Nothing without a controller (tests that don't set one).
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key, this.controller});

  /// Defaults to the running app's [AppUpdates.controller].
  final UpdateController? controller;

  Future<void> _olderVersion(BuildContext context, UpdateController c) async {
    final versions = await c.releasesByVersionList();
    if (!context.mounted) return;
    final running = c.config.version;
    final older = versions.keys
        .where((v) => compareVersions(v, running) < 0)
        .toList()
      ..sort(compareVersions);
    if (older.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('No older version is available to download.')));
      return;
    }
    await c.onVersionTap(context, older.last);
  }

  @override
  Widget build(BuildContext context) {
    final c = controller ?? AppUpdates.controller;
    if (c == null) return const SizedBox.shrink();
    return Card(
      key: const Key('about.updates'),
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          UpdateCheckTile(controller: c),
          ListTile(
            key: const Key('about.update.older'),
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Go back to an older version'),
            subtitle: const Text('Or tap a version in the Changelog'),
            onTap: () => _olderVersion(context, c),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              "Updates come straight from the app's GitHub releases — no "
              'store needed. They download quietly in the background; '
              'Android then asks once whether to install.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
