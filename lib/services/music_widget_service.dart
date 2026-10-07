import 'package:home_widget/home_widget.dart';

import 'music_audio_handler.dart';

/// Bridges live playback state to the two Music Player home-screen widgets:
/// a minimal play/pause-only widget and a play/pause + skip-previous one.
/// The widgets' own buttons don't come back through here — they send real
/// Android media-button broadcasts straight to `audio_service`'s
/// `MediaButtonReceiver` (see the native widget providers), the same path a
/// Bluetooth headset button uses. This service only keeps their title and
/// play/pause icon in sync with what's actually playing.
class MusicWidgetService {
  MusicWidgetService._();

  static const String appGroupId = 'group.homeScreenApp';
  static const String miniWidgetName = 'MusicMiniWidgetProvider';
  static const String controlsWidgetName = 'MusicControlsWidgetProvider';

  /// URI scheme/host the widgets use for taps that should open the app
  /// (their transport buttons instead send real media-button broadcasts —
  /// see the native widget providers — so they work without opening it).
  static const String scheme = 'besttodomusic';
  static const String hostOpen = 'open';

  static bool _attached = false;

  static Future<void> _ready() async {
    await HomeWidget.setAppGroupId(appGroupId).catchError((_) => false);
  }

  /// Starts pushing [handler]'s now-playing state to the widgets. Safe to
  /// call more than once — only the first call subscribes.
  static void attach(MusicAudioHandler handler) {
    if (_attached) return;
    _attached = true;
    handler.mediaItem.listen((_) => _sync(handler));
    handler.playbackState.listen((_) => _sync(handler));
  }

  static Future<void> _sync(MusicAudioHandler handler) async {
    try {
      await _ready();
      final item = handler.mediaItem.valueOrNull;
      final playing = handler.playbackState.valueOrNull?.playing ?? false;
      await HomeWidget.saveWidgetData<String>(
          'music_widget_title', item?.title ?? '');
      await HomeWidget.saveWidgetData<String>(
          'music_widget_artist', item?.artist ?? '');
      await HomeWidget.saveWidgetData<bool>('music_widget_playing', playing);
      await HomeWidget.saveWidgetData<bool>(
          'music_widget_has_track', item != null);
      await HomeWidget.updateWidget(androidName: miniWidgetName);
      await HomeWidget.updateWidget(androidName: controlsWidgetName);
    } catch (_) {}
  }
}
