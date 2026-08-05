import 'package:flutter/material.dart';

import 'mode_select_page.dart';

/// The welcome flow: three slides about what the app is, then the simple/full
/// mode question as the closing page. Shown on a first launch and replayable
/// from About → "Replay introduction"; [onFinished] runs once a mode is picked.
class IntroPage extends StatefulWidget {
  final VoidCallback onFinished;
  const IntroPage({super.key, required this.onFinished});

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  /// Number of slides before the mode chooser, which is always the last page.
  static const int _slideCount = 3;
  static const int _pageCount = _slideCount + 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _nextPage() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildPage(String title, String body, IconData icon) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onLastPage = _currentIndex == _pageCount - 1;
    final pages = [
      _buildPage(
        'Privacy First',
        'F*ck big tech, No ads, No tracking!',
        Icons.lock,
      ),
      _buildPage(
        'Open Source & Fast',
        'Transparent code and boots in under one second!',
        Icons.speed,
      ),
      _buildPage(
        'Minimal Interactions',
        'Designed for the fewest clicks possible!',
        Icons.touch_app,
      ),
      SafeArea(
        bottom: false,
        child: ModeSelectView(onModeSelected: widget.onFinished),
      ),
    ];

    return Scaffold(
      body: PageView(
        controller: _controller,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: pages,
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: List.generate(pages.length, (index) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentIndex == index
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                );
              }),
            ),
            // The last page ends the intro by picking a mode, so it gets a
            // nudge instead of a button that could skip the question.
            if (onLastPage)
              Text(
                'Pick a mode to start',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              TextButton(
                onPressed: _nextPage,
                child: Text(
                  _currentIndex == _slideCount - 1 ? 'Get Started' : 'Next',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
