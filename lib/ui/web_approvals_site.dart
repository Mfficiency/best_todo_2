import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/todoist_api_client.dart';
import '../services/todoist_sync_service.dart';
import '../services/web_approvals/approvals_sync.dart';
import '../services/web_approvals/browser.dart';
import '../services/web_approvals/real_data_loader.dart';
import '../services/web_approvals/token_vault.dart';
import '../services/web_approvals/vault_crypto.dart';
import '../utils/voice_inbox.dart';
import 'waiting_approval_page.dart';

/// [VaultStore] over SharedPreferences — the browser's localStorage.
class PrefsVaultStore implements VaultStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// The approvals website (SPEC §4.2k): a password-locked Waiting for
/// Approval page over the live Todoist account, nothing else of the app.
class WebApprovalsSiteApp extends StatelessWidget {
  const WebApprovalsSiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness brightness) => ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: brightness,
          ),
          useMaterial3: true,
        );
    return MaterialApp(
      title: 'BestToDo approvals',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: WebApprovalsSite(
        vault: TokenVault(store: PrefsVaultStore(), crypto: VaultCrypto.platform),
      ),
    );
  }
}

/// Categories approved only in the app: their approval does more than the
/// website can (SPEC §4.2k) — Food/Groceries become local-only items, a
/// Backlog approval fires the Obsidian-page routine, Research's flag never
/// syncs.
const Set<String> hiddenOnSite = {
  ApprovalGroups.backlog,
  ApprovalGroups.research,
  ApprovalGroups.groceries,
  ApprovalGroups.food,
};

enum _Stage { checking, framed, setup, locked, loading, open }

class WebApprovalsSite extends StatefulWidget {
  final TokenVault vault;

  /// Loads the account into memory (tests fake it).
  final Future<int> Function(String token, void Function(String) onStatus)
      loadData;

  /// Locks: the real site reloads the tab, wiping everything in memory.
  final VoidCallback lock;

  /// No input for this long locks the site.
  final Duration idleTimeout;

  WebApprovalsSite({
    super.key,
    required this.vault,
    Future<int> Function(String, void Function(String))? loadData,
    VoidCallback? lock,
    this.idleTimeout = const Duration(minutes: 15),
  })  : loadData = loadData ??
            ((token, onStatus) => loadRealTodoistData(token, onStatus: onStatus)),
        lock = lock ?? reloadPage;

  @override
  State<WebApprovalsSite> createState() => _WebApprovalsSiteState();
}

class _WebApprovalsSiteState extends State<WebApprovalsSite> {
  _Stage _stage = _Stage.checking;
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _status;
  ApprovalsSyncCoordinator? _sync;
  Timer? _idleTimer;
  Timer? _pullTimer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (isFramed()) {
      setState(() => _stage = _Stage.framed);
      return;
    }
    // A banned browser looks exactly like one with a vault.
    final locked =
        await widget.vault.exists() || await widget.vault.isBanned();
    if (!mounted) return;
    setState(() => _stage = locked ? _Stage.locked : _Stage.setup);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _pullTimer?.cancel();
    _sync?.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _setUp() async {
    final token = _token.text.trim();
    final password = _password.text;
    final problem = token.isEmpty
        ? 'Enter your Todoist API token'
        : TokenVault.passwordProblem(password) ??
            (password != _confirm.text ? 'The passwords differ' : null);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Checking the token…';
    });
    try {
      await TodoistSyncService.instance.testConnection(token);
    } catch (e) {
      _fail(e);
      return;
    }
    setState(() => _status = 'Encrypting it in this browser…');
    try {
      await widget.vault.create(token, password);
    } catch (e) {
      _fail(e);
      return;
    }
    await _open(token);
  }

  Future<void> _unlock() async {
    final password = _password.text;
    if (password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Unlocking…';
    });
    final String token;
    try {
      token = await widget.vault.unlock(password);
    } on WrongPasswordException {
      // Same answer whether it was a typo or the browser is banned.
      _password.clear();
      _fail(null, message: 'Wrong password');
      return;
    } on VaultWipedException {
      _password.clear();
      setState(() {
        _busy = false;
        _status = null;
        _stage = _Stage.setup;
        _error = null;
      });
      return;
    }
    await _open(token);
  }

  Future<void> _open(String token) async {
    _password.clear();
    _confirm.clear();
    _token.clear();
    setState(() {
      _stage = _Stage.loading;
      _status = 'Connecting to Todoist…';
    });
    try {
      await widget.loadData(token, (status) {
        if (mounted) setState(() => _status = status);
      });
    } catch (e) {
      // Wrong token (revoked?) or offline: back to the lock screen.
      _fail(e, stage: _Stage.locked);
      return;
    }
    if (!mounted) return;
    final sync = ApprovalsSyncCoordinator(runSync: () async {
      final entry =
          await TodoistSyncService.instance.syncNow(trigger: 'approvals site');
      if (entry == null) return 'Sync skipped';
      return entry.success ? null : entry.message;
    });
    sync.syncing.addListener(_updateLeaveWarning);
    _sync = sync;
    // New voice notes keep arriving while the page is open.
    _pullTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (!sync.syncing.value) unawaited(sync.syncNow());
    });
    HardwareKeyboard.instance.addHandler(_onKey);
    _touch();
    setState(() {
      _busy = false;
      _status = null;
      _stage = _Stage.open;
    });
  }

  void _fail(Object? e, {String? message, _Stage? stage}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = null;
      if (stage != null) _stage = stage;
      _error = message ??
          (e is TodoistApiException
              ? (e.statusCode == 401 ? 'Todoist rejected the token' : e.message)
              : '$e');
      if (_error!.isEmpty) _error = null;
    });
  }

  void _updateLeaveWarning() =>
      setLeaveWarning(_sync?.syncing.value ?? false);

  bool _onKey(KeyEvent event) {
    _touch();
    return false;
  }

  void _touch() {
    if (_stage != _Stage.open && _sync == null) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleTimeout, _lock);
  }

  /// Pushes what's still waiting for the debounced sync, then wipes the tab.
  Future<void> _lock() async {
    _idleTimer?.cancel();
    _pullTimer?.cancel();
    final sync = _sync;
    // Capped: offline, the lock mustn't hang on the request.
    if (sync != null) {
      await sync.syncNow().timeout(const Duration(seconds: 20), onTimeout: () {});
    }
    setLeaveWarning(false);
    widget.lock();
  }

  Future<void> _forget() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget this browser?'),
        content: const Text('Deletes the encrypted token from this browser. '
            'You will need the Todoist token again to use the site here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await widget.vault.forget();
    if (_stage == _Stage.open) {
      await _lock();
      return;
    }
    // Banned: nothing visible happens — setup stays closed.
    if (await widget.vault.isBanned() || !mounted) return;
    setState(() {
      _error = null;
      _stage = _Stage.setup;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.checking:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _Stage.framed:
        return const Scaffold(
          body: Center(child: Text('This page can only be opened directly.')),
        );
      case _Stage.open:
        final sync = _sync!;
        return Listener(
          onPointerDown: (_) => _touch(),
          onPointerSignal: (_) => _touch(),
          child: WaitingApprovalPage(
            site: ApprovalSiteOptions(
              sync: sync,
              hiddenGroups: hiddenOnSite,
              actions: [
                ValueListenableBuilder<bool>(
                  valueListenable: sync.syncing,
                  builder: (context, syncing, _) =>
                      ValueListenableBuilder<String?>(
                    valueListenable: sync.lastError,
                    builder: (context, error, _) => IconButton(
                      tooltip: syncing
                          ? 'Syncing with Todoist…'
                          : error ?? 'Sync with Todoist',
                      icon: Icon(syncing
                          ? Icons.sync
                          : error == null
                              ? Icons.cloud_done_outlined
                              : Icons.sync_problem),
                      onPressed: syncing ? null : sync.syncNow,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (value) =>
                      value == 'forget' ? _forget() : _lock(),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'lock', child: Text('Lock')),
                    PopupMenuItem(
                        value: 'forget', child: Text('Forget this browser')),
                  ],
                ),
              ],
            ),
          ),
        );
      case _Stage.setup:
      case _Stage.locked:
      case _Stage.loading:
        return Scaffold(body: _buildForm(context));
    }
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final setup = _stage == _Stage.setup;
    final enabled = !_busy && _stage != _Stage.loading;
    InputDecoration field(String label, {String? helper}) => InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        );
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_outline,
                      size: 40, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    setup ? 'Set up approvals' : 'Waiting for Approval',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    setup
                        ? 'Your Todoist token is stored in this browser only, '
                            'encrypted with the password you choose here. '
                            'Nothing is sent anywhere but Todoist.'
                        : 'Enter your password to unlock.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (setup) ...[
                    TextField(
                      key: const Key('site-token'),
                      controller: _token,
                      enabled: enabled,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: field('Todoist API token',
                          helper: 'Todoist → Settings → Integrations → '
                              'Developer'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    key: const Key('site-password'),
                    controller: _password,
                    enabled: enabled,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: [
                      setup ? AutofillHints.newPassword : AutofillHints.password
                    ],
                    decoration: field(
                      setup ? 'New password' : 'Password',
                      helper: setup
                          ? 'At least ${TokenVault.minPasswordLength} '
                              'characters. It cannot be recovered — if you '
                              'forget it, set the site up again.'
                          : null,
                    ),
                    onSubmitted: setup ? null : (_) => _unlock(),
                  ),
                  if (setup) ...[
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('site-confirm'),
                      controller: _confirm,
                      enabled: enabled,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: field('Repeat password'),
                      onSubmitted: (_) => _setUp(),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_status!)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: enabled ? (setup ? _setUp : _unlock) : null,
                    child: Text(setup ? 'Save and open' : 'Unlock'),
                  ),
                  if (!setup) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: enabled ? _forget : null,
                      child: const Text('Forget this browser'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
