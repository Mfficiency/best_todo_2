import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/alarm_log_service.dart';
import '../services/notification_service.dart';
import 'subpage_app_bar.dart';

/// Viewer for the persistent alarm reliability log (alarm_log.txt) with
/// one-tap tools to exercise the pipeline: fire a test alarm through the
/// full scheduling chain and run the diagnostics snapshot.
class AlarmLogPage extends StatefulWidget {
  const AlarmLogPage({Key? key}) : super(key: key);

  @override
  State<AlarmLogPage> createState() => _AlarmLogPageState();
}

class _AlarmLogPageState extends State<AlarmLogPage> {
  String _content = '';
  String? _path;
  bool _loading = true;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    AlarmLog.revision.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    AlarmLog.revision.removeListener(_reload);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final content = await AlarmLog.read();
    final path = await AlarmLog.path();
    if (!mounted) return;
    setState(() {
      _content = content;
      _path = path;
      _loading = false;
    });
    // Newest entries are at the end — keep the view pinned there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log copied to clipboard')),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear alarm log?'),
        content: const Text(
            'The history of scheduled and fired alarms will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AlarmLog.clear();
      await _reload();
    }
  }

  Future<void> _testAlarm() async {
    await NotificationService.scheduleTestAlarm();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 6),
        content: Text('Test alarm set for ~1 minute from now. Lock the phone '
            'and wait — the delivery verdict appears here ~90 s after the '
            'ring time.'),
      ),
    );
  }

  Future<void> _diagnostics() async {
    await NotificationService.runAlarmDiagnostics(trigger: 'manual');
    await _reload();
  }

  Color? _lineColor(BuildContext context, String line) {
    if (line.contains('[FAIL')) return Colors.red.shade400;
    if (line.contains('[WARN')) return Colors.orange.shade700;
    if (line.contains('[OK')) return Colors.green.shade600;
    if (line.startsWith('════')) return Theme.of(context).colorScheme.primary;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = _content.isEmpty ? const <String>[] : _content.split('\n');
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Alarm Log',
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy whole log',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _reload,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_path != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                'File: $_path',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _testAlarm,
                    icon: const Icon(Icons.alarm_add),
                    label: const Text('Test alarm (1 min)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _diagnostics,
                    icon: const Icon(Icons.medical_services_outlined),
                    label: const Text('Run diagnostics'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : lines.isEmpty
                    ? Center(
                        child: Text(
                          'No log entries yet.\nSave an alarm or run a test '
                          'alarm to start the trail.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.hintColor),
                        ),
                      )
                    : Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          itemCount: lines.length,
                          itemBuilder: (context, index) {
                            final line = lines[index];
                            return SelectableText(
                              line,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.35,
                                color: _lineColor(context, line),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
