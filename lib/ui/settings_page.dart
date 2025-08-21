import 'package:flutter/material.dart';
import '../config.dart';
import '../main.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const SettingsPage({Key? key, this.onSettingsChanged}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifications = false;
  bool _swipeLeftDelete = Config.swipeLeftDelete;
  bool _darkMode = Config.darkMode;
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
            onChanged: (val) => setState(() => _notifications = val),
          ),
          SwitchListTile(
            title: const Text('Dark mode'),
            value: _darkMode,
            onChanged: (val) {
              setState(() => _darkMode = val);
              Config.darkMode = val;
              MyApp.of(context)?.updateTheme();
              widget.onSettingsChanged?.call();
            },
          ),
          SwitchListTile(
            title: const Text('Swipe left to delete'),
            value: _swipeLeftDelete,
            onChanged: (val) {
              setState(() => _swipeLeftDelete = val);
              Config.swipeLeftDelete = val;
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
              onChanged: (val) {
                final newVal = (val * 10).round() / 10;
                setState(() => _defaultDelaySeconds = newVal);
                Config.defaultDelaySeconds = newVal;
                widget.onSettingsChanged?.call();
              },
            ),
          ),
        ],
      ),
    );
  }
}
