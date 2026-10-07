/// A saved BPM range on the BPM page — e.g. "Running 160–175". Stored in
/// `Config.musicBpmPresets`.
class BpmPreset {
  const BpmPreset({required this.name, required this.min, required this.max});

  final String name;
  final int min;
  final int max;

  /// Whether [bpm] falls inside this range (both ends included).
  bool matches(int? bpm) => bpm != null && bpm >= min && bpm <= max;

  String get rangeLabel => '$min–$max BPM';

  Map<String, dynamic> toJson() => {'name': name, 'min': min, 'max': max};

  /// Null for an entry that can't be a range (missing or non-numeric ends).
  static BpmPreset? fromJson(Object? json) {
    if (json is! Map) return null;
    final min = (json['min'] as num?)?.round();
    final max = (json['max'] as num?)?.round();
    if (min == null || max == null) return null;
    return BpmPreset(
      name: json['name']?.toString() ?? '',
      min: min <= max ? min : max,
      max: min <= max ? max : min,
    );
  }
}
