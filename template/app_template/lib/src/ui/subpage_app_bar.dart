import 'package:flutter/material.dart';

/// Consistent app bar for every subpage: a back button that returns to the
/// main menu, the page title, and optional actions. Using one helper keeps
/// navigation and spacing identical across the app.
AppBar buildSubpageAppBar(
  BuildContext context, {
  required String title,
  PreferredSizeWidget? bottom,
  List<Widget>? actions,
}) {
  return AppBar(
    leading: IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Back',
      onPressed: () => Navigator.of(context).maybePop(),
    ),
    title: Text(title),
    actions: actions,
    bottom: bottom,
  );
}
