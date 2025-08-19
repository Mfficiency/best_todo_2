import 'package:flutter/material.dart';

import '../services/log_service.dart';

/// Displays logs collected during app interactions and widget updates.
class AppLogsPage extends StatefulWidget {
  const AppLogsPage({Key? key}) : super(key: key);

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  @override
  void initState() {
    super.initState();
    LogService.init();
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
      floatingActionButton: FloatingActionButton(
        onPressed: LogService.clear,
        tooltip: 'Clear logs',
        child: const Icon(Icons.delete),
      ),
    );
  }
}
