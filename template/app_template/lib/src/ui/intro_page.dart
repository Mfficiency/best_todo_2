import 'package:flutter/material.dart';

import '../app_config.dart';
import 'widgets/spacing.dart';

/// First-run introduction carousel. Slides come from [AppConfig.introSlides];
/// [onFinished] is called when the user reaches the end. Reachable again via
/// About → "Replay introduction".
class IntroPage extends StatefulWidget {
  final VoidCallback onFinished;
  const IntroPage({super.key, required this.onFinished});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  int get _lastIndex => AppConfig.introSlides.length - 1;

  void _next() {
    if (_currentIndex < _lastIndex) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onFinished();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = AppConfig.introSlides;
    final theme = Theme.of(context);
    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: [
          for (final slide in slides)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(slide.icon, size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: AppSpacing.xl),
                  Text(slide.title,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.lg),
                  Text(slide.body,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: List.generate(slides.length, (i) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentIndex == i
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                );
              }),
            ),
            TextButton(
              onPressed: _next,
              child: Text(_currentIndex == _lastIndex ? 'Get Started' : 'Next'),
            ),
          ],
        ),
      ),
    );
  }
}
