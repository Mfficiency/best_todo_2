import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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

  Future<void> _exportHistory() async {
    final messenger = ScaffoldMessenger.of(context);
    final downloads = await getDownloadsDirectory();
    final directory =
        await getDirectoryPath(initialDirectory: downloads?.path);
    if (directory == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Export canceled')),
      );
      return;
    }
    final now = DateTime.now();
    final two = (int n) => n.toString().padLeft(2, '0');
    final ts =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final sep = Platform.pathSeparator;
    final path =
        '$directory${directory.endsWith(sep) ? '' : sep}sms_report_log_$ts.json';
    final file = await SmsReportLogService.exportTo(path);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(
        file != null ? 'Exported to ${file.path}' : 'Export failed',
      ),
    ));
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
                      final isDiag = e.kind == SmsLogKind.diag;
                      final icon = isDiag
                          ? (e.success ? Icons.info_outline : Icons.warning_amber)
                          : (e.success ? Icons.check_circle : Icons.error);
                      final color = e.success
                          ? (isDiag ? Colors.blueGrey : Colors.green)
                          : (isDiag ? Colors.orange : Colors.red);
                      final title = isDiag
                          ? e.message
                          : (e.recipientNickname.isEmpty
                              ? e.recipientPhone
                              : '${e.recipientNickname} (${e.recipientPhone})');
                      final subtitle = isDiag
                          ? _formatTimestamp(e.sentAt)
                          : '${_formatTimestamp(e.sentAt)}  '
                              '• ${e.completedCount} done / ${e.uncompletedCount} left';
                      return ExpansionTile(
                        leading: Icon(icon, color: color),
                        title: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(subtitle),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (e.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SelectableText(
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'sms_log_export',
            onPressed: _exportHistory,
            icon: const Icon(Icons.file_download),
            label: const Text('Export'),
          ),
          if (_entries.isNotEmpty) ...[
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'sms_log_clear',
              onPressed: _confirmClear,
              tooltip: 'Clear history',
              child: const Icon(Icons.delete),
            ),
          ],
        ],
      ),
    );
  }
}
