import 'package:flutter/material.dart';

import '../models/sms_report_log_entry.dart';
import '../services/sms_report_log_service.dart';
import 'subpage_app_bar.dart';

class SmsReportLogPage extends StatefulWidget {
  const SmsReportLogPage({Key? key}) : super(key: key);

  @override
  State<SmsReportLogPage> createState() => _SmsReportLogPageState();
}

class _SmsReportLogPageState extends State<SmsReportLogPage> {
  List<SmsReportLogEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await SmsReportLogService.load();
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This will delete all logged SMS messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SmsReportLogService.clear();
    await _load();
  }

  String _formatTimestamp(DateTime dt) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'SMS report history'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('No messages sent yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = _entries[i];
                      final label = e.recipientNickname.isEmpty
                          ? e.recipientPhone
                          : '${e.recipientNickname} (${e.recipientPhone})';
                      return ExpansionTile(
                        leading: Icon(
                          e.success ? Icons.check_circle : Icons.error,
                          color: e.success ? Colors.green : Colors.red,
                        ),
                        title: Text(label),
                        subtitle: Text(
                          '${_formatTimestamp(e.sentAt)}  '
                          '• ${e.completedCount} done / ${e.uncompletedCount} left',
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Error: ${e.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          SelectableText(e.message),
                        ],
                      );
                    },
                  ),
                ),
      floatingActionButton: _entries.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _confirmClear,
              tooltip: 'Clear history',
              child: const Icon(Icons.delete),
            ),
    );
  }
}
