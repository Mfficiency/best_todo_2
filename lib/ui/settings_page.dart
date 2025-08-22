import 'package:flutter/material.dart';
import '../config.dart';
import '../main.dart';
import '../widget_update_worker.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const SettingsPage({Key? key, this.onSettingsChanged}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifications = Config.enableNotifications;
  bool _widgetUpdates = Config.enableWidgetUpdates;
  bool _swipeLeftDelete = Config.swipeLeftDelete;
  bool _darkMode = Config.darkMode;
  bool _useIconTabs = Config.useIconTabs;
  double _defaultDelaySeconds = Config.defaultDelaySeconds;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable notifications'),
            value: _notifications,
            onChanged: (val) async {
              setState(() => _notifications = val);
              Config.enableNotifications = val;
              await Config.save();
            },
          ),
          SwitchListTile(
            title: const Text('Refresh home widget at midnight'),
            value: _widgetUpdates,
            onChanged: (val) async {
              setState(() => _widgetUpdates = val);
              Config.enableWidgetUpdates = val;
              await Config.save();
              if (val) {
                registerWidgetUpdate();
              } else {
                cancelWidgetUpdate();
              }
            },
          ),
          SwitchListTile(
            title: const Text('Dark mode'),
            value: _darkMode,
            onChanged: (val) async {
              setState(() => _darkMode = val);
              Config.darkMode = val;
              await Config.save();
              MyApp.of(context)?.updateTheme();
              widget.onSettingsChanged?.call();
            },
          ),
          SwitchListTile(
            title: const Text('Swipe left to delete'),
            value: _swipeLeftDelete,
            onChanged: (val) async {
              setState(() => _swipeLeftDelete = val);
              Config.swipeLeftDelete = val;
              await Config.save();
              widget.onSettingsChanged?.call();
            },
          ),
          SwitchListTile(
            title: const Text('Use tab icons'),
            value: _useIconTabs,
            onChanged: (val) async {
              setState(() => _useIconTabs = val);
              Config.useIconTabs = val;
              await Config.save();
              widget.onSettingsChanged?.call();
            },
          ),
          ListTile(
            title: Text(
                'Default delay (${_defaultDelaySeconds.toStringAsFixed(1)}s)'),
            subtitle: Slider(
              value: _defaultDelaySeconds,
              min: 0,
              max: 10,
              divisions: 100,
              onChanged: (val) async {
                final newVal = (val * 10).round() / 10;
                setState(() => _defaultDelaySeconds = newVal);
                Config.defaultDelaySeconds = newVal;
                await Config.save();
                widget.onSettingsChanged?.call();
              },
            ),
          ),
        ],
      ),
    );
  }
}
