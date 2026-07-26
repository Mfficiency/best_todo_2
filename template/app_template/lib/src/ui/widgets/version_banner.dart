import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../util/app_version.dart';

/// App title + current version, shown at the top of the main menu and reused on
/// the About page. The version is resolved at runtime via [AppVersion] — never
/// hard-coded — so it always matches the installed build.
class VersionBanner extends StatelessWidget {
  /// When true, also shows the tagline and the Dev/Production mode line.
  final bool detailed;

  const VersionBanner({super.key, this.detailed = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = AppVersion.isDev ? 'Development' : 'Production';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          AppConfig.appName,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        if (detailed) ...[
          const SizedBox(height: 4),
          Text(
            AppConfig.tagline,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 4),
        // A single FutureBuilder keeps the version text correct even before
        // AppVersion has finished loading (it shows "unknown" then updates).
        FutureBuilder<void>(
          future: AppVersion.ensureLoaded(),
          builder: (context, _) => Text(
            detailed
                ? 'v${AppVersion.versionWithBuild}  ·  $mode'
                : 'v${AppVersion.versionWithBuild}',
            key: const Key('version-text'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
