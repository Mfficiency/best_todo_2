import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../services/log_service.dart';
import '../services/pre_update_backup.dart';
import 'changelog_page.dart';

/// Compares dotted versions numerically (`0.2.10` > `0.2.9`); build
/// suffixes (`+445`) and pre-release tags are ignored.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
        for (final p in v.split('+').first.split('-').first.split('.'))
          int.tryParse(p) ?? 0,
      ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Releases newer than [previous], up to and including [current], newest
/// first (as CHANGELOG.md lists them), without the build-time notes.
List<ChangelogRelease> releasesSince(
  List<ChangelogRelease> all,
  String previous,
  String current,
) =>
    [
      for (final r in all)
        if (RegExp(r'^\d').hasMatch(r.version) &&
            compareVersions(r.version, previous) > 0 &&
            compareVersions(r.version, current) <= 0)
          ChangelogRelease(
            version: r.version,
            date: r.date,
            entries: r.entries.where((e) => !isChangelogBuildNote(e)).toList(),
          ),
    ];

/// What's new after an update: the first start of a new version shows,
/// once, a sheet with the changelog entries since the version the user had
/// before. Settings → Releases → What's new after an update turns it off
/// ([Config.whatsNewEnabled], on by default). A fresh install shows nothing.
class WhatsNew {
  WhatsNew._();

  /// The version that last ran (and so last had its what's new handled).
  static const String lastVersionKey = 'whats_new.last_version';

  static Future<List<ChangelogRelease>>? _pending;

  /// Works out (once per run, right after the first frame) what to show,
  /// and records the running version so it shows only once.
  static Future<List<ChangelogRelease>> prepare({
    SharedPreferences? prefs,
    String? current,
    Future<String> Function()? loadChangelog,
    Future<String?> Function()? legacyVersion,
  }) =>
      _pending ??= _compute(prefs, current, loadChangelog, legacyVersion);

  /// Shows the sheet if [prepare] found something, once per run.
  static Future<void> show(BuildContext context) async {
    final pending = _pending ??= prepare();
    final releases = await pending;
    _pending = Future.value(const []);
    if (releases.isEmpty || !context.mounted) return;
    LogService.add('updates', "What's new: ${releases.length} release(s)");
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => WhatsNewSheet(releases: releases),
    );
  }

  static void resetForTest() => _pending = null;

  static Future<List<ChangelogRelease>> _compute(
    SharedPreferences? prefs,
    String? current,
    Future<String> Function()? loadChangelog,
    Future<String?> Function()? legacyVersion,
  ) async {
    try {
      if (current == null) {
        await Config.ensureVersionLoaded();
        current = Config.version;
      }
      if (current == 'unknown') return const [];
      prefs ??= await SharedPreferences.getInstance();
      // Installs from before this sheet: the version marker the data
      // files keep (written a few seconds after the first frame, so still
      // the old version here).
      final previous = prefs.getString(lastVersionKey) ??
          await (legacyVersion ?? _legacyVersion)();
      await prefs.setString(lastVersionKey, current);
      if (!Config.whatsNewEnabled ||
          previous == null ||
          compareVersions(previous, current) >= 0) {
        return const [];
      }
      final markdown = await (loadChangelog ??
          () => rootBundle.loadString('CHANGELOG.md'))();
      return releasesSince(parseChangelogReleases(markdown), previous, current)
          .where((r) => r.entries.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> _legacyVersion() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${PreUpdateBackup.versionFileName}');
      if (!await file.exists()) return null;
      final v = (await file.readAsString()).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }
}

/// The sheet [WhatsNew.show] opens.
class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key, required this.releases});
  final List<ChangelogRelease> releases;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Text(
            "What's new",
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Updated to version ${releases.first.version}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          for (final r in releases) ...[
            const SizedBox(height: 20),
            Text(
              r.version,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            for (final entry in r.entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: MarkdownBody(data: entry)),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(
                      MaterialPageRoute(builder: (_) => const ChangelogPage()));
                },
                child: const Text('Full changelog'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
