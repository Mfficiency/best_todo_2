import 'package:flutter/material.dart';

import 'controller.dart';
import 'release.dart';
import 'strings.dart';

/// The slim banner above the app's screens. Nothing while an update
/// downloads. Once complete and Android's dialog was cancelled: "Update
/// ready · 1.2.0 (5)" with Install, until installed. A failed download: Try
/// again (silent again). Without the background download (automatic checks
/// off, a release without an APK): the update is available, Later or
/// Install. Otherwise an empty box.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.controller});
  final UpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final s = c.stringsOf(context);
          final done = c.readyUpdate;
          if (done != null &&
              done.key == c.ready.value &&
              c.readyApk(done) != null) {
            return _banner(s.readyBanner(done.label), [
              TextButton(
                key: const Key('update.banner.install'),
                onPressed: () => c.install(context, done),
                child: Text(s.install),
              ),
            ]);
          }
          if (c.downloading.value) return const SizedBox.shrink();
          final failed = c.failed.value;
          if (failed != null) {
            return _banner(s.downloadFailedBanner(failed.label), [
              TextButton(
                key: const Key('update.banner.retry'),
                onPressed: () => c.install(context, failed),
                child: Text(s.retry),
              ),
            ]);
          }
          final r = c.result.value;
          if (r == null || !c.showsAvailableBanner(r)) {
            return const SizedBox.shrink();
          }
          return _banner(s.availableBanner(r.label), [
            TextButton(onPressed: () => c.dismiss(r), child: Text(s.later)),
            TextButton(
              key: const Key('update.banner.install'),
              onPressed: () => c.install(context, r),
              child: Text(s.install),
            ),
          ]);
        },
      );

  static Widget _banner(String text, List<Widget> actions) => MaterialBanner(
        leading: const Icon(Icons.system_update_outlined),
        content: Text(text),
        actions: actions,
      );
}

/// The changelog's header card: version and channel on top ("Version
/// 1.2.0 (5) · main"), a status line only when there is news (checking, an
/// update, a problem), then the times in two aligned columns (Downloaded,
/// Installed, Last check), a newer build downloaded and ready (or its
/// download progress), and Install when an update is there.
class UpdateStatusCard extends StatelessWidget {
  const UpdateStatusCard({super.key, required this.controller});
  final UpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final c = controller;
          final s = c.stringsOf(context);
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          final r = c.result.value;
          final last = c.lastCheck;
          final available = r?.status == UpdateStatus.available;
          final config = c.config;
          final version = s.versionTitle(
            '${config.version} (${config.build}) · ${config.channel}',
          );
          final label = c.statusLabel(s, r);
          final status = c.checking.value
              ? s.checking
              : label == s.upToDate
                  ? null
                  : label;
          final d = c.downloaded.value;
          final installed = c.installedAt.value;
          // When the running build was downloaded and installed, and when
          // the last check ran.
          final rows = [
            if (d != null && c.isRunning(d.key))
              (s.downloadedLabel, s.dateTime(d.at)),
            if (installed != null) (s.installedLabel, s.dateTime(installed)),
            (s.lastCheckLabel, last == null ? s.neverChecked : s.dateTime(last)),
          ];
          // A newer build that is downloaded and waiting.
          final waiting =
              available && r!.key == c.ready.value && d?.key == r.key
                  ? s.downloadedReady(d!.label, s.dateTime(d.at))
                  : c.progressLabel(s);
          final muted = theme.textTheme.bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant);
          return Card(
            color: available ? scheme.primaryContainer : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(version,
                            style: theme.textTheme.titleMedium),
                      ),
                      if (available)
                        FilledButton(
                          onPressed: () => c.install(context, r!),
                          child: Text(s.install),
                        ),
                    ],
                  ),
                  if (status != null) Text(status, style: muted),
                  const SizedBox(height: 8),
                  Table(
                    columnWidths: const {
                      0: IntrinsicColumnWidth(),
                      1: FlexColumnWidth(),
                    },
                    children: [
                      for (final (name, time) in rows)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: Text(name, style: muted),
                            ),
                            Text(time, style: muted),
                          ],
                        ),
                    ],
                  ),
                  if (waiting != null) ...[
                    const SizedBox(height: 8),
                    Text(waiting, style: muted),
                  ],
                ],
              ),
            ),
          );
        },
      );
}

/// A version's build facts for its changelog entry, read from its GitHub
/// release (the highest build of that x.y.z): when it was built, how long
/// the build took and the APK's size, as small chips ("Built 15.10.2026
/// 14:02", "Build time 3m 12s", "APK 19.4 MB"). [fallback] (e.g. the
/// build lines of the app's CHANGELOG.md) while the releases load or when
/// the release says nothing; else an empty box. The release list is read
/// once ([UpdateController.releasesByVersionList]) and again on pull-down.
class ReleaseBuildInfo extends StatelessWidget {
  const ReleaseBuildInfo({
    super.key,
    required this.controller,
    required this.version,
    this.fallback,
    this.padding = const EdgeInsets.only(top: 12),
  });
  final UpdateController controller;

  /// x.y.z as in the changelog heading.
  final String version;
  final Widget? fallback;

  /// Around the chips (not around [fallback]).
  final EdgeInsetsGeometry padding;

  /// The facts as (icon, text), empty when the release says nothing.
  static List<(IconData, String)> facts(UpdateStrings s, UpdateResult? r) => [
        if (r?.builtAt case final at?)
          (Icons.build_outlined, s.releaseBuilt(s.dateTime(at))),
        if (r?.buildDuration case final d?)
          (Icons.timer_outlined, s.releaseBuildTime(formatBuildDuration(d))),
        if (r?.apkSize case final size?)
          (Icons.sd_storage_outlined, s.releaseApkSize(formatApkSize(size))),
      ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => FutureBuilder<Map<String, UpdateResult>>(
          future: controller.releasesByVersionList(),
          builder: (context, snap) {
            final s = controller.stringsOf(context);
            final facts = ReleaseBuildInfo.facts(s, snap.data?[version]);
            if (facts.isEmpty) return fallback ?? const SizedBox.shrink();
            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final style = theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant);
            return Padding(
              padding: padding,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (icon, text) in facts)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Flexible(child: Text(text, style: style)),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
}

/// Title, subtitle and busy state of a "Check for updates" tile, for apps
/// that draw the tile in their own style ([UpdateCheckTile] is the plain
/// one). Rebuild with a ListenableBuilder on the controller.
extension UpdateCheckTileText on UpdateController {
  /// "Check for updates", or "Checking…" while it runs.
  String checkTileTitle(BuildContext context) {
    final s = stringsOf(context);
    return checking.value ? s.checking : s.checkNow;
  }

  /// "Downloading version 1.3.0 (6)… 42 %" while an APK downloads, else
  /// "Current version 1.2.0 (5)".
  String checkTileSubtitle(BuildContext context) {
    final s = stringsOf(context);
    return progressLabel(s) ?? s.currentVersion(config.versionLabel);
  }

  /// "Up to date · Last checked 12.10.2026" (settings search summaries).
  String checkSummary(BuildContext context) {
    final s = stringsOf(context);
    final label = statusLabel(s);
    final last = lastCheck;
    return last == null || !configured
        ? label
        : '$label · ${s.lastChecked(s.date(last))}';
  }
}

/// A plain "Check for updates" ListTile: checks on tap (a newer build
/// downloads silently, then Android asks to install), progress as subtitle.
class UpdateCheckTile extends StatelessWidget {
  const UpdateCheckTile({super.key, required this.controller});
  final UpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final busy = controller.checking.value;
          return ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(controller.checkTileTitle(context)),
            subtitle: Text(controller.checkTileSubtitle(context)),
            trailing: busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: busy ? null : () => controller.checkNow(context),
          );
        },
      );
}

/// The sheet for a version tapped in the changelog: "You are using this
/// version", its download (an older one with the downgrade note), or "no
/// longer available". The download is silent, then Android asks.
Future<void> showUpdateVersionSheet(
  BuildContext context,
  UpdateController controller,
  String version,
) {
  final versions = controller.releasesByVersionList();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // The sheet closes before the download starts: use the page's context.
    builder: (_) => UpdateVersionSheet(
      controller: controller,
      version: version,
      versions: versions,
      onDownload: (release) => controller.install(context, release),
    ),
  );
}

class UpdateVersionSheet extends StatelessWidget {
  const UpdateVersionSheet({
    super.key,
    required this.controller,
    required this.version,
    required this.versions,
    required this.onDownload,
  });

  final UpdateController controller;
  final String version;
  final Future<Map<String, UpdateResult>> versions;
  final void Function(UpdateResult release) onDownload;

  @override
  Widget build(BuildContext context) {
    final s = controller.stringsOf(context);
    final theme = Theme.of(context);
    final running = controller.config.version;
    final older = compareVersions(version, running) < 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: FutureBuilder(
          future: versions,
          builder: (context, snap) {
            final release = snap.data?[version];
            // The running x.y.z, unless there is a newer build of it.
            final current = version == running &&
                (release == null || !controller.isNewer(release));
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.versionTitle(version),
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                if (current)
                  Text(s.versionCurrent)
                else if (!snap.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (release == null)
                  Text(s.versionNotAvailable(version))
                else ...[
                  if (older) ...[
                    Text(
                      s.versionDowngradeNote,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDownload(release);
                    },
                    icon: const Icon(Icons.download),
                    label: Text(s.versionDownload(release.label)),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
