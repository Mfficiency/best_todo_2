import 'package:flutter/material.dart';

/// Keeps every screen, bottom sheet, dialog and SnackBar clear of Android's
/// navigation bar (gesture handle or 3-button bar, bottom or side).
///
/// Android 15 draws apps edge to edge, so the navigation bar sits on top of
/// the app's bottom edge. Wrapped once around the navigator
/// (`MaterialApp.builder`), this measures the bar Android reports
/// (`MediaQuery.padding`: none, the slim gesture handle or the taller
/// buttons; on the side in landscape) and moves the whole app out of its way.
/// Nothing below the navigator can end up behind it, including routes added
/// later. The strip behind the bar gets the page background. The status bar
/// stays with the app bars (`top: false`), and while the keyboard is open the
/// bar's padding is 0, so pages still resize for the keyboard as before.
class SystemBarSafeArea extends StatelessWidget {
  const SystemBarSafeArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(top: false, child: child),
  );
}
