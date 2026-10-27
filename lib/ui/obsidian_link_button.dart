import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Open in Obsidian" for an item whose page the voice-inbox routine wrote
/// into the vault ([Task.obsidianLink], an `obsidian://open?…` link sent back
/// through Todoist). Compact, so it fits under a tile's title.
class ObsidianLinkButton extends StatelessWidget {
  final String link;

  const ObsidianLinkButton({Key? key, required this.link}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.description_outlined, size: 16),
      label: const Text('Open in Obsidian'),
      onPressed: () {
        final uri = Uri.tryParse(link);
        if (uri == null) return;
        launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }
}
