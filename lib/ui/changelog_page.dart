import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import '../l10n/app_localizations.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({Key? key}) : super(key: key);

  Future<String> _loadChangelog() async {
    return rootBundle.loadString('CHANGELOG.md');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.changelog)),
      body: FutureBuilder<String>(
        future: _loadChangelog(),
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
