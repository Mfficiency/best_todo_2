import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../app_config.dart';
import 'subpage_app_bar.dart';
import 'widgets/spacing.dart';
import 'widgets/version_banner.dart';

/// App details, dynamic version, "Replay introduction" and "Update app". All
/// copy and links come from [AppConfig].
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'About'),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const VersionBanner(detailed: true),
              const SizedBox(height: AppSpacing.xl),
              const Text(AppConfig.aboutText, textAlign: TextAlign.left),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: () => TemplateApp.of(context)?.replayIntro(),
                child: const Text('Replay Introduction'),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: () async {
                  final uri = Uri.parse(AppConfig.updateUrl);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text('Update App'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
