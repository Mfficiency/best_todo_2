import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// A single manually-logged bodyweight measurement.
class WeightEntry {
  final String id;
  final DateTime date;
  final double weightKg;
  final String note;

  WeightEntry({
    String? id,
    required this.date,
    required this.weightKg,
    this.note = '',
  }) : id = id ?? _uuid.v4();

  WeightEntry copyWith({DateTime? date, double? weightKg, String? note}) =>
      WeightEntry(
        id: id,
        date: date ?? this.date,
        weightKg: weightKg ?? this.weightKg,
        note: note ?? this.note,
      );

  factory WeightEntry.fromJson(Map<String, dynamic> json) => WeightEntry(
        id: json['id'] as String?,
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'weightKg': weightKg,
        'note': note,
      };
}

/// A manually-logged personal best, e.g. "Bench press" 80 kg or "5K run"
/// 22.5 minutes. [unit] is free-form so it fits both weight-based and
/// time-based records.
class PersonalBest {
  final String id;
  final String name;
  final double value;
  final String unit;
  final DateTime date;
  final String note;

  PersonalBest({
    String? id,
    required this.name,
    required this.value,
    required this.unit,
    required this.date,
    this.note = '',
  }) : id = id ?? _uuid.v4();

  PersonalBest copyWith({
    String? name,
    double? value,
    String? unit,
    DateTime? date,
    String? note,
  }) =>
      PersonalBest(
        id: id,
        name: name ?? this.name,
        value: value ?? this.value,
        unit: unit ?? this.unit,
        date: date ?? this.date,
        note: note ?? this.note,
      );

  factory PersonalBest.fromJson(Map<String, dynamic> json) => PersonalBest(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '',
        value: (json['value'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
        'unit': unit,
        'date': date.toIso8601String(),
        'note': note,
      };
}
