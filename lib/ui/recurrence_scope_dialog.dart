import 'package:flutter/material.dart';

/// Which occurrences of a recurring series a change (edit or delete) applies
/// to — the same three choices Google Calendar offers.
enum RecurrenceEditScope { thisEvent, thisAndFollowing, allEvents }

/// Asks which occurrences [isDelete] (or an edit, when false) should apply
/// to. [allowAllEvents] is false for a plain due-date move, where "all
/// events" (shifting the whole series) isn't offered — only Calendar's
/// "this event" / "this and following" choice applies there. Returns null
/// if the user backs out, meaning "do nothing".
Future<RecurrenceEditScope?> showRecurrenceScopeDialog(
  BuildContext context, {
  required bool isDelete,
  bool allowAllEvents = true,
}) {
  final verb = isDelete ? 'Delete' : 'Change';
  return showDialog<RecurrenceEditScope>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('This is a repeating task'),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(context).pop(RecurrenceEditScope.thisEvent),
          child: Text('$verb this event'),
        ),
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(context).pop(RecurrenceEditScope.thisAndFollowing),
          child: Text('$verb this and following events'),
        ),
        if (allowAllEvents)
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(RecurrenceEditScope.allEvents),
            child: Text('$verb all events'),
          ),
      ],
    ),
  );
}
