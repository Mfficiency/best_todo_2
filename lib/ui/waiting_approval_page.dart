import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/log_service.dart';
import '../services/task_widget_service.dart';
import '../utils/label_utils.dart';
import '../utils/linkified_text.dart';
import 'subpage_app_bar.dart';

/// Tasks pulled in via the Todoist workflow land here first — tagged with
/// [waitingApprovalToken] and hidden from every other list (home tabs,
/// wishlist, project boards; see `ItemViews`) — until approved or denied.
///
/// Self-contained like [WishlistPage]: loads and saves the whole task list
/// on its own, so the home page just reloads from storage when coming back
/// (see `HomePage._reloadTasksFromStorage`).
class WaitingApprovalPage extends StatefulWidget {
  const WaitingApprovalPage({Key? key}) : super(key: key);

  @override
  State<WaitingApprovalPage> createState() => _WaitingApprovalPageState();
}

class _WaitingApprovalPageState extends State<WaitingApprovalPage> {
  final ItemRepository _repository = ItemRepository.instance;

  /// The full task list; the page shows and mutates only the pending subset
  /// but always persists the whole list.
  List<Task> _tasks = <Task>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _repository.loadItems();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  /// Persists the list and redraws the home-screen widget from it — the
  /// widget is a view of the same list, so a denied task has to leave it
  /// too (the home page only pushes on its own saves).
  Future<void> _save() async {
    await _repository.saveItems(_tasks);
    await TaskWidgetService.sync(_tasks);
  }

  List<Task> _pending() => ItemViews.waitingApproval(
        _tasks,
        rules: Config.viewFilterRules[ViewFilterRules.approval],
      );

  /// Removes [waitingApprovalToken] (and its legacy spellings), making the
  /// task visible wherever it belongs (today's list, a project, the
  /// wishlist, ...). The next Todoist sync pushes the shortened label array,
  /// so the tag disappears on the Todoist side too.
  void _approve(Task task) {
    setState(() {
      task.label = removeWaitingApprovalToken(task.label);
    });
    _save();
    LogService.add('WaitingApprovalPage._approve', 'Approved "${task.title}"');
  }

  /// Denies the task by sending it straight to the real Deleted bin — unlike
  /// a normal delete elsewhere in the app (which only archives), a denial was
  /// never wanted in the first place, so it skips the archive and starts
  /// aging toward permanent purge right away (recoverable from the bin until
  /// then).
  Future<void> _deny(Task task) async {
    setState(() {
      _tasks.remove(task);
    });
    task.deletedAt = DateTime.now();
    task.autoDeleted = false;
    final binned = await _repository.loadBinItems();
    binned.insert(0, task);
    if (binned.length > 100) binned.removeLast();
    await _repository.saveBinItems(binned);
    await _save();
    LogService.add('WaitingApprovalPage._deny', 'Denied "${task.title}"');
  }

  @override
  Widget build(BuildContext context) {
    final pending = _loading ? <Task>[] : _pending();
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Waiting for Approval'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pending.isEmpty
              ? const Center(child: Text('Nothing waiting for approval'))
              : ListView.builder(
                  itemCount: pending.length,
                  itemBuilder: (context, index) {
                    final task = pending[index];
                    return ListTile(
                      title: LinkifiedText(task.title),
                      subtitle: task.description.isNotEmpty
                          ? LinkifiedText(task.description)
                          : null,
                      isThreeLine: task.description.isNotEmpty,
                      leading: IconButton(
                        icon: const Icon(Icons.check_circle_outline),
                        tooltip: 'Approve',
                        color: Colors.green,
                        onPressed: () => _approve(task),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Deny',
                        color: Theme.of(context).colorScheme.error,
                        onPressed: () => _deny(task),
                      ),
                    );
                  },
                ),
    );
  }
}
