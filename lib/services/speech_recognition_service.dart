import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'log_service.dart';

/// Thin wrapper around the `speech_to_text` plugin (on-device speech
/// recognition — no server round-trip) so UI code depends on this small
/// surface instead of the vendor API directly. [instance] is reassignable so
/// widget tests can swap in a fake, the same pattern `PathProviderPlatform`
/// fakes use elsewhere in this repo.
class SpeechRecognitionService {
  static SpeechRecognitionService instance = SpeechRecognitionService();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _initialized = false;
  VoidCallback? _onDone;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (error) => LogService.add(
          'SpeechRecognitionService', 'Error: ${error.errorMsg}'),
      onStatus: (status) {
        LogService.add('SpeechRecognitionService', 'Status: $status');
        // The session can end on its own (silence timeout, error, the
        // listenFor cap) without the widget ever calling stop() — tell it so
        // its "recording" UI state doesn't get stuck.
        if (!_speech.isListening) _onDone?.call();
      },
    );
    return _initialized;
  }

  bool get isListening => _speech.isListening;

  /// Starts a listening session. [onResult] fires with the full recognized
  /// text of the session so far each time it updates — the caller decides
  /// how to merge that into whatever text already existed. [onDone] fires
  /// once the session ends on its own, so the caller can drop its own
  /// "recording" state without waiting for an explicit stop. Returns false
  /// if speech recognition isn't available on this device or permission was
  /// denied.
  Future<bool> listen({
    required void Function(String text) onResult,
    VoidCallback? onDone,
  }) async {
    final available = await _ensureInitialized();
    if (!available) return false;
    _onDone = onDone;
    await _speech.listen(
      onResult: (result) => onResult(result.recognizedWords),
      listenFor: const Duration(minutes: 3),
    );
    return true;
  }

  Future<void> stop() => _speech.stop();
}
