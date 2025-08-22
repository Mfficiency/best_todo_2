import 'package:flutter/material.dart';
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
          ],
        ),
      ),
    );
  }
}
