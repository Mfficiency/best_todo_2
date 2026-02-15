import 'package:flutter/material.dart';

import '../services/log_service.dart';
import 'subpage_app_bar.dart';

/// Displays logs collected during app interactions and widget updates.
class AppLogsPage extends StatelessWidget {
  const AppLogsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'App Logs'),
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
