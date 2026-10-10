import 'dart:convert';

/// Splits a Todoist task's `description` field into the part the user edits
/// (in either app) and the BestToDo metadata trailer this codec appends.
class TodoistDescriptionParts {
  /// The user-facing text — mirrors [Task.description] both ways.
  final String visible;

  /// Decoded `sync-data` payload, or null when the description carries no
  /// BestToDo trailer (a task that was never synced, or created fresh in
  /// Todoist).
  final Map<String, dynamic>? meta;

  const TodoistDescriptionParts({required this.visible, this.meta});
}

/// Encodes/decodes the BestToDo trailer appended to a synced Todoist task's
/// description field.
///
/// BestToDo tracks fields Todoist has no equivalent for — the separate
/// [Task.note], the free-text [Task.label], which project/Kanban column a
/// task sits in — so round-tripping them through a plain "description" field
/// needs somewhere to live. Rather than hide them in something Todoist would
/// mangle, they're appended as a readable summary (visible if you open the
/// task in Todoist) followed by one compact JSON line prefixed `sync-data:`,
/// which is what this codec actually parses back — the summary lines above
/// it are for the human reading the Todoist app, not for round-tripping.
class TodoistMetadataCodec {
  static const String marker = 'BestToDo sync';
  static const String _separator = '\n\n⸻ $marker — generated, do not edit '
      'below this line ⸻\n';
  static final RegExp _dataLine = RegExp(r'^sync-data:\s*(\{.*\})\s*$');

  /// Builds the full Todoist description for [visible] (mirrors
  /// [Task.description]) plus the metadata fields listed in [meta].
  static String build({
    required String visible,
    required Map<String, dynamic> meta,
  }) {
    final summary = StringBuffer();
    final project = meta['projectName'] as String?;
    final stage = meta['kanbanStageLabel'] as String?;
    if (project != null && project.isNotEmpty) {
      summary.writeln(
          'Project: $project${stage != null && stage.isNotEmpty ? ' · $stage' : ''}');
    }
    final label = meta['label'] as String?;
    if (label != null && label.isNotEmpty) summary.writeln('Label: $label');
    final note = meta['note'] as String?;
    if (note != null && note.isNotEmpty) summary.writeln('Note: $note');
    summary.write('sync-data: ${jsonEncode(meta)}');

    final trimmedVisible = visible.trim();
    return trimmedVisible.isEmpty
        ? '$_separator$summary'
        : '$trimmedVisible$_separator$summary';
  }

  /// Parses a Todoist description back into the editable [visible] text and
  /// the decoded metadata, if any.
  static TodoistDescriptionParts parse(String description) {
    final idx = description.indexOf('⸻ $marker');
    if (idx < 0) {
      return TodoistDescriptionParts(visible: description.trim());
    }
    // Walk back over the separator's own leading blank line(s) so they don't
    // linger as trailing whitespace on the visible part.
    final visible = description.substring(0, idx).trim();
    final trailer = description.substring(idx);
    for (final line in trailer.split('\n')) {
      final match = _dataLine.firstMatch(line.trim());
      if (match == null) continue;
      try {
        final decoded = jsonDecode(match.group(1)!);
        if (decoded is Map<String, dynamic>) {
          return TodoistDescriptionParts(visible: visible, meta: decoded);
        }
        if (decoded is Map) {
          return TodoistDescriptionParts(
            visible: visible,
            meta: Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {
        // Malformed trailer (hand-edited in Todoist): fall through and treat
        // this task as unsynced metadata, keeping the visible text intact.
      }
    }
    return TodoistDescriptionParts(visible: visible);
  }
}
