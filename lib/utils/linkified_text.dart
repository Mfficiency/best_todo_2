import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

enum _LinkKind { url, phone }

class _LinkMatch {
  final int start;
  final int end;
  final _LinkKind kind;
  final String text;

  _LinkMatch(this.start, this.end, this.kind, this.text);
}

/// Renders [text] like a plain [Text], but with http/https URLs and phone
/// numbers underlined and tappable (URLs open in the external browser, phone
/// numbers open the dialer). A tapped link wins the gesture arena over
/// ancestor tap targets, so linkified text is safe inside a [ListTile] that
/// has its own `onTap`.
class LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  /// Test/override hook; defaults to launching the URL/tel Uri externally.
  final void Function(Uri uri)? onOpenLink;

  const LinkifiedText(
    this.text, {
    Key? key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.onOpenLink,
  }) : super(key: key);

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  static final RegExp _urlPattern = RegExp(r'https?://\S+');

  /// Candidate phone spans: digits/spaces/dots/dashes/parens, optionally
  /// preceded by a country-code `+`, at least 7 chars wide so short numbers
  /// (chapter/version-style "5.2") never qualify. Validated further by
  /// [_looksLikePhoneNumber] since this shape alone also matches dates.
  static final RegExp _phonePattern =
      RegExp(r'(?<!\w)\+?\(?\d[\d\s().-]{5,}\d(?!\w)');

  /// YYYY-MM-DD / MM-DD-YYYY / DD-MM-YYYY (dash or dot separated) — due
  /// dates typed into a note match the phone shape above but aren't numbers.
  static final RegExp _dateLikePattern = RegExp(
    r'^(\d{4}[-.]\d{1,2}[-.]\d{1,2}|\d{1,2}[-.]\d{1,2}[-.]\d{4})$',
  );

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

  static bool _looksLikePhoneNumber(String candidate) {
    if (_dateLikePattern.hasMatch(candidate)) return false;
    final digits = candidate.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7 || digits.length > 15) return false;
    final hasSeparator = candidate.contains(RegExp(r'[\s().-]'));
    if (!hasSeparator && digits.length < 9) return false;
    return true;
  }

  static List<_LinkMatch> _findLinks(String text) {
    final matches = <_LinkMatch>[];
    for (final match in _urlPattern.allMatches(text)) {
      final url = _withoutTrailingPunctuation(match.group(0)!);
      if (url.isEmpty) continue;
      matches.add(_LinkMatch(match.start, match.start + url.length,
          _LinkKind.url, url));
    }
    for (final match in _phonePattern.allMatches(text)) {
      final candidate = match.group(0)!;
      if (!_looksLikePhoneNumber(candidate)) continue;
      matches.add(
          _LinkMatch(match.start, match.end, _LinkKind.phone, candidate));
    }
    matches.sort((a, b) => a.start.compareTo(b.start));

    final resolved = <_LinkMatch>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start < cursor) continue;
      resolved.add(match);
      cursor = match.end;
    }
    return resolved;
  }

  void _open(Uri uri) {
    final onOpenLink = widget.onOpenLink;
    if (onOpenLink != null) {
      onOpenLink(uri);
    } else {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    _open(uri);
  }

  void _openPhone(String number) {
    final dialable = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (dialable.isEmpty) return;
    _open(Uri(scheme: 'tel', path: dialable));
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final text = widget.text;
    final links = _findLinks(text);
    if (links.isEmpty) {
      return Text(
        text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign,
        softWrap: widget.softWrap,
      );
    }

    final spans = <InlineSpan>[];
    var index = 0;
    for (final link in links) {
      if (link.start > index) {
        spans.add(TextSpan(text: text.substring(index, link.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = link.kind == _LinkKind.url
            ? () => _openUrl(link.text)
            : () => _openPhone(link.text);
      _recognizers.add(recognizer);
      final linkStyle = (widget.style ?? const TextStyle()).copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      );
      spans.add(TextSpan(
        text: link.text,
        style: linkStyle,
        recognizer: recognizer,
      ));
      index = link.end;
    }
    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index)));
    }
    return Text.rich(
      TextSpan(style: widget.style, children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
      softWrap: widget.softWrap,
    );
  }
}
