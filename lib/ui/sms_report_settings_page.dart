import 'package:flutter/material.dart';

import '../models/sms_recipient.dart';
import '../models/sms_report_config.dart';
import '../services/sms_report_config_service.dart';
import '../services/sms_report_scheduler.dart';
import '../services/sms_report_service.dart';
import 'sms_report_log_page.dart';
import 'subpage_app_bar.dart';

class SmsReportSettingsPage extends StatefulWidget {
  const SmsReportSettingsPage({Key? key}) : super(key: key);

  @override
  State<SmsReportSettingsPage> createState() => _SmsReportSettingsPageState();
}

class _SmsReportSettingsPageState extends State<SmsReportSettingsPage> {
  SmsReportConfig? _config;
  late TextEditingController _templateController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _templateController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _templateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await SmsReportConfigService.load();
    setState(() {
      _config = c;
      _templateController.text = c.template;
      _loading = false;
    });
  }

  Future<void> _persist() async {
    final c = _config;
    if (c == null) return;
    await SmsReportConfigService.save(c);
    await SmsReportScheduler.applyFromConfig();
  }

  String _formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final c = _config;
    if (c == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: c.hour, minute: c.minute),
    );
    if (picked == null) return;
    setState(() {
      c.hour = picked.hour;
      c.minute = picked.minute;
    });
    await _persist();
  }

  Future<void> _editRecipient({SmsRecipient? existing, int? index}) async {
    final nicknameController =
        TextEditingController(text: existing?.nickname ?? '');
    final phoneController =
        TextEditingController(text: existing?.phoneNumber ?? '');

    final result = await showDialog<SmsRecipient>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add recipient' : 'Edit recipient'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nicknameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nickname'),
            ),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '+1234567890',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final phone = phoneController.text.trim();
              if (phone.isEmpty) return;
              Navigator.of(context).pop(SmsRecipient(
                nickname: nicknameController.text.trim(),
                phoneNumber: phone,
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final c = _config;
    if (c == null) return;
    setState(() {
      if (index == null) {
        c.recipients.add(result);
      } else {
        c.recipients[index] = result;
      }
    });
    await _persist();
  }

  Future<void> _removeRecipient(int index) async {
    final c = _config;
    if (c == null) return;
    setState(() => c.recipients.removeAt(index));
    await _persist();
  }

  Future<void> _resetTemplate() async {
    final c = _config;
    if (c == null) return;
    setState(() {
      c.template = kDefaultSmsTemplate;
      _templateController.text = kDefaultSmsTemplate;
    });
    await _persist();
  }

  Future<void> _saveTemplate() async {
    final c = _config;
    if (c == null) return;
    c.template = _templateController.text;
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Template saved')),
    );
  }

  Future<void> _sendTestNow() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Sending...')));
    final sent = await SmsReportService.runDailyReport();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Sent to $sent recipient(s)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return Scaffold(
        appBar: buildSubpageAppBar(context, title: 'Daily SMS report'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final c = _config!;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Daily SMS report'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Enable daily SMS report'),
                  subtitle: const Text(
                      'Sends an SMS each day at the chosen time to all recipients'),
                  value: c.enabled,
                  onChanged: (v) async {
                    setState(() => c.enabled = v);
                    await _persist();
                  },
                ),
                ListTile(
                  title: const Text('Send time'),
                  subtitle: Text(_formatTime(c.hour, c.minute)),
                  trailing: const Icon(Icons.schedule),
                  onTap: _pickTime,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        'Recipients',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Add recipient',
                        icon: const Icon(Icons.add),
                        onPressed: () => _editRecipient(),
                      ),
                    ],
                  ),
                ),
                if (c.recipients.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text('No recipients yet'),
                  )
                else
                  ...List<Widget>.generate(c.recipients.length, (i) {
                    final r = c.recipients[i];
                    final label = r.nickname.isEmpty ? '(no nickname)' : r.nickname;
                    return ListTile(
                      title: Text(label),
                      subtitle: Text(r.phoneNumber),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () =>
                                _editRecipient(existing: r, index: i),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeRecipient(i),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Message template',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tokens: {hello} {nickname} {completed} {uncompleted} {date} {list}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _templateController,
                    maxLines: 8,
                    minLines: 4,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _saveTemplate,
                        icon: const Icon(Icons.save),
                        label: const Text('Save template'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _resetTemplate,
                        child: const Text('Reset to default'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Sent message history'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SmsReportLogPage(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.send),
                  title: const Text('Send test now'),
                  subtitle: const Text(
                      'Run the report immediately using today\'s tasks'),
                  onTap: _sendTestNow,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
