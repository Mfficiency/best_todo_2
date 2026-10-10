import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';

import 'subpage_app_bar.dart';

/// Renders the bundled `CHANGELOG.md` (newest version first — keep the file
/// ordered that way; `tool/bump_version.dart` prepends new entries for you).
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  Future<String> _load() => rootBundle.loadString('CHANGELOG.md');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Changelog'),
      body: FutureBuilder<String>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Markdown(data: snapshot.data!);
        },
      ),
    );
  }
}
