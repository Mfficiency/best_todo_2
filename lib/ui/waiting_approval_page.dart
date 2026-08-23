import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/log_service.dart';
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

  Future<void> _save() => _repository.saveItems(_tasks);

  List<Task> _pending() => ItemViews.waitingApproval(_tasks);

  /// Removes [waitingApprovalToken], making the task visible wherever it
  /// belongs (today's list, a project, the wishlist, ...).
  void _approve(Task task) {
    setState(() {
      task.label = removeLabelToken(task.label, waitingApprovalToken);
    });
    _save();
    LogService.add('WaitingApprovalPage._approve', 'Approved "${task.title}"');
  }

  /// Denies the task by deleting it outright (soft-delete, same as swiping a
  /// task away elsewhere — recoverable from Deleted Items).
  Future<void> _deny(Task task) async {
    setState(() {
      _tasks.remove(task);
    });
    task.deletedAt = DateTime.now();
    task.autoDeleted = false;
    final deleted = await _repository.loadDeletedItems();
    deleted.insert(0, task);
    if (deleted.length > 100) deleted.removeLast();
    await _repository.saveDeletedItems(deleted);
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
