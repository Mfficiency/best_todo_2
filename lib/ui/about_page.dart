import 'package:flutter/material.dart';
import '../config.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mode = Config.isDev ? 'Development' : 'Production';
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Center(
        child: Text(
          'Best Todo 2 v${Config.version}\nRunning in $mode mode',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
