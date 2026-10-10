import 'package:app_template/app_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final backup = BackupService.instance;

  setUp(() {
    AppSettings.instance.resetForTest();
    backup.clearSectionsForTest();
  });

  test('buildBackup includes identity, settings and registered data', () {
    var store = [1, 2, 3];
    backup.registerSection(BackupSection(
      key: 'numbers',
      export: () => store,
      import: (json) => store = (json as List).cast<int>(),
    ));
    AppSettings.instance.minimalist = true;

    final map = backup.buildBackup();
    expect(map['app_id'], AppConfig.backupAppId);
    expect(map['schema_version'], AppConfig.backupSchemaVersion);
    expect(map['settings'], isA<Map>());
    expect((map['settings'] as Map)['minimalist'], isTrue);
    expect((map['data'] as Map)['numbers'], [1, 2, 3]);
  });

  test('export settings-only omits the data block', () {
    backup.registerSection(BackupSection(
      key: 'numbers',
      export: () => [1],
      import: (_) {},
    ));
    final map = backup.buildBackup(includeData: false);
    expect(map.containsKey('data'), isFalse);
    expect(map['settings'], isA<Map>());
  });

  test('importMap restores settings and data sections', () {
    var restored = <int>[];
    backup.registerSection(BackupSection(
      key: 'numbers',
      export: () => const <int>[],
      import: (json) => restored = (json as List).cast<int>(),
    ));

    final result = backup.importMap({
      'app_id': AppConfig.backupAppId,
      'schema_version': AppConfig.backupSchemaVersion,
      'settings': {'themeMode': 'dark'},
      'data': {'numbers': [7, 8, 9]},
    });

    expect(result.applied, isTrue);
    expect(result.warnings, isEmpty);
    expect(AppSettings.instance.themeMode, AppThemeMode.dark);
    expect(restored, [7, 8, 9]);
  });

  test('importMap refuses a backup from a different app', () {
    final result = backup.importMap({'app_id': 'some_other_app'});
    expect(result.applied, isFalse);
    expect(result.warnings.single, contains('some_other_app'));
  });

  test('importMap warns on a newer schema but still applies', () {
    final result = backup.importMap({
      'app_id': AppConfig.backupAppId,
      'schema_version': AppConfig.backupSchemaVersion + 5,
      'settings': {'minimalist': true},
    });
    expect(result.applied, isTrue);
    expect(result.warnings.any((w) => w.contains('newer format')), isTrue);
    expect(AppSettings.instance.minimalist, isTrue);
  });

  test('importMap warns about unknown sections', () {
    final result = backup.importMap({
      'app_id': AppConfig.backupAppId,
      'data': {'mystery': 1},
    });
    expect(result.applied, isTrue);
    expect(result.warnings.any((w) => w.contains('mystery')), isTrue);
  });
}
