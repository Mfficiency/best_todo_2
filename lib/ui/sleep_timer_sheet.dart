import 'package:flutter/material.dart';

import '../services/music_sleep_timer.dart';

/// Preset sleep timer lengths, in minutes.
const sleepTimerPresets = [5, 10, 15, 30, 45, 60, 90];

/// The one sleep timer picker, opened from Now Playing, the mini player,
/// Best Music's drawer and Settings — all driving [MusicSleepTimer].
Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ValueListenableBuilder<SleepTimerState>(
        valueListenable: MusicSleepTimer.instance.state,
        builder: (context, state, _) {
          final timer = MusicSleepTimer.instance;
          void pick(VoidCallback action) {
            action();
            Navigator.of(sheetContext).pop();
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.bedtime_outlined),
                  title: Text('Sleep timer',
                      style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text(state.isActive
                      ? (state.endOfTrack
                          ? 'Pauses at the end of this song'
                          : 'Pauses in ${MusicSleepTimer.describe(state)}')
                      : 'Pause playback after a while'),
                ),
                if (state.isActive) ...[
                  if (state.endsAt != null)
                    ListTile(
                      leading: const Icon(Icons.more_time),
                      title: const Text('Add 10 minutes'),
                      onTap: () => pick(
                          () => timer.extend(const Duration(minutes: 10))),
                    ),
                  ListTile(
                    leading: const Icon(Icons.timer_off_outlined),
                    title: const Text('Turn off sleep timer'),
                    onTap: () => pick(timer.cancel),
                  ),
                  const Divider(height: 1),
                ],
                for (final minutes in sleepTimerPresets)
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(minutes >= 60 && minutes % 60 == 0
                        ? '${minutes ~/ 60} hour'
                        : '$minutes minutes'),
                    onTap: () =>
                        pick(() => timer.start(Duration(minutes: minutes))),
                  ),
                ListTile(
                  leading: const Icon(Icons.music_off_outlined),
                  title: const Text('End of current song'),
                  selected: state.endOfTrack,
                  onTap: () => pick(timer.startEndOfTrack),
                ),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Custom…'),
                  onTap: () async {
                    final minutes = await showDialog<int>(
                      context: sheetContext,
                      builder: (_) => const _CustomMinutesDialog(),
                    );
                    if (minutes != null && minutes > 0) {
                      timer.start(Duration(minutes: minutes));
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// App-bar button for the sleep timer: a bedtime icon, highlighted with
/// the time left while a timer runs.
class SleepTimerButton extends StatelessWidget {
  const SleepTimerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SleepTimerState>(
      valueListenable: MusicSleepTimer.instance.state,
      builder: (context, state, _) => IconButton(
        icon: Icon(state.isActive ? Icons.bedtime : Icons.bedtime_outlined),
        color: state.isActive ? Theme.of(context).colorScheme.primary : null,
        tooltip: state.isActive
            ? 'Sleep timer: ${MusicSleepTimer.describe(state)}'
            : 'Sleep timer',
        onPressed: () => showSleepTimerSheet(context),
      ),
    );
  }
}

/// Owns its controller (see CLAUDE.md: never dispose a dialog's controller
/// right after showDialog returns).
class _CustomMinutesDialog extends StatefulWidget {
  const _CustomMinutesDialog();

  @override
  State<_CustomMinutesDialog> createState() => _CustomMinutesDialogState();
}

class _CustomMinutesDialogState extends State<_CustomMinutesDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop(int.tryParse(_controller.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sleep timer'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Minutes'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Start')),
      ],
    );
  }
}
