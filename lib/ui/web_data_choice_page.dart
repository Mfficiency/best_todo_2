import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../services/storage_service.dart';
import '../services/todoist_api_client.dart';
import '../services/todoist_sync_service.dart';

/// Shown first on every `flutter run -d chrome` dev session: pick between
/// the dev seed data ("Demo data", what Chrome always showed before) and the
/// real task list pulled live from Todoist ("Real data").
///
/// The web has no documents dir, so nothing persists between runs — a Real
/// data session imports everything fresh into [StorageService]'s in-memory
/// store ([Config.webRealData]) and from there behaves like the real app,
/// two-way Todoist sync included. The token can come from
/// `--dart-define=TODOIST_TOKEN=...`, or be typed in and remembered in the
/// browser's local storage (SharedPreferences) for the next run.
class WebDataChoicePage extends StatefulWidget {
  final VoidCallback onFinished;
  const WebDataChoicePage({super.key, required this.onFinished});

  /// SharedPreferences key for a remembered token (web: localStorage).
  static const String tokenPrefKey = 'web_todoist_token';

  static const String _dartDefineToken =
      String.fromEnvironment('TODOIST_TOKEN');

  @override
  State<WebDataChoicePage> createState() => _WebDataChoicePageState();
}

class _WebDataChoicePageState extends State<WebDataChoicePage> {
  final _tokenController = TextEditingController();
  bool _obscured = true;
  bool _remember = true;
  bool _busy = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tokenController.text = WebDataChoicePage._dartDefineToken.isNotEmpty
        ? WebDataChoicePage._dartDefineToken
        : Config.todoistApiToken;
    _restoreRememberedToken();
  }

  Future<void> _restoreRememberedToken() async {
    if (_tokenController.text.trim().isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(WebDataChoicePage.tokenPrefKey);
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() => _tokenController.text = saved);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadRealData() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Enter your Todoist API token first');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Connecting to Todoist…';
    });
    try {
      await TodoistSyncService.instance.testConnection(token);
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_remember) {
          await prefs.setString(WebDataChoicePage.tokenPrefKey, token);
        } else {
          await prefs.remove(WebDataChoicePage.tokenPrefKey);
        }
      } catch (_) {}
      Config.todoistApiToken = token;
      Config.todoistSyncEnabled = true;
      // Before the import: its saves must land in the in-memory store.
      Config.webRealData = true;
      if (mounted) setState(() => _status = 'Loading your tasks…');
      final result = await TodoistSyncService.instance.startFirstLaunchImport();
      if (result == null) {
        throw StateError('A Todoist sync is already running — try again');
      }
      // Unlike the phone's first-launch import, wait for everything: the
      // home page reads the list once when it opens.
      final entry = await result.finishInBackground();
      if (entry != null && !entry.success) {
        throw StateError(entry.message);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Loaded ${entry?.itemCount ?? result.todayCount} task(s) from Todoist'),
      ));
      widget.onFinished();
    } catch (e) {
      Config.webRealData = false;
      StorageService.resetWebRealDataForTest();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
        _error = e is TodoistApiException
            ? (e.statusCode == 401 ? 'Invalid API token' : e.message)
            : e.toString();
      });
    }
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
                    'Which data?',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Browser dev session — nothing is saved between runs.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Icon(Icons.science_outlined,
                          size: 32, color: theme.colorScheme.primary),
                      title: const Text('Demo data'),
                      subtitle: const Text(
                          'Sample tasks, projects and stats to test with.'),
                      trailing: FilledButton.tonal(
                        onPressed: _busy ? null : widget.onFinished,
                        child: const Text('Use demo'),
                      ),
                      onTap: _busy ? null : widget.onFinished,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.cloud_download_outlined,
                                  size: 32, color: theme.colorScheme.primary),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text('Real data from Todoist',
                                    style: theme.textTheme.titleMedium),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Loads your actual Todoist tasks and projects. '
                            'Changes you make here sync back to Todoist.',
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _tokenController,
                            obscureText: _obscured,
                            enabled: !_busy,
                            decoration: InputDecoration(
                              labelText: 'Todoist API token',
                              helperText: 'Todoist → Settings → Integrations '
                                  '→ Developer',
                              errorText: _error,
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip:
                                    _obscured ? 'Show token' : 'Hide token',
                                icon: Icon(_obscured
                                    ? Icons.visibility
                                    : Icons.visibility_off),
                                onPressed: () =>
                                    setState(() => _obscured = !_obscured),
                              ),
                            ),
                            onSubmitted: (_) => _busy ? null : _loadRealData(),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Remember in this browser'),
                            value: _remember,
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _remember = v ?? true),
                          ),
                          if (_status != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(_status!),
                                ],
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: _busy ? null : _loadRealData,
                              child: const Text('Load real data'),
                            ),
                          ),
                        ],
                      ),
                    ),
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
