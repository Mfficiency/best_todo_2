import 'dart:io';

import 'package:besttodo/models/health_metrics.dart';
import 'package:besttodo/services/health_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WeightEntry / PersonalBest json round-trip', () {
    test('WeightEntry survives toJson/fromJson', () {
      final entry = WeightEntry(
        date: DateTime(2026, 8, 30, 7, 15),
        weightKg: 71.5,
        note: 'Morning, after run',
      );
      final restored = WeightEntry.fromJson(entry.toJson());

      expect(restored.id, entry.id);
      expect(restored.date, entry.date);
      expect(restored.weightKg, 71.5);
      expect(restored.note, 'Morning, after run');
    });

    test('PersonalBest survives toJson/fromJson', () {
      final best = PersonalBest(
        name: 'Bench press',
        value: 80,
        unit: 'kg',
        date: DateTime(2026, 8, 20),
        note: 'New rack',
      );
      final restored = PersonalBest.fromJson(best.toJson());

      expect(restored.id, best.id);
      expect(restored.name, 'Bench press');
      expect(restored.value, 80);
      expect(restored.unit, 'kg');
      expect(restored.date, DateTime(2026, 8, 20));
      expect(restored.note, 'New rack');
    });
  });

  group('HealthTrackingService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp();
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      HealthTrackingService.instance.resetForTest();
    });

    File weightFile() => File('${tempDir.path}/weight_log.json');
    File bestsFile() => File('${tempDir.path}/personal_bests.json');

    test('loadWeightEntries is empty until an entry is saved', () async {
      await HealthTrackingService.instance.loadWeightEntries();
      expect(HealthTrackingService.instance.weightEntries.value, isEmpty);
      expect(await weightFile().exists(), isFalse);
    });

    test('saveWeightEntry persists and sorts newest-first, surviving reload',
        () async {
      await HealthTrackingService.instance.loadWeightEntries();
      await HealthTrackingService.instance.saveWeightEntry(
        WeightEntry(date: DateTime(2026, 8, 20), weightKg: 73),
      );
      await HealthTrackingService.instance.saveWeightEntry(
        WeightEntry(date: DateTime(2026, 8, 30), weightKg: 71),
      );

      final values = HealthTrackingService.instance.weightEntries.value;
      expect(values.map((e) => e.weightKg).toList(), [71, 73]);
      expect(await weightFile().exists(), isTrue);

      HealthTrackingService.instance.resetForTest();
      await HealthTrackingService.instance.loadWeightEntries();
      expect(
        HealthTrackingService.instance.weightEntries.value
            .map((e) => e.weightKg)
            .toList(),
        [71, 73],
      );
    });

    test('saveWeightEntry with an existing id updates it in place', () async {
      await HealthTrackingService.instance.loadWeightEntries();
      final entry =
          WeightEntry(date: DateTime(2026, 8, 20), weightKg: 73);
      await HealthTrackingService.instance.saveWeightEntry(entry);
      await HealthTrackingService.instance
          .saveWeightEntry(entry.copyWith(weightKg: 72));

      final values = HealthTrackingService.instance.weightEntries.value;
      expect(values, hasLength(1));
      expect(values.single.weightKg, 72);
    });

    test('deleteWeightEntry removes it and persists the removal', () async {
      await HealthTrackingService.instance.loadWeightEntries();
      final entry =
          WeightEntry(date: DateTime(2026, 8, 20), weightKg: 73);
      await HealthTrackingService.instance.saveWeightEntry(entry);
      await HealthTrackingService.instance.deleteWeightEntry(entry.id);

      expect(HealthTrackingService.instance.weightEntries.value, isEmpty);

      HealthTrackingService.instance.resetForTest();
      await HealthTrackingService.instance.loadWeightEntries();
      expect(HealthTrackingService.instance.weightEntries.value, isEmpty);
    });

    test('savePersonalBest persists and sorts newest-first, surviving reload',
        () async {
      await HealthTrackingService.instance.loadPersonalBests();
      await HealthTrackingService.instance.savePersonalBest(PersonalBest(
          name: '5K run', value: 23.5, unit: 'min', date: DateTime(2026, 7, 1)));
      await HealthTrackingService.instance.savePersonalBest(PersonalBest(
          name: 'Bench press', value: 80, unit: 'kg', date: DateTime(2026, 8, 15)));

      final values = HealthTrackingService.instance.personalBests.value;
      expect(values.map((b) => b.name).toList(), ['Bench press', '5K run']);
      expect(await bestsFile().exists(), isTrue);

      HealthTrackingService.instance.resetForTest();
      await HealthTrackingService.instance.loadPersonalBests();
      expect(
        HealthTrackingService.instance.personalBests.value
            .map((b) => b.name)
            .toList(),
        ['Bench press', '5K run'],
      );
    });

    test('deletePersonalBest removes it and persists the removal', () async {
      await HealthTrackingService.instance.loadPersonalBests();
      final best = PersonalBest(
          name: 'Bench press', value: 80, unit: 'kg', date: DateTime(2026, 8, 15));
      await HealthTrackingService.instance.savePersonalBest(best);
      await HealthTrackingService.instance.deletePersonalBest(best.id);

      expect(HealthTrackingService.instance.personalBests.value, isEmpty);

      HealthTrackingService.instance.resetForTest();
      await HealthTrackingService.instance.loadPersonalBests();
      expect(HealthTrackingService.instance.personalBests.value, isEmpty);
    });
  });
}
