class DailyTaskStats {
  final String dayKey;
  final Set<String> openingTaskIds;
  final Set<String> movedFromOpeningTaskIds;
  final Set<String> completedFromOpeningTaskIds;
  final Set<String> createdDuringDayTaskIds;
  final Set<String> completedFromCreatedTaskIds;

  DailyTaskStats({
    required this.dayKey,
    Set<String>? openingTaskIds,
    Set<String>? movedFromOpeningTaskIds,
    Set<String>? completedFromOpeningTaskIds,
    Set<String>? createdDuringDayTaskIds,
    Set<String>? completedFromCreatedTaskIds,
  })  : openingTaskIds = openingTaskIds ?? <String>{},
        movedFromOpeningTaskIds = movedFromOpeningTaskIds ?? <String>{},
        completedFromOpeningTaskIds = completedFromOpeningTaskIds ?? <String>{},
        createdDuringDayTaskIds = createdDuringDayTaskIds ?? <String>{},
        completedFromCreatedTaskIds = completedFromCreatedTaskIds ?? <String>{};

  factory DailyTaskStats.fromJson(Map<String, dynamic> json) {
    Set<String> toSet(dynamic value) {
      if (value is! List) return <String>{};
      return value.whereType<String>().toSet();
    }

    return DailyTaskStats(
      dayKey: json['dayKey'] as String? ?? '',
      openingTaskIds: toSet(json['openingTaskIds']),
      movedFromOpeningTaskIds: toSet(json['movedFromOpeningTaskIds']),
      completedFromOpeningTaskIds: toSet(json['completedFromOpeningTaskIds']),
      createdDuringDayTaskIds: toSet(json['createdDuringDayTaskIds']),
      completedFromCreatedTaskIds: toSet(json['completedFromCreatedTaskIds']),
    );
  }

  Map<String, dynamic> toJson() => {
        'dayKey': dayKey,
        'openingTaskIds': openingTaskIds.toList(),
        'movedFromOpeningTaskIds': movedFromOpeningTaskIds.toList(),
        'completedFromOpeningTaskIds': completedFromOpeningTaskIds.toList(),
        'createdDuringDayTaskIds': createdDuringDayTaskIds.toList(),
        'completedFromCreatedTaskIds': completedFromCreatedTaskIds.toList(),
      };
}
