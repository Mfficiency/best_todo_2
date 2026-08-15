import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../config.dart';
import '../services/permission_flow.dart';

/// The chooser between the two ways to run the app: *simple mode* (the plain
/// task list, nothing else) and *full mode* (every tool and extra), without a
/// [Scaffold] of its own so it can be the closing page of the intro as well as
/// a standalone page.
class ModeSelectView extends StatelessWidget {
  final VoidCallback onModeSelected;
  const ModeSelectView({super.key, required this.onModeSelected});

  Future<void> _choose(bool simple) async {
    Config.simpleMode = simple;
    Config.modeChosen = true;
    await Config.save();
    if (simple) {
      // No dialogs for the plain list; record the version so the next open
      // is not treated as the first open after an update.
      unawaited(PermissionFlow.markVersionHandled());
    } else {
      // The full experience: ask for every permission right away, over
      // whatever page opens next.
      unawaited(PermissionFlow.requestAll(trigger: 'full mode chosen'));
    }
    onModeSelected();
  }

  Widget _modeCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> bullets,
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
              ...bullets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('· '),
                      Expanded(
                        child: Text(b, style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How do you want to use BestToDo?',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You can switch any time in Settings.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _modeCard(
                context,
                icon: Icons.check_circle_outline,
                title: 'Simple mode',
                subtitle: 'Just the to-do list — nothing else on screen.',
                bullets: const [
                  'The task list with its day tabs',
                  'No tools, no streak, no extra buttons',
                  'Best if you only want to write down tasks',
                ],
                buttonLabel: 'Start simple',
                onTap: () => _choose(true),
              ),
              const SizedBox(height: 16),
              _modeCard(
                context,
                icon: Icons.widgets_outlined,
                title: 'Full mode',
                subtitle: 'The complete app with every tool.',
                bullets: const [
                  'Alarms, countdown, projects, wishlist, Chronize',
                  'Streak flame, dice timer, schedule view, stats',
                  'Pick exactly which features you want in Settings',
                ],
                buttonLabel: 'Use everything',
                onTap: () => _choose(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standalone version of [ModeSelectView], used when only the mode question is
/// asked again (Settings → Mode & features → "Show the mode picker again").
/// On a first launch the same chooser closes the intro instead.
class ModeSelectPage extends StatelessWidget {
  final VoidCallback onModeSelected;
  const ModeSelectPage({super.key, required this.onModeSelected});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ModeSelectView(onModeSelected: onModeSelected),
      ),
    );
  }
}
