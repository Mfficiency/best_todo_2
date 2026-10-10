import 'package:flutter/material.dart';

import 'spacing.dart';

/// A titled card grouping related settings. Reused by the Settings page for
/// every section so headings, padding and card style stay consistent. The
/// [sectionKey] anchors scroll-to-section jumps.
class SettingsSection extends StatelessWidget {
  final Key? sectionKey;
  final String title;
  final List<Widget> children;

  const SettingsSection({
    super.key,
    this.sectionKey,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: sectionKey,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 14, AppSpacing.lg, AppSpacing.sm),
              child: Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}
