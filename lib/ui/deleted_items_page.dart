import 'package:flutter/material.dart';
import '../models/task.dart';

class DeletedItemsPage extends StatelessWidget {
  final List<Task> items;
  const DeletedItemsPage({Key? key, required this.items}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deleted Items')),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final task = items[index];
          return ListTile(
            title: Text(task.title),
            subtitle: task.description.isNotEmpty ? Text(task.description) : null,
          );
        },
      ),
    );
  }
}
