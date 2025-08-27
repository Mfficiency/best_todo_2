import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../main.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mode = Config.isDev ? 'Development' : 'Production';
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'BestToDo v${Config.version}\nRunning in $mode mode',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Text(
                'BestToDo is a lightweight, privacy-focused task manager designed to help you stay productive without the clutter.\n'
                'It emphasizes:\n\n'
                'Speed: launches in under a second.\n'
                'Minimal interactions: built for the fewest clicks possible.\n'
                'Privacy first: no ads, no tracking, no data collection.\n'
                'Open source: transparent code you can trust.\n\n'
                'With simple swipes you can reschedule tasks for tomorrow, next week, or later. Notes and labels help keep things organized while keeping the interface clean and intuitive.\n\n'
                'BestToDo is a product of Mfficiency, created to make everyday productivity tools faster, leaner, and user-controlled.',
                textAlign: TextAlign.left,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  MyApp.of(context)?.restartIntro();
                },
                child: const Text('Replay Introduction'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  final uri = Uri.parse('https://play.google.com/store/apps/details?id=com.mfficiency.best_todo_2');
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
