import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

import '../services/log_service.dart';

/// Displays logs collected during app interactions and widget updates.
class AppLogsPage extends StatefulWidget {
  const AppLogsPage({Key? key}) : super(key: key);

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  bool _showDelete = false;

  @override
  void initState() {
    super.initState();
    _checkEmulator();
  }

  Future<void> _checkEmulator() async {
    final deviceInfo = DeviceInfoPlugin();
    bool show = false;
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        show = !info.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        show = !info.isPhysicalDevice;
      }
    } catch (_) {
      show = false;
    }
    if (mounted) {
      setState(() => _showDelete = show);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App Logs')),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: LogService.logs,
        builder: (context, logs, _) {
          if (logs.isEmpty) {
            return const Center(child: Text('No logs yet'));
          }
          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) => ListTile(
              dense: true,
              title: Text(logs[index]),
            ),
          );
        },
      ),
      floatingActionButton: _showDelete
          ? FloatingActionButton(
              onPressed: LogService.clear,
              tooltip: 'Clear logs',
              child: const Icon(Icons.delete),
            )
          : null,
    );
  }
}
