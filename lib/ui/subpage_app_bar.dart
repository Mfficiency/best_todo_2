import 'package:flutter/material.dart';

import 'home_scaffold_key.dart';

AppBar buildSubpageAppBar(
  BuildContext context, {
  required String title,
  PreferredSizeWidget? bottom,
  List<Widget>? actions,
  // False: just the menu button (the system back gesture still works) —
  // Now Playing keeps every other control at the bottom of the screen.
  bool showBack = true,
}) {
  return AppBar(
    automaticallyImplyLeading: false,
    leadingWidth: showBack ? 96 : 56,
    leading: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Menu',
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              homeScaffoldKey.currentState?.openDrawer();
            });
          },
        ),
        if (showBack) IconButton(
          icon: const Icon(Icons.arrow_back), // not sure which one to choose home_outlined),
          tooltip: 'Back to Home',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
    title: Text(title),
    actions: actions,
    bottom: bottom,
  );
}
