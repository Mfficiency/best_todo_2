import 'package:flutter/material.dart';
import 'ui/home_page.dart';
import 'config.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  void updateTheme() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Best Todo 2',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.green,
        textTheme: ThemeData.light()
            .textTheme
            .apply(bodyColor: Colors.red, displayColor: Colors.red),
      ),
      darkTheme: ThemeData.dark(),
      themeMode: Config.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomePage(),
    );
  }
}
