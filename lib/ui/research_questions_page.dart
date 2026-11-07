import 'package:flutter/material.dart';

import '../models/task.dart';
import 'speech_input_button.dart';
import 'subpage_app_bar.dart';

/// The research routine's questions for an Active research item
/// ([Task.researchQuestions]), each with an answer field (and the mic
/// button). "Send answers" pops the answers, index-aligned with the
/// questions — an empty one is sent as skipped. Owns its controllers (see
/// `_ProjectEditDialog`'s rule).
class ResearchQuestionsPage extends StatefulWidget {
  final Task task;

  const ResearchQuestionsPage({Key? key, required this.task}) : super(key: key);

  @override
  State<ResearchQuestionsPage> createState() => _ResearchQuestionsPageState();
}

class _ResearchQuestionsPageState extends State<ResearchQuestionsPage> {
  late final List<TextEditingController> _controllers = [
    for (final _ in widget.task.researchQuestions) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _send() =>
      Navigator.of(context).pop([for (final c in _controllers) c.text.trim()]);

  @override
  Widget build(BuildContext context) {
    final questions = widget.task.researchQuestions;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Questions from Claude'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(widget.task.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Answer what you can; leave a field empty to skip it.',
            style: theme.textTheme.bodySmall,
          ),
          for (var i = 0; i < questions.length; i++) ...[
            const SizedBox(height: 16),
            Text('${i + 1}. ${questions[i]}',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('research-answer-$i'),
                    controller: _controllers[i],
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Answer'),
                  ),
                ),
                SpeechInputButton(controller: _controllers[i]),
              ],
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _send,
        icon: const Icon(Icons.send),
        label: const Text('Send answers'),
      ),
    );
  }
}
