import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/agent_desk.dart';
import '../services/agent_desk_service.dart';
import '../services/todoist_api_client.dart';
import 'speech_input_button.dart';
import 'subpage_app_bar.dart';

/// "5 min ago"-style age of [at] relative to [now].
String deskAge(DateTime? at, DateTime now) {
  if (at == null) return '';
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 30) return '${d.inDays} d ago';
  return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
}

Color deskStateColor(DeskState state, ColorScheme scheme) => switch (state) {
      DeskState.working => Colors.blue,
      DeskState.waiting => Colors.orange,
      DeskState.error => scheme.error,
      DeskState.idle => scheme.outline,
    };

IconData deskWhereIcon(String where) => switch (where) {
      'cloud' => Icons.cloud_outlined,
      'both' => Icons.cloud_sync_outlined,
      _ => Icons.computer,
    };

String _deskError(Object e) {
  if (e is TodoistApiException) {
    return e.statusCode == 401 ? 'Todoist refused the token' : e.message;
  }
  return 'Todoist could not be reached';
}

Future<void> _openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Tools → Agent Desk (SPEC §10.6s): what the background agents need from you,
/// as Todoist tasks labelled `agentdesk`.
///
/// At 1000 px and wider it's a three-pane desk (the queue, the selected item
/// with its description and attachments, the projects); narrower, a list whose
/// entries open on their own page. [embedded] leaves out the scaffold: the home
/// page hosts it next to its task list, under its own app bar and menu.
class AgentDeskPage extends StatefulWidget {
  final AgentDeskService? service;
  final bool embedded;

  /// False while it sits hidden behind the task list: no polling then.
  final bool active;

  /// How often Todoist is asked; null turns polling off (tests).
  final Duration? pollInterval;
  final DateTime Function()? clock;

  const AgentDeskPage({
    super.key,
    this.service,
    this.embedded = false,
    this.active = true,
    this.pollInterval = const Duration(seconds: 30),
    this.clock,
  });

  @override
  State<AgentDeskPage> createState() => AgentDeskPageState();
}

class AgentDeskPageState extends State<AgentDeskPage> {
  static const double wideWidth = 1000;

  AgentDeskService get _service => widget.service ?? AgentDeskService.instance;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  DeskBoard? _board;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  DateTime? _lastRefresh;
  Timer? _poll;

  /// The selected question, or null for the top of the queue.
  String? _selectedId;

  /// The selected project; wins over [_selectedId] while set.
  String? _selectedProject;

  /// Bumped by every refresh, so the open item re-reads its comments.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _start();
    final every = widget.pollInterval;
    if (every != null) {
      _poll = Timer.periodic(every, (_) {
        // Not behind Settings or a dialog, and not behind the task list.
        if (!widget.active || !mounted) return;
        if (ModalRoute.of(context)?.isCurrent == false) return;
        refresh();
      });
    }
  }

  @override
  void didUpdateWidget(AgentDeskPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final cached = await _service.loadCached();
    if (!mounted) return;
    setState(() {
      _board ??= cached;
      _loading = _service.connected && _board == null;
    });
    if (_service.connected && widget.active) await refresh();
  }

  /// Fetches the desk. What's on screen stays when that fails.
  Future<void> refresh() async {
    if (_refreshing || !_service.connected) return;
    _refreshing = true;
    if (mounted) setState(() {});
    try {
      final board = await _service.refresh();
      if (!mounted) return;
      setState(() {
        _board = board;
        _error = null;
        _lastRefresh = _now();
        _revision++;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _deskError(e));
    } finally {
      _refreshing = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Moves the selection in the queue (arrow keys / J and K, from the home
  /// page's key handler).
  void moveSelection(int delta) {
    final queue = _board?.open ?? const <DeskItem>[];
    if (queue.isEmpty) return;
    final current = queue.indexWhere((i) => i.id == _selectedItem(_board!)?.id);
    final next = (current + delta).clamp(0, queue.length - 1);
    setState(() {
      _selectedProject = null;
      _selectedId = queue[next].id;
    });
  }

  DeskItem? _selectedItem(DeskBoard board) {
    final picked = _selectedId == null ? null : board.item(_selectedId!);
    if (picked != null) return picked;
    final queue = board.open;
    return queue.isEmpty ? null : queue.first;
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Returns whether the answer reached Todoist; the pane keeps the text when
  /// it didn't.
  Future<bool> _answer(DeskItem item, String text) async {
    try {
      await _service.answer(item, text);
    } catch (e) {
      _snack('Not sent: ${_deskError(e)}');
      return false;
    }
    _snack('Sent to ${item.project}');
    if (mounted && _selectedId == item.id) setState(() => _selectedId = null);
    await refresh();
    return true;
  }

  Future<bool> _instruct(String project, String text) async {
    try {
      await _service.instruct(project, text);
    } catch (e) {
      _snack('Not sent: ${_deskError(e)}');
      return false;
    }
    _snack('Sent to $project');
    await refresh();
    return true;
  }

  Future<void> _close(DeskItem item) async {
    try {
      await _service.close(item);
    } catch (e) {
      _snack('Not closed: ${_deskError(e)}');
      return;
    }
    if (mounted && _selectedId == item.id) setState(() => _selectedId = null);
    await refresh();
  }

  Future<void> _seed() async {
    try {
      await _service.seed();
    } catch (e) {
      _snack('Could not set up the desk: ${_deskError(e)}');
    }
    await refresh();
  }

  Future<void> _connect(String token) async {
    await _service.connect(token);
    if (mounted) setState(() => _loading = true);
    await refresh();
  }

  void _selectItem(DeskItem item, bool wide) {
    if (wide) {
      setState(() {
        _selectedProject = null;
        _selectedId = item.id;
      });
    } else {
      _push(item.title, (_) => _itemPane(item));
    }
  }

  void _selectProject(DeskProject project, bool wide) {
    if (wide) {
      setState(() => _selectedProject = project.name);
    } else {
      _push(project.name, (context) => _projectPane(project, wide: false));
    }
  }

  Future<void> _push(String title, WidgetBuilder pane) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: buildSubpageAppBar(context, title: title),
        body: pane(context),
      ),
    ));
    await refresh();
  }

  Widget _itemPane(DeskItem item) => DeskItemPane(
        key: ValueKey('desk-item-${item.id}'),
        item: item,
        service: _service,
        now: _now(),
        revision: _revision,
        onAnswer: (text) => _answer(item, text),
        onClose: () => _close(item),
      );

  Widget _projectPane(DeskProject project, {required bool wide}) =>
      DeskProjectPane(
        key: ValueKey('desk-project-${project.name}'),
        project: project,
        now: _now(),
        onInstruct: (text) => _instruct(project.name, text),
        onOpenItem: (item) => _selectItem(item, wide),
      );

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Agent Desk',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refreshing ? null : refresh,
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _body(BuildContext context) {
    if (!_service.connected) return _ConnectCard(onConnect: _connect);
    final board = _board;
    if (board == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _EmptyDesk(error: _error, onSeed: _seed, onRetry: refresh);
    }
    if (board.isEmpty) {
      return _EmptyDesk(error: _error, onSeed: _seed, onRetry: refresh);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= wideWidth;
      if (!wide) {
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            children: [
              _statusLine(context),
              ..._queue(board, wide: false),
              ..._projects(board, wide: false),
              const SizedBox(height: 32),
            ],
          ),
        );
      }
      final project =
          _selectedProject == null ? null : board.project(_selectedProject!);
      final item = _selectedItem(board);
      final divider = VerticalDivider(
          width: 1, color: Theme.of(context).colorScheme.outlineVariant);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 340,
            child: ListView(
              children: [_statusLine(context), ..._queue(board, wide: true)],
            ),
          ),
          divider,
          Expanded(
            child: project != null
                ? _projectPane(project, wide: true)
                : item != null
                    ? _itemPane(item)
                    : const _AllClear(),
          ),
          divider,
          SizedBox(
            width: 290,
            child: ListView(children: _projects(board, wide: true)),
          ),
        ],
      );
    });
  }

  Widget _statusLine(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final text = error != null
        ? '$error. Showing the last known desk.'
        : _lastRefresh == null
            ? 'Not updated yet'
            : 'Updated ${deskAge(_lastRefresh, _now())}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Text(text,
          style: theme.textTheme.bodySmall?.copyWith(
              color: error != null
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline)),
    );
  }

  List<Widget> _queue(DeskBoard board, {required bool wide}) {
    final open = board.open;
    final now_ = open.where((i) => i.priority != DeskPriority.later).toList();
    final later = open.where((i) => i.priority == DeskPriority.later).toList();
    final selected =
        wide && _selectedProject == null ? _selectedItem(board)?.id : null;
    DeskItemTile tile(DeskItem item, {int? rank}) => DeskItemTile(
          item: item,
          rank: rank,
          now: _now(),
          selected: item.id == selected,
          onTap: () => _selectItem(item, wide),
        );
    return [
      _SectionTitle('Decide', trailing: '${now_.length}'),
      if (now_.isEmpty)
        const ListTile(
          dense: true,
          leading: Icon(Icons.check_circle_outline),
          title: Text('Nothing is waiting on you.'),
        ),
      for (var i = 0; i < now_.length; i++) tile(now_[i], rank: i + 1),
      if (later.isNotEmpty) ...[
        _SectionTitle('Later', trailing: '${later.length}'),
        for (final item in later) tile(item),
      ],
      if (board.answered.isNotEmpty) ...[
        _SectionTitle('Answered', trailing: '${board.answered.length}'),
        for (final item in board.answered) tile(item),
      ],
    ];
  }

  List<Widget> _projects(DeskBoard board, {required bool wide}) => [
        _SectionTitle('Projects', trailing: '${board.projects.length}'),
        for (final p in board.projects)
          DeskProjectTile(
            project: p,
            now: _now(),
            selected: wide && _selectedProject == p.name,
            onTap: () => _selectProject(p, wide),
          ),
      ];
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionTitle(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          Text(title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary)),
          const SizedBox(width: 8),
          if (trailing != null)
            Text(trailing!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

/// A row of the queue.
class DeskItemTile extends StatelessWidget {
  final DeskItem item;
  final int? rank;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  const DeskItemTile({
    super.key,
    required this.item,
    required this.now,
    required this.onTap,
    this.rank,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      item.project,
      if (item.topic.isNotEmpty) item.topic,
      if (item.at != null) deskAge(item.at, now),
    ].join(' · ');
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withAlpha(90),
      leading: item.isAnswered
          ? Icon(Icons.reply, size: 20, color: theme.colorScheme.outline)
          : CircleAvatar(
              radius: 12,
              backgroundColor: item.priority == DeskPriority.blocking
                  ? theme.colorScheme.errorContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Text(rank?.toString() ?? '·',
                  style: theme.textTheme.labelSmall),
            ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: item.deadline == null
          ? null
          : Text('by ${item.deadline!.month}/${item.deadline!.day}',
              style: theme.textTheme.labelSmall),
      onTap: onTap,
    );
  }
}

/// A row of the projects list.
class DeskProjectTile extends StatelessWidget {
  final DeskProject project;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  const DeskProjectTile({
    super.key,
    required this.project,
    required this.now,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgent =
        project.open.where((i) => i.priority != DeskPriority.later).length;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withAlpha(90),
      leading: Tooltip(
        message: project.state.name,
        child: Icon(Icons.circle,
            size: 12, color: deskStateColor(project.state, theme.colorScheme)),
      ),
      minLeadingWidth: 12,
      title: Text(project.name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: project.summary.isEmpty
          ? null
          : Text(project.summary,
              maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: urgent > 0
          ? Badge(
              label: Text('$urgent'),
              backgroundColor: theme.colorScheme.primary,
            )
          : null,
      onTap: onTap,
    );
  }
}

/// The selected question: its big description, attachments and comments, with
/// the answer bar fixed to the bottom. Owns its text controller (CLAUDE.md:
/// never dispose one a parent rebuild may still use).
class DeskItemPane extends StatefulWidget {
  final DeskItem item;
  final AgentDeskService service;
  final DateTime now;

  /// A change re-reads the comments.
  final int revision;
  final Future<bool> Function(String text) onAnswer;
  final Future<void> Function() onClose;

  const DeskItemPane({
    super.key,
    required this.item,
    required this.service,
    required this.now,
    required this.revision,
    required this.onAnswer,
    required this.onClose,
  });

  @override
  State<DeskItemPane> createState() => _DeskItemPaneState();
}

class _DeskItemPaneState extends State<DeskItemPane> {
  final TextEditingController _controller = TextEditingController();
  List<DeskComment>? _comments;
  String? _commentsError;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void didUpdateWidget(DeskItemPane old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) _loadComments();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await widget.service.comments(widget.item);
      if (mounted) {
        setState(() {
          _comments = comments;
          _commentsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _commentsError = _deskError(e));
    }
  }

  Future<void> _send(String text) async {
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    final sent = await widget.onAnswer(text.trim());
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final comments = _comments ?? const <DeskComment>[];
    final attachments = [
      for (final c in comments)
        if (c.attachment != null) c.attachment!,
    ];
    final notes = comments.where((c) => c.text.isNotEmpty).toList();
    final meta = [
      item.project,
      if (item.topic.isNotEmpty) item.topic,
      if (item.at != null) deskAge(item.at, widget.now),
      if (item.deadline != null)
        'by ${item.deadline!.month}/${item.deadline!.day}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(meta,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: theme.colorScheme.outline)),
                      ),
                      if (item.priority == DeskPriority.blocking)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text('blocking',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.error)),
                        ),
                      IconButton(
                        tooltip: 'Open in Todoist',
                        icon: const Icon(Icons.open_in_new, size: 20),
                        onPressed: () =>
                            _openLink(AgentDeskService.todoistUrl(item)),
                      ),
                      IconButton(
                        tooltip: 'Close this item',
                        icon: const Icon(Icons.check, size: 20),
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  SelectableText(item.title,
                      style: theme.textTheme.headlineSmall),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Markdown(item.body),
                  ],
                  if (attachments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionLabel('Attachments (${attachments.length})'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in attachments)
                          _AttachmentView(
                              attachment: a, service: widget.service),
                      ],
                    ),
                  ],
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionLabel('Comments (${notes.length})'),
                    for (final c in notes)
                      _CommentView(comment: c, now: widget.now),
                  ],
                  if (_commentsError != null) ...[
                    const SizedBox(height: 12),
                    Text('Attachments and comments: $_commentsError',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (item.isOpen)
          Material(
            elevation: 3,
            color: theme.colorScheme.surfaceContainerLow,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 16, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.options.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final option in item.options)
                                FilledButton.tonal(
                                  onPressed:
                                      _sending ? null : () => _send(option),
                                  child: Text(option),
                                ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              enabled: !_sending,
                              minLines: 1,
                              maxLines: 5,
                              textInputAction: TextInputAction.send,
                              onSubmitted: _send,
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: item.options.isEmpty
                                    ? 'Type or speak your answer'
                                    : 'Or say something else',
                              ),
                            ),
                          ),
                          SpeechInputButton(controller: _controller),
                          IconButton(
                            tooltip: 'Send answer',
                            icon: const Icon(Icons.send),
                            onPressed: _sending
                                ? null
                                : () => _send(_controller.text),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: theme.colorScheme.outline));
  }
}

class _Markdown extends StatelessWidget {
  final String data;
  const _Markdown(this.data);

  @override
  Widget build(BuildContext context) => MarkdownBody(
        data: data,
        selectable: true,
        onTapLink: (_, href, __) {
          if (href != null) _openLink(href);
        },
      );
}

/// An image shows as a thumbnail; anything else, or an image that won't load,
/// as a file button. Both open in the browser.
class _AttachmentView extends StatelessWidget {
  final DeskAttachment attachment;
  final AgentDeskService service;
  const _AttachmentView({required this.attachment, required this.service});

  @override
  Widget build(BuildContext context) {
    final file = OutlinedButton.icon(
      icon: const Icon(Icons.attach_file, size: 18),
      label: Text(attachment.name, overflow: TextOverflow.ellipsis),
      onPressed: () => _openLink(attachment.url),
    );
    if (!attachment.isImage) return file;
    return Tooltip(
      message: attachment.name,
      child: InkWell(
        onTap: () => _openLink(attachment.url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            attachment.url,
            height: 150,
            fit: BoxFit.cover,
            headers: service.headersFor(attachment.url),
            errorBuilder: (_, __, ___) => file,
          ),
        ),
      ),
    );
  }
}

class _CommentView extends StatelessWidget {
  final DeskComment comment;
  final DateTime now;
  const _CommentView({required this.comment, required this.now});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(comment.isAnswer ? Icons.reply : Icons.smart_toy_outlined,
              size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Markdown(comment.text),
                if (comment.at != null)
                  Text(
                      '${comment.isAnswer ? 'You, ' : ''}${deskAge(comment.at, now)}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A project: where it stands, its brief and log, "tell the agent", its items.
class DeskProjectPane extends StatefulWidget {
  final DeskProject project;
  final DateTime now;
  final Future<bool> Function(String text) onInstruct;
  final void Function(DeskItem item) onOpenItem;

  const DeskProjectPane({
    super.key,
    required this.project,
    required this.now,
    required this.onInstruct,
    required this.onOpenItem,
  });

  @override
  State<DeskProjectPane> createState() => _DeskProjectPaneState();
}

class _DeskProjectPaneState extends State<DeskProjectPane> {
  final TextEditingController _instruction = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _instruction.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    final sent = await widget.onInstruct(text.trim());
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) _instruction.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = widget.project;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text(project.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.circle,
                    size: 12,
                    color: deskStateColor(project.state, theme.colorScheme)),
                const SizedBox(width: 8),
                Text(project.state.name, style: theme.textTheme.titleSmall),
                if (project.updatedAt != null)
                  Text(' · ${deskAge(project.updatedAt, widget.now)}',
                      style: theme.textTheme.bodySmall),
                if (project.where.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(deskWhereIcon(project.where),
                      size: 18, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(project.where, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
            if (project.summary.isNotEmpty) ...[
              const SizedBox(height: 10),
              SelectableText(project.summary,
                  style: theme.textTheme.titleMedium),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _instruction,
                        enabled: !_sending,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Tell the agent what to do next',
                        ),
                      ),
                    ),
                    SpeechInputButton(controller: _instruction),
                    IconButton(
                      tooltip: 'Send to agent',
                      icon: const Icon(Icons.send),
                      onPressed: _sending ? null : _send,
                    ),
                  ],
                ),
              ),
            ),
            if (project.brief.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Markdown(project.brief),
            ],
            if (project.open.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionLabel('Open questions (${project.open.length})'),
              for (final item in project.open)
                DeskItemTile(
                  item: item,
                  now: widget.now,
                  onTap: () => widget.onOpenItem(item),
                ),
            ],
            if (project.answered.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionLabel('Answered (${project.answered.length})'),
              for (final item in project.answered)
                DeskItemTile(
                  item: item,
                  now: widget.now,
                  onTap: () => widget.onOpenItem(item),
                ),
            ],
            if (project.instructions.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionLabel(
                  'Your instructions (${project.instructions.length})'),
              for (final item in project.instructions)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.campaign_outlined, size: 20),
                  title: Text(item.title),
                  subtitle: Text(deskAge(item.at, widget.now)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear();

  @override
  Widget build(BuildContext context) => Center(
        child: Text('Nothing is waiting on you.',
            style: Theme.of(context).textTheme.titleMedium),
      );
}

class _EmptyDesk extends StatelessWidget {
  final String? error;
  final VoidCallback onSeed;
  final VoidCallback onRetry;
  const _EmptyDesk({required this.onSeed, required this.onRetry, this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nothing on the desk yet', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'The desk shows every Todoist task with the label agentdesk. '
                  'Set it up with five starter projects (3D builder, photos, '
                  'network, sensitive documents, deals) and the questions '
                  'already known. They are created in your Todoist.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: onSeed,
                      child: const Text('Set up the desk'),
                    ),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: const Text('Check again'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the Todoist token. Saving it doesn't switch the full sync on.
class _ConnectCard extends StatefulWidget {
  final Future<void> Function(String token) onConnect;
  const _ConnectCard({required this.onConnect});

  @override
  State<_ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends State<_ConnectCard> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConnect(_controller.text);
    } catch (e) {
      if (mounted) setState(() => _error = _deskError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect Todoist', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'The desk lives in your Todoist. Paste your API token '
                  '(Todoist: Settings > Integrations > Developer). The desk '
                  'only touches tasks labelled agentdesk; your task list here '
                  'stays as it is and the sync setting is not changed.',
                  style: theme.textTheme.bodyMedium,
                ),
                TextField(
                  controller: _controller,
                  obscureText: true,
                  enabled: !_busy,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: 'API token'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
