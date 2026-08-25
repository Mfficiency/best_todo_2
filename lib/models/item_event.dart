import 'package:uuid/uuid.dart';

import 'task_change_source.dart';

/// A single change to one field of an item, recorded inside an [ItemEvent].
/// Values are the JSON representations of the field (String/bool/int/null),
/// so a change round-trips losslessly through the journal file.
class FieldChange {
  String field;
  Object? from;
  Object? to;

  FieldChange(this.field, this.from, this.to);

  factory FieldChange.fromJson(Map<String, dynamic> json) => FieldChange(
        json['field'] as String? ?? '',
        json['from'],
        json['to'],
      );

  Map<String, dynamic> toJson() => {
        'field': field,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };
}

/// One immutable entry in the append-only item-history journal
/// (`item_events.jsonl`): who-knows-what changed on which item, when.
///
/// [seq] is the per-item version number: the item's first event is seq 1 and
/// every later event increments it, so "the item at version N" is the replay
/// of its first N events. Events are never edited after being written;
/// history is only ever appended (and compacted by dropping the oldest
/// entries when the file grows too large).
class ItemEvent {
  static final Uuid _uuid = const Uuid();

  static String newUid() => _uuid.v4();

  /// Event types. Stored in JSON — keep them stable once shipped.
  static const String typeCreated = 'created';
  static const String typeEdited = 'edited';
  static const String typeLabeled = 'labeled';
  static const String typeScheduled = 'scheduled';
  static const String typeStatusChanged = 'statusChanged';
  static const String typeProjectChanged = 'projectChanged';
  static const String typeWishChanged = 'wishChanged';
  static const String typeRecurrenceChanged = 'recurrenceChanged';
  static const String typeDeleted = 'deleted';
  static const String typeRestored = 'restored';

  String eventId;

  /// Uid of the task this event belongs to.
  String itemId;

  /// Per-item sequence number (1-based). Doubles as the item's version.
  int seq;

  DateTime at;

  /// One of the `type*` constants above.
  String type;

  /// Field-level changes carried by this event. Empty for lifecycle events
  /// (deleted/restored) where the type alone tells the story.
  List<FieldChange> patch;

  /// True when the event was reconstructed from pre-journal data (lifecycle
  /// timestamps, the deleted list, daily stats) rather than observed live.
  bool seeded;

  /// Where the change came from — one of [TaskChangeSource]'s constants.
  /// Absent on events written before source tracking existed; those default
  /// to [TaskChangeSource.user] on read.
  String source;

  ItemEvent({
    String? eventId,
    required this.itemId,
    required this.seq,
    required this.at,
    required this.type,
    List<FieldChange>? patch,
    this.seeded = false,
    this.source = TaskChangeSource.user,
  })  : eventId = eventId ?? ItemEvent.newUid(),
        patch = patch ?? <FieldChange>[];

  factory ItemEvent.fromJson(Map<String, dynamic> json) => ItemEvent(
        eventId: json['eventId'] as String?,
        itemId: json['itemId'] as String? ?? '',
        seq: json['seq'] as int? ?? 0,
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(1970),
        type: json['type'] as String? ?? '',
        patch: (json['patch'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((e) => FieldChange.fromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            <FieldChange>[],
        seeded: json['seeded'] as bool? ?? false,
        source: json['source'] as String? ?? TaskChangeSource.user,
      );

  Map<String, dynamic> toJson() => {
        'eventId': eventId,
        'itemId': itemId,
        'seq': seq,
        'at': at.toIso8601String(),
        'type': type,
        if (patch.isNotEmpty) 'patch': patch.map((c) => c.toJson()).toList(),
        if (seeded) 'seeded': seeded,
        if (source != TaskChangeSource.user) 'source': source,
      };
}
