import 'package:flutter/material.dart';
import '../config.dart';
import '../l10n/app_localizations.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mode = Config.isDev ? l10n.development : l10n.production;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: Center(
        child: Text(
          l10n.aboutBody(Config.version, mode),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
