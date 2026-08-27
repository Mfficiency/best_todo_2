import 'package:flutter/material.dart';

import '../services/speech_recognition_service.dart';

/// Mic button that sits beside a text field: first tap starts local
/// speech-to-text, second tap stops it. The transcription is written
/// straight into [controller], appended after whatever was already there,
/// and stays fully editable — nothing here submits or closes anything, it
/// only ever touches the text.
class SpeechInputButton extends StatefulWidget {
  final TextEditingController controller;

  const SpeechInputButton({super.key, required this.controller});

  @override
  State<SpeechInputButton> createState() => _SpeechInputButtonState();
}

class _SpeechInputButtonState extends State<SpeechInputButton> {
  bool _listening = false;
  String _baseText = '';

  @override
  void dispose() {
    if (_listening) SpeechRecognitionService.instance.stop();
    super.dispose();
  }

  void _applyTranscript(String transcript) {
    if (!mounted) return;
    final combined = _baseText.isEmpty
        ? transcript
        : (transcript.isEmpty ? _baseText : '$_baseText $transcript');
    widget.controller.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
  }

  Future<void> _toggle() async {
    if (_listening) {
      await SpeechRecognitionService.instance.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    _baseText = widget.controller.text;
    final started = await SpeechRecognitionService.instance.listen(
      onResult: _applyTranscript,
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Speech recognition is not available on this device'),
        ),
      );
      return;
    }
    setState(() => _listening = true);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening ? 'Stop recording' : 'Speak instead of typing',
      icon: Icon(
        _listening ? Icons.mic : Icons.mic_none,
        color: _listening ? Colors.red : null,
      ),
      onPressed: _toggle,
    );
  }
}
