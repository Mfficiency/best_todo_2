import 'package:flutter/material.dart';

import '../config.dart';
import '../models/alarm.dart';
import '../services/alarm_sound.dart';
import '../services/alarm_vibration.dart';

/// The dice timer's own settings — how it alerts at zero (melody + volume,
/// vibration, notification or completely silent) and how far the dial is
/// pre-wound. Rendered as bare tiles so the caller supplies the surround: the
/// Settings page drops it into its "Dice timer" card, the timer page into a
/// bottom sheet behind the app-bar gear.
///
/// Every change writes straight through to [Config] and persists, then calls
/// [onChanged] — there is no Save button, matching the rest of Settings.
class DiceTimerSettingsList extends StatefulWidget {
  /// Called after a change has been saved (so a host page can rebuild).
  final VoidCallback? onChanged;

  const DiceTimerSettingsList({Key? key, this.onChanged}) : super(key: key);

  @override
  State<DiceTimerSettingsList> createState() => _DiceTimerSettingsListState();
}

class _DiceTimerSettingsListState extends State<DiceTimerSettingsList> {
  String _mode = Config.diceTimerAlertMode;
  String _melody = Config.diceTimerMelody;
  double _volume = Config.diceTimerVolume;
  bool _alsoVibrate = Config.diceTimerAlsoVibrate;
  int _defaultMinutes = Config.diceTimerDefaultMinutes;

  /// Whether the melody preview is currently playing.
  bool _previewing = false;

  @override
  void dispose() {
    if (_previewing) AlarmSound.stop();
    super.dispose();
  }

  Future<void> _save() async {
    await Config.save();
    widget.onChanged?.call();
  }

  /// Plays the chosen melody exactly the way the timer will ring it — same
  /// melody, same absolute loudness — so both can be judged before committing.
  Future<void> _togglePreview() async {
    if (_previewing) {
      setState(() => _previewing = false);
      await AlarmSound.stop();
      return;
    }
    setState(() => _previewing = true);
    await AlarmSound.play(melody: _melody, volume: _volume, loop: true);
  }

  /// While the preview is playing, apply melody/volume changes to it live.
  Future<void> _refreshPreview() async {
    if (!_previewing) return;
    await AlarmSound.play(melody: _melody, volume: _volume, loop: true);
  }

  /// A one-shot buzz so "Vibration" can be felt before it is chosen for real.
  Future<void> _previewVibration() async {
    await AlarmVibration.start();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await AlarmVibration.stop();
  }

  String get _modeDescription {
    final index = Config.diceTimerAlertModes.indexOf(_mode);
    if (index < 0) return '';
    if (_mode == 'notification' && !Config.enableNotifications) {
      return 'Notifications are switched off, so the timer will just show '
          '0:00 at zero';
    }
    return Config.diceTimerAlertDescriptions[index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: const Text('Alert at zero'),
          subtitle: Text(_modeDescription),
          trailing: DropdownButton<String>(
            value: Config.diceTimerAlertModes.contains(_mode)
                ? _mode
                : Config.diceTimerAlertModes.first,
            items: [
              for (var i = 0; i < Config.diceTimerAlertModes.length; i++)
                DropdownMenuItem<String>(
                  value: Config.diceTimerAlertModes[i],
                  child: Text(Config.diceTimerAlertLabels[i]),
                ),
            ],
            onChanged: (val) async {
              if (val == null) return;
              if (_previewing) {
                setState(() => _previewing = false);
                await AlarmSound.stop();
              }
              setState(() => _mode = val);
              Config.diceTimerAlertMode = val;
              await _save();
            },
          ),
        ),
        if (_mode == 'melody') ...[
          ListTile(
            title: const Text('Melody'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: kAlarmMelodies.contains(_melody)
                      ? _melody
                      : kAlarmMelodies.first,
                  items: [
                    for (final melody in kAlarmMelodies)
                      DropdownMenuItem<String>(
                        value: melody,
                        child: Text(melody),
                      ),
                  ],
                  onChanged: (val) async {
                    if (val == null) return;
                    setState(() => _melody = val);
                    Config.diceTimerMelody = val;
                    await _refreshPreview();
                    await _save();
                  },
                ),
                IconButton(
                  icon: Icon(_previewing ? Icons.stop : Icons.play_arrow),
                  tooltip: _previewing ? 'Stop preview' : 'Preview melody',
                  onPressed: _togglePreview,
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('Volume'),
            subtitle: Row(
              children: [
                const Icon(Icons.volume_up, size: 20),
                Expanded(
                  child: Slider(
                    value: _volume.clamp(0.0, 1.0),
                    onChanged: (val) => setState(() => _volume = val),
                    onChangeEnd: (val) async {
                      Config.diceTimerVolume = val;
                      await _refreshPreview();
                      await _save();
                    },
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(_volume * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_mode == 'vibrate')
          ListTile(
            title: const Text('Try the vibration'),
            subtitle: const Text('Buzzes once so you know what to expect'),
            trailing: const Icon(Icons.vibration),
            onTap: _previewVibration,
          ),
        if (_mode == 'melody' || _mode == 'notification')
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Also vibrate'),
            subtitle: const Text('Buzz along with the alert at zero'),
            value: _alsoVibrate,
            onChanged: (val) async {
              setState(() => _alsoVibrate = val);
              Config.diceTimerAlsoVibrate = val;
              await _save();
            },
          ),
        ListTile(
          title: const Text('Default timer length'),
          subtitle: const Text('Where the dial sits when a fresh timer opens'),
          trailing: DropdownButton<int>(
            value: Config.diceTimerLengthOptions.contains(_defaultMinutes)
                ? _defaultMinutes
                : 20,
            items: [
              for (final minutes in Config.diceTimerLengthOptions)
                DropdownMenuItem<int>(
                  value: minutes,
                  child: Text('$minutes min'),
                ),
            ],
            onChanged: (val) async {
              if (val == null) return;
              setState(() => _defaultMinutes = val);
              Config.diceTimerDefaultMinutes = val;
              await _save();
            },
          ),
        ),
      ],
    );
  }
}
