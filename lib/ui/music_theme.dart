import 'package:flutter/material.dart';

import '../config.dart';

/// Best Music's colours: the same blue BestToDo uses (`_seedColor` in
/// `main.dart`), so the two apps look like siblings.
const Color musicSeedColor = Color(0xFF005FDD);

ThemeData buildMusicTheme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: musicSeedColor,
        brightness: brightness,
      ).copyWith(primary: musicSeedColor),
      useMaterial3: true,
    );

/// Live dark-mode switch for Best Music: `BestMusicApp` rebuilds its theme
/// when this changes, Settings → Appearance flips it (and persists
/// [Config.darkMode]).
class MusicTheme {
  MusicTheme._();

  static final ValueNotifier<bool> darkMode = ValueNotifier(Config.darkMode);

  static Future<void> setDarkMode(bool value) async {
    Config.darkMode = value;
    darkMode.value = value;
    await Config.save();
  }
}
