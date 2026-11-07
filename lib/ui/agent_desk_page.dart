import 'dart:async';

import 'package:flutter/material.dart';

import '../models/agent_desk.dart';
import '../services/agent_desk_service.dart';
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

/// Tools → Agent Desk (SPEC §10.6s): the three decisions the background
/// agents need from you on top, every project below. Answer by tapping a
/// suggested answer, typing or speaking; the answer is appended to the
/// project's decisions file in the desk folder, where the project's agent
/// picks it up. Meant as the start page on the PCs (Settings → Default start
/// page → Agent Desk), so it is the first thing seen at logon.
class AgentDeskPage extends StatefulWidget {
  final AgentDeskService? service;

  /// How often the folder is re-read for new questions and status; null
  /// turns polling off (tests).
  final Duration? pollInterval;
  final DateTime Function()? clock;

  const AgentDeskPage({
    super.key,
    this.service,
    this.pollInterval = const Duration(seconds: 15),
    this.clock,
  });

  @override
  State<AgentDeskPage> createState() => _AgentDeskPageState();
}

class _AgentDeskPageState extends State<AgentDeskPage> {
  AgentDeskService get _service => widget.service ?? AgentDeskService.instance;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  DeskSnapshot? _snapshot;
  String _folder = '';
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _reload();
    final every = widget.pollInterval;
    if (every != null) {
      _poll = Timer.periodic(every, (_) => _reload(quiet: true));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final folder = await _service.folder();
      final snapshot = await _service.load();
      if (!mounted) return;
      setState(() {
        _folder = folder;
        _snapshot = snapshot;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _answer(DeskQuestion q, String text, String via) async {
    await _sendDecision(
      projectId: q.projectId,
      text: text,
      questionId: q.id,
      topic: q.topic,
      via: via,
    );
  }

  Future<void> _sendDecision({
    required String projectId,
    required String text,
    String? questionId,
    String topic = '',
    String via = 'text',
  }) async {
    if (text.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = _snapshot?.project(projectId)?.name ?? projectId;
    try {
      await _service.decide(
        projectId: projectId,
        text: text,
        questionId: questionId,
        topic: topic,
        via: via,
      );
      messenger.showSnackBar(SnackBar(content: Text('Sent to $name')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
    await _reload(quiet: true);
  }

  Future<void> _chooseFolder() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _FolderDialog(initial: _folder),
    );
    if (result == null) return;
    await _service.setFolder(result);
    await _reload();
  }

  Future<void> _seed() async {
    try {
      await _service.seed();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not create the folder: $e')));
      }
    }
    await _reload();
  }

  Future<void> _openProject(DeskProject project) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AgentDeskProjectPage(
        projectId: project.id,
        service: _service,
        clock: widget.clock,
        pollInterval: widget.pollInterval,
      ),
    ));
    await _reload(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Agent Desk',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _reload(),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Desk folder',
            onPressed: _chooseFolder,
          ),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return _SetupCard(
        folder: _folder,
        error: _error,
        onSeed: _seed,
        onChooseFolder: _chooseFolder,
      );
    }
    final theme = Theme.of(context);
    final top = snapshot.topQuestions();
    final allOpen = snapshot.openQuestions;
    final laterCount =
        allOpen.where((q) => q.priority == DeskPriority.later).length;
    final waitingCount = allOpen.length - laterCount - top.length;
    return RefreshIndicator(
      onRefresh: _reload,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _SectionTitle(
              'Decide now',
              trailing: waitingCount > 0
                  ? '+$waitingCount more waiting'
                  : (laterCount > 0 ? '$laterCount for later' : null),
            ),
            if (top.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Nothing is waiting on you.'),
                  subtitle: laterCount > 0
                      ? Text('$laterCount question(s) parked for later, on '
                          'the project pages.')
                      : null,
                ),
              )
            else if (wide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < top.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                          child: _questionCard(snapshot, top[i], i + 1,
                              fillHeight: true)),
                    ],
                    for (var i = top.length; i < 3; i++) ...[
                      const SizedBox(width: 12),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ],
                ),
              )
            else
              for (var i = 0; i < top.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _questionCard(snapshot, top[i], i + 1),
                ),
            const SizedBox(height: 20),
            _SectionTitle('Projects',
                trailing: '${snapshot.projects.length} in $_folder'),
            if (snapshot.projects.isEmpty)
              Text('No project folders yet in $_folder.',
                  style: theme.textTheme.bodyMedium),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final p in snapshot.projects)
                  SizedBox(
                    width: wide
                        ? (constraints.maxWidth - 32 - 12) / 2
                        : constraints.maxWidth - 32,
                    child: _ProjectCard(
                      project: p,
                      now: _now(),
                      onTap: () => _openProject(p),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _questionCard(DeskSnapshot snapshot, DeskQuestion q, int rank,
      {bool fillHeight = false}) {
    return DeskQuestionCard(
      fillHeight: fillHeight,
      key: ValueKey('desk-q-${q.projectId}-${q.id}'),
      question: q,
      projectName: snapshot.project(q.projectId)?.name ?? q.projectId,
      rank: rank,
      now: _now(),
      onAnswer: (text, via) => _answer(q, text, via),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionTitle(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary)),
          const SizedBox(width: 12),
          if (trailing != null)
            Expanded(
              child: Text(trailing!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
        ],
      ),
    );
  }
}

/// One question with its suggested answers and a type/speak box. Owns its
/// text controller (CLAUDE.md: never dispose one a parent rebuild may still
/// use).
class DeskQuestionCard extends StatefulWidget {
  final DeskQuestion question;
  final String projectName;
  final int? rank;
  final DateTime now;
  final void Function(String text, String via) onAnswer;

  /// True when the card sits in a row of equal-height cards: the answer box
  /// is pushed to the bottom so the three boxes line up.
  final bool fillHeight;

  const DeskQuestionCard({
    super.key,
    required this.question,
    required this.projectName,
    required this.now,
    required this.onAnswer,
    this.rank,
    this.fillHeight = false,
  });

  @override
  State<DeskQuestionCard> createState() => _DeskQuestionCardState();
}

class _DeskQuestionCardState extends State<DeskQuestionCard> {
  final TextEditingController _controller = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(String text, String via) {
    if (text.trim().isEmpty || _sent) return;
    setState(() => _sent = true);
    widget.onAnswer(text.trim(), via);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    final meta = [
      widget.projectName,
      if (q.topic.isNotEmpty) q.topic,
      if (q.at != null) deskAge(q.at, widget.now),
    ].join(' · ');
    return Card(
      shape: q.priority == DeskPriority.blocking
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.error, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (widget.rank != null) ...[
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text('${widget.rank}',
                        style: theme.textTheme.labelMedium),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(meta,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
                if (q.priority == DeskPriority.blocking)
                  Text('blocking',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.error)),
                if (q.deadline != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8),
                    child: Text(
                        'by ${q.deadline!.month}/${q.deadline!.day}',
                        style: theme.textTheme.labelSmall),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(q.text, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            if (q.options.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final option in q.options)
                    FilledButton.tonal(
                      onPressed: _sent ? null : () => _send(option, 'option'),
                      child: Text(option),
                    ),
                ],
              ),
            widget.fillHeight ? const Spacer() : const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_sent,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (t) => _send(t, 'text'),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _sent
                          ? 'Sent'
                          : (q.options.isEmpty
                              ? 'Type or speak your answer'
                              : 'Or say something else'),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                SpeechInputButton(controller: _controller),
                IconButton(
                  tooltip: 'Send answer',
                  icon: const Icon(Icons.send),
                  onPressed: _sent ? null : () => _send(_controller.text, 'text'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final DeskProject project;
  final DateTime now;
  final VoidCallback onTap;
  const _ProjectCard(
      {required this.project, required this.now, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = project.openQuestions;
    final urgent = open.where((q) => q.priority != DeskPriority.later).length;
    final later = open.length - urgent;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle,
                      size: 12,
                      color: deskStateColor(project.state, theme.colorScheme)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(project.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  Tooltip(
                    message: 'Runs on: ${project.where.isEmpty ? 'not set' : project.where}',
                    child: Icon(deskWhereIcon(project.where),
                        size: 18, color: theme.colorScheme.outline),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                project.summary.isNotEmpty ? project.summary : project.goal,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(project.state.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: deskStateColor(
                              project.state, theme.colorScheme))),
                  if (project.updatedAt != null)
                    Text(' · ${deskAge(project.updatedAt, now)}',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.outline)),
                  const Spacer(),
                  if (urgent > 0)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('$urgent open'),
                    ),
                  if (later > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('$later later',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: theme.colorScheme.outline)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  final String folder;
  final String? error;
  final VoidCallback onSeed;
  final VoidCallback onChooseFolder;
  const _SetupCard({
    required this.folder,
    required this.onSeed,
    required this.onChooseFolder,
    this.error,
  });

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
                Text('No desk yet', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'The Agent Desk reads a folder that the agents write their '
                  'questions to. There is none at:\n$folder\n\n'
                  'Set it up with the five starter projects (3D builder, '
                  'photos, network, sensitive documents, deals) and the '
                  'questions already known, or point it at the folder '
                  'another PC syncs.',
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
                      onPressed: onChooseFolder,
                      child: const Text('Choose folder'),
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

class _FolderDialog extends StatefulWidget {
  final String initial;
  const _FolderDialog({required this.initial});

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Desk folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The folder the agents write to. Leave empty for the '
              'default (D:\\AgentDesk on a PC with a D: drive).'),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Folder'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One project: its status, an "instruct the agent" box, every open
/// question (the parked ones under Later), your recent decisions and the end
/// of the agent's log.
class AgentDeskProjectPage extends StatefulWidget {
  final String projectId;
  final AgentDeskService? service;
  final Duration? pollInterval;
  final DateTime Function()? clock;

  const AgentDeskProjectPage({
    super.key,
    required this.projectId,
    this.service,
    this.pollInterval = const Duration(seconds: 15),
    this.clock,
  });

  @override
  State<AgentDeskProjectPage> createState() => _AgentDeskProjectPageState();
}

class _AgentDeskProjectPageState extends State<AgentDeskProjectPage> {
  AgentDeskService get _service => widget.service ?? AgentDeskService.instance;
  DateTime _now() => (widget.clock ?? DateTime.now)();

  DeskProject? _project;
  bool _loading = true;
  Timer? _poll;
  final TextEditingController _instruction = TextEditingController();
  String _topic = '';

  @override
  void initState() {
    super.initState();
    _reload();
    final every = widget.pollInterval;
    if (every != null) {
      _poll = Timer.periodic(every, (_) => _reload());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final snapshot = await _service.load();
      if (!mounted) return;
      setState(() => _project = snapshot?.project(widget.projectId));
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(String text,
      {String? questionId, String topic = '', String via = 'text'}) async {
    if (text.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.decide(
        projectId: widget.projectId,
        text: text,
        questionId: questionId,
        topic: topic,
        via: via,
      );
      messenger.showSnackBar(SnackBar(
          content: Text('Sent to ${_project?.name ?? widget.projectId}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
    await _reload();
  }

  void _sendInstruction() {
    final text = _instruction.text;
    if (text.trim().isEmpty) return;
    _instruction.clear();
    _decide(text, topic: _topic);
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: project?.name ?? 'Project',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _reload,
          ),
        ],
      ),
      body: project == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('This project is no longer on the desk.'))
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: _body(context, project),
              ),
            ),
    );
  }

  Widget _body(BuildContext context, DeskProject project) {
    final theme = Theme.of(context);
    final now = _now();
    final open = project.openQuestions;
    final current = open.where((q) => q.priority != DeskPriority.later).toList();
    final later = open.where((q) => q.priority == DeskPriority.later).toList();
    final recent = project.decisions.reversed.take(10).toList();
    final questionText = {for (final q in project.questions) q.id: q.text};
    final topics = project.topics;
    Widget card(DeskQuestion q) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DeskQuestionCard(
            key: ValueKey('desk-pq-${q.id}'),
            question: q,
            projectName: project.name,
            now: now,
            onAnswer: (text, via) => _decide(text,
                questionId: q.id, topic: q.topic, via: via),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Icon(Icons.circle,
                size: 12, color: deskStateColor(project.state, theme.colorScheme)),
            const SizedBox(width: 8),
            Text(project.state.name, style: theme.textTheme.titleSmall),
            if (project.updatedAt != null)
              Text(' · ${deskAge(project.updatedAt, now)}',
                  style: theme.textTheme.bodySmall),
            const Spacer(),
            Icon(deskWhereIcon(project.where),
                size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text(project.where, style: theme.textTheme.bodySmall),
          ],
        ),
        if (project.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(project.summary, style: theme.textTheme.bodyLarge),
        ],
        if (project.goal.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(project.goal,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline)),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                if (topics.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: DropdownButton<String>(
                      value: _topic,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('General')),
                        for (final t in topics)
                          DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (v) => setState(() => _topic = v ?? ''),
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: _instruction,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendInstruction(),
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
                  onPressed: _sendInstruction,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionTitle('Open questions', trailing: '${current.length}'),
        if (current.isEmpty)
          Text('None.', style: theme.textTheme.bodyMedium),
        for (final q in current) card(q),
        if (later.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionTitle('Later', trailing: '${later.length} parked'),
          for (final q in later) card(q),
        ],
        const SizedBox(height: 12),
        _SectionTitle('Your decisions', trailing: recent.isEmpty ? null : 'newest first'),
        if (recent.isEmpty) Text('None yet.', style: theme.textTheme.bodyMedium),
        for (final d in recent)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(d.questionId == null ? Icons.campaign_outlined : Icons.reply,
                size: 20),
            title: Text(d.text),
            subtitle: Text([
              if (d.questionId != null && questionText[d.questionId] != null)
                questionText[d.questionId]!,
              if (d.topic.isNotEmpty && d.questionId == null) d.topic,
              '${deskAge(d.at, now)}${d.device.isEmpty ? '' : ' on ${d.device}'}',
            ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        const SizedBox(height: 12),
        const _SectionTitle('Agent log'),
        if (project.logTail.isEmpty)
          Text('Empty.', style: theme.textTheme.bodyMedium)
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              project.logTail.join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
      ],
    );
  }
}
