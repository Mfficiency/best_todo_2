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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'BestToDo v${Config.version}\nRunning in $mode mode',
              textAlign: TextAlign.center,
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
    );
  }
}
