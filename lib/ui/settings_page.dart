import 'package:flutter/material.dart';
import '../config.dart';
import '../main.dart';
import 'subpage_app_bar.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;
  const SettingsPage({Key? key, this.onSettingsChanged}) : super(key: key);

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifications = Config.enableNotifications;
  bool _swipeLeftDelete = Config.swipeLeftDelete;
  bool _darkMode = Config.darkMode;
  bool _useIconTabs = Config.useIconTabs;
  bool _showWidgetProgressLine = Config.showWidgetProgressLine;
  double _defaultDelaySeconds = Config.defaultDelaySeconds;
  int _defaultNotificationDelaySeconds = Config.defaultNotificationDelaySeconds;

  String _formatMmSs(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  int? _parseMmSs(String value) {
    final normalized = value.trim();
    final match = RegExp(r'^(\d{1,3}):([0-5]\d)$').firstMatch(normalized);
    if (match == null) return null;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    return minutes * 60 + seconds;
  }

  Future<void> _editNotificationDelay() async {
    final controller = TextEditingController(
      text: _formatMmSs(_defaultNotificationDelaySeconds),
    );
    String? errorText;

    final parsed = await showDialog<int>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Default notification delay'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'MM:SS',
                hintText: '00:30',
                errorText: errorText,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final seconds = _parseMmSs(controller.text);
                  if (seconds == null) {
                    setDialogState(() => errorText = 'Use format MM:SS');
                    return;
                  }
                  Navigator.of(context).pop(seconds);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (parsed == null) return;
    setState(() => _defaultNotificationDelaySeconds = parsed);
    Config.defaultNotificationDelaySeconds = parsed;
    await Config.save();
    widget.onSettingsChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Settings'),
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
          ListTile(
            title: const Text('Default notification delay'),
            subtitle: Text('MM:SS (${_formatMmSs(_defaultNotificationDelaySeconds)})'),
            trailing: const Icon(Icons.edit),
            onTap: _editNotificationDelay,
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
          SwitchListTile(
            title: const Text('Widget progress line'),
            subtitle: const Text('Show completion line on the home widget'),
            value: _showWidgetProgressLine,
            onChanged: (val) async {
              setState(() => _showWidgetProgressLine = val);
              Config.showWidgetProgressLine = val;
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
