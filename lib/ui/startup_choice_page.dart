import 'package:flutter/material.dart';

import '../config.dart';
import '../services/todoist_api_client.dart';
import '../services/todoist_sync_service.dart';

/// Shown once, right after onboarding finishes on a brand-new install
/// (never for an upgrade of an existing install — see the backfill logic in
/// `main()`): choose between an empty task list and pulling everything in
/// from a Todoist account via the existing two-way sync
/// ([TodoistSyncService]).
class StartupChoicePage extends StatelessWidget {
  final VoidCallback onFinished;
  const StartupChoicePage({super.key, required this.onFinished});

  Future<void> _importFromTodoist(BuildContext context) async {
    final result = await showDialog<_TodoistImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _TodoistImportDialog(),
    );
    if (result == null) return; // cancelled: stay on this page
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
    onFinished();
  }

  Widget _choiceCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 32, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onTap,
                  child: Text(buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Set up your tasks',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can change this later in Settings.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  _choiceCard(
                    context,
                    icon: Icons.playlist_add_check,
                    title: 'Start fresh',
                    subtitle: 'Begin with an empty task list.',
                    buttonLabel: 'Start fresh',
                    onTap: onFinished,
                  ),
                  const SizedBox(height: 16),
                  _choiceCard(
                    context,
                    icon: Icons.cloud_download_outlined,
                    title: 'Import from Todoist',
                    subtitle: 'Connect a Todoist account and pull in your '
                        'existing tasks and projects.',
                    buttonLabel: 'Import from Todoist',
                    onTap: () => _importFromTodoist(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodoistImportResult {
  final String message;
  const _TodoistImportResult(this.message);
}

/// Owns its own [TextEditingController] (rather than the page above) so the
/// controller survives the dialog's exit animation — see CLAUDE.md.
class _TodoistImportDialog extends StatefulWidget {
  const _TodoistImportDialog();

  @override
  State<_TodoistImportDialog> createState() => _TodoistImportDialogState();
}

class _TodoistImportDialogState extends State<_TodoistImportDialog> {
  final _tokenController = TextEditingController();
  bool _obscured = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _connectAndImport() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Enter an API token first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TodoistSyncService.instance.testConnection(token);
      Config.todoistApiToken = token;
      Config.todoistSyncEnabled = true;
      await Config.save();
      final entry =
          await TodoistSyncService.instance.syncNow(trigger: 'initial import');
      if (!mounted) return;
      Navigator.of(context).pop(_TodoistImportResult(
        entry != null && entry.success
            ? 'Imported ${entry.itemCount} task(s) from Todoist'
            : 'Connected to Todoist, but the first sync failed — '
                'retry from Settings → Todoist sync.',
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is TodoistApiException
            ? (e.statusCode == 401 ? 'Invalid API token' : e.message)
            : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect Todoist'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('From Todoist → Settings → Integrations → Developer.'),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              obscureText: _obscured,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'API token',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscured ? 'Show token' : 'Hide token',
                  icon: Icon(_obscured
                      ? Icons.visibility
                      : Icons.visibility_off),
                  onPressed: () => setState(() => _obscured = !_obscured),
                ),
              ),
              onSubmitted: (_) => _busy ? null : _connectAndImport(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _connectAndImport,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_download_outlined),
          label: const Text('Connect & Import'),
        ),
      ],
    );
  }
}
