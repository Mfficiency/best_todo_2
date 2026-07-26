import 'package:flutter/material.dart';

/// One page of the first-run introduction carousel. Configured in
/// [AppConfig.introSlides].
class IntroSlide {
  final IconData icon;
  final String title;
  final String body;

  const IntroSlide({
    required this.icon,
    required this.title,
    required this.body,
  });
}
