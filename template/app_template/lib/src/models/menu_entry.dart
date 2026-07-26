import 'package:flutter/material.dart';

/// A row on the main menu that pushes a page when tapped. App-specific entries
/// are declared in [AppConfig.customMenuEntries]; the built-in technical pages
/// (Settings, About, Changelog, …) are added by the main menu itself.
class MenuEntry {
  final IconData icon;
  final String label;

  /// Optional secondary line under the label.
  final String? subtitle;

  /// Builds the page to push. Kept as a builder so pages are constructed lazily
  /// (and can be `const`).
  final Widget Function() routeBuilder;

  const MenuEntry({
    required this.icon,
    required this.label,
    required this.routeBuilder,
    this.subtitle,
  });
}
