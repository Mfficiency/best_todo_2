import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders [text] like a plain [Text], but with http/https URLs underlined
/// and tappable (opened in the external browser). A tapped link wins the
/// gesture arena over ancestor tap targets, so linkified text is safe inside
/// a [ListTile] that has its own `onTap`.
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Test/override hook; defaults to launching the URL externally.
  final void Function(Uri uri)? onOpenLink;

  const LinkifiedText(this.text, {Key? key, this.style, this.onOpenLink})
      : super(key: key);

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  static final RegExp _urlPattern = RegExp(r'https?://\S+');

  /// Recognizers of the spans built last; span recognizers are not widgets,
  /// so the state owns and disposes them.
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  /// Trailing sentence punctuation belongs to the prose, not the URL.
  static String _withoutTrailingPunctuation(String url) {
    var end = url.length;
    while (end > 0 && '.,;:!?)"\''.contains(url[end - 1])) {
      end--;
    }
    return url.substring(0, end);
  }

  void _open(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final onOpenLink = widget.onOpenLink;
    if (onOpenLink != null) {
      onOpenLink(uri);
    } else {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final text = widget.text;
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in _urlPattern.allMatches(text)) {
      final url = _withoutTrailingPunctuation(match.group(0)!);
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: url,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        recognizer: recognizer,
      ));
      index = match.start + url.length;
    }
    if (spans.isEmpty) return Text(text, style: widget.style);
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
