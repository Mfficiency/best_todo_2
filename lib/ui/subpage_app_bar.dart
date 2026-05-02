import 'package:flutter/material.dart';

import 'home_scaffold_key.dart';

AppBar buildSubpageAppBar(
  BuildContext context, {
  required String title,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    automaticallyImplyLeading: false,
    leadingWidth: 96,
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
        IconButton(
          icon: const Icon(Icons.arrow_back), // not sure which one to choose home_outlined),
          tooltip: 'Back to Home',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
    title: Text(title),
    bottom: bottom,
  );
}
