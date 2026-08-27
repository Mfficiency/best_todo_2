import 'package:flutter/material.dart';

import 'linkified_text.dart';

/// A description hidden behind a small chevron toggle. List tiles that show
/// both tags and a free-text description put tags first (the more useful
/// glance info) and tuck the description behind this — shared so every tile
/// expands the same way instead of each dumping the full text inline.
/// Renders nothing for an empty description.
class DescriptionDisclosure extends StatefulWidget {
  final String description;

  const DescriptionDisclosure({Key? key, required this.description})
      : super(key: key);

  @override
  State<DescriptionDisclosure> createState() => _DescriptionDisclosureState();
}

class _DescriptionDisclosureState extends State<DescriptionDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.description.isEmpty) return const SizedBox.shrink();
    final hint = Theme.of(context).hintColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: hint,
                ),
                const SizedBox(width: 2),
                Text(
                  'Description',
                  style: TextStyle(fontSize: 12, color: hint),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: LinkifiedText(widget.description),
          ),
      ],
    );
  }
}
