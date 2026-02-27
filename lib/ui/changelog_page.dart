import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'subpage_app_bar.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({Key? key}) : super(key: key);

  Future<String> _loadChangelog() async {
    return rootBundle.loadString('CHANGELOG.md');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Changelog'),
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
