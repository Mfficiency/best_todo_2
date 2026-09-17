import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/smart_test.dart' as tool;

/// `tool/smart_test.dart` picks which `test/<area>` suite(s) a change should
/// run, falling back to a full `flutter test` for anything cross-cutting or
/// unrecognised, and forces a full run periodically (every
/// [tool.fullRunEveryMods] targeted runs or [tool.fullRunEveryDays] days) so
/// the shortcut never silently drifts out of sync with the real suite.
void main() {
  group('testSuiteFor', () {
    test('maps a test/<area>/ path to that area', () {
      expect(tool.testSuiteFor('test/alarms/alarm_model_test.dart'), 'alarms');
      expect(tool.testSuiteFor('test/home/home_search_test.dart'), 'home');
    });

    test('test/core/ maps to nothing extra (core always runs)', () {
      expect(tool.testSuiteFor('test/core/task_model_test.dart'), isNull);
    });

    test('a bare test/ file with no subdirectory maps to nothing', () {
      expect(tool.testSuiteFor('test/README.md'), isNull);
    });
  });

  group('classify', () {
    test('docs/changelog-only changes are not test-relevant', () {
      final c = tool.classify(['CHANGELOG.md', 'SPEC.md', 'docs/foo.md']);
      expect(c.anyTestRelevant, isFalse);
      expect(c.crossCutting, isFalse);
      expect(c.suites, isEmpty);
    });

    test('pubspec.yaml forces a full (cross-cutting) run', () {
      final c = tool.classify(['pubspec.yaml']);
      expect(c.crossCutting, isTrue);
      expect(c.crossCuttingFiles, contains('pubspec.yaml'));
    });

    test('an alarm model change maps to the alarms suite', () {
      final c = tool.classify(['lib/models/alarm.dart']);
      expect(c.crossCutting, isFalse);
      expect(c.suites, {'alarms'});
    });

    test('a change touching multiple areas unions their suites', () {
      final c = tool.classify([
        'lib/models/project.dart',
        'lib/services/streak_service.dart',
      ]);
      expect(c.suites, {'projects', 'streaks'});
    });

    test('home_page.dart pulls in every suite it hosts', () {
      final c = tool.classify(['lib/ui/home_page.dart']);
      expect(c.suites, {'home', 'projects', 'streaks', 'recurrence', 'music'});
    });

    test('a test/<area> file change maps straight to that suite', () {
      final c = tool.classify(['test/sync/sync_service_test.dart']);
      expect(c.suites, {'sync'});
      expect(c.crossCutting, isFalse);
    });

    test('a test/core file change needs nothing beyond core', () {
      final c = tool.classify(['test/core/task_model_test.dart']);
      expect(c.suites, isEmpty);
      expect(c.crossCutting, isFalse);
      expect(c.anyTestRelevant, isTrue);
    });

    test('an unrecognised lib/ file falls back to a full run', () {
      final c = tool.classify(['lib/services/brand_new_service.dart']);
      expect(c.crossCutting, isTrue);
      expect(c.crossCuttingFiles, contains('lib/services/brand_new_service.dart'));
    });

    test('an unrecognised platform file falls back to a full run', () {
      final c = tool.classify(['android/app/src/main/AndroidManifest.xml']);
      expect(c.crossCutting, isTrue);
    });

    test('a platform file matched by basename only maps to its suite', () {
      final c = tool.classify([
        'android/app/src/main/kotlin/com/example/AlarmsWidgetProvider.kt',
      ]);
      expect(c.crossCutting, isFalse);
      expect(c.suites, {'alarms', 'home'});
    });

    test('backslash separators from Windows git output are normalised', () {
      final c = tool.classify([r'lib\models\alarm.dart']);
      expect(c.suites, {'alarms'});
    });
  });

  group('SmartTestState', () {
    test('round-trips through JSON', () {
      final state = tool.SmartTestState(
        modsSinceFullRun: 3,
        lastFullRun: DateTime(2026, 9, 1),
        totalRuns: 12,
      );
      final decoded = tool.SmartTestState.fromJson(state.toJson());
      expect(decoded.modsSinceFullRun, 3);
      expect(decoded.lastFullRun, DateTime(2026, 9, 1));
      expect(decoded.totalRuns, 12);
    });

    test('initial state has never run in full', () {
      expect(tool.SmartTestState.initial.lastFullRun, isNull);
      expect(tool.SmartTestState.initial.modsSinceFullRun, 0);
    });

    test('afterRun(full: false) increments the mod counter', () {
      final next = tool.SmartTestState.initial.afterRun(full: false);
      expect(next.modsSinceFullRun, 1);
      expect(next.lastFullRun, isNull);
      expect(next.totalRuns, 1);
    });

    test('afterRun(full: true) resets the mod counter and stamps the time',
        () {
      final next = tool.SmartTestState(
        modsSinceFullRun: 7,
        lastFullRun: DateTime(2020),
        totalRuns: 20,
      ).afterRun(full: true);
      expect(next.modsSinceFullRun, 0);
      expect(next.lastFullRun, isNotNull);
      expect(next.lastFullRun!.isAfter(DateTime(2020)), isTrue);
      expect(next.totalRuns, 21);
    });
  });

  group('readState / writeState', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('smart_test_state_test');
    });

    tearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {
        // Disposable temp dir; a lingering handle isn't worth failing over.
      }
    });

    test('a missing file reads as the initial state', () {
      final state = tool.readState(File('${temp.path}/missing.json'));
      expect(state.modsSinceFullRun, 0);
      expect(state.lastFullRun, isNull);
    });

    test('corrupt JSON reads as the initial state instead of throwing', () {
      final file = File('${temp.path}/state.json')..writeAsStringSync('{not json');
      final state = tool.readState(file);
      expect(state.modsSinceFullRun, 0);
    });

    test('writeState then readState round-trips', () {
      final file = File('${temp.path}/state.json');
      tool.writeState(
        file,
        tool.SmartTestState(
          modsSinceFullRun: 4,
          lastFullRun: DateTime(2026, 9, 10, 8, 30),
          totalRuns: 9,
        ),
      );
      final decoded = jsonDecode(file.readAsStringSync());
      expect(decoded['modsSinceFullRun'], 4);
      expect(decoded['totalRuns'], 9);

      final state = tool.readState(file);
      expect(state.modsSinceFullRun, 4);
      expect(state.lastFullRun, DateTime(2026, 9, 10, 8, 30));
    });
  });

  group('decide', () {
    final now = DateTime(2026, 9, 17);
    final recentState = tool.SmartTestState(
      modsSinceFullRun: 2,
      lastFullRun: now.subtract(const Duration(days: 1)),
      totalRuns: 5,
    );

    test('--full always forces a full run', () {
      final d = tool.decide(
        classification: tool.classify(['CHANGELOG.md']),
        state: recentState,
        now: now,
        forceFull: true,
      );
      expect(d.full, isTrue);
    });

    test('a cross-cutting change forces a full run even with fresh state', () {
      final d = tool.decide(
        classification: tool.classify(['pubspec.yaml']),
        state: recentState,
        now: now,
      );
      expect(d.full, isTrue);
    });

    test('a targeted change with fresh state runs core + the touched suite',
        () {
      final d = tool.decide(
        classification: tool.classify(['lib/models/alarm.dart']),
        state: recentState,
        now: now,
      );
      expect(d.full, isFalse);
      expect(d.suites, {'core', 'alarms'});
    });

    test('no test-relevant files needs no run at all', () {
      final d = tool.decide(
        classification: tool.classify(['CHANGELOG.md']),
        state: recentState,
        now: now,
      );
      expect(d.full, isFalse);
      expect(d.suites, isEmpty);
    });

    test('hitting the mod-count safety net forces a full run', () {
      final saturated = tool.SmartTestState(
        modsSinceFullRun: tool.fullRunEveryMods,
        lastFullRun: now.subtract(const Duration(hours: 1)),
        totalRuns: 30,
      );
      final d = tool.decide(
        classification: tool.classify(['lib/models/alarm.dart']),
        state: saturated,
        now: now,
      );
      expect(d.full, isTrue);
      expect(d.reason, contains('safety net'));
    });

    test('never having run in full forces a full run', () {
      final d = tool.decide(
        classification: tool.classify(['lib/models/alarm.dart']),
        state: tool.SmartTestState.initial,
        now: now,
      );
      expect(d.full, isTrue);
    });

    test('the weekly safety net forces a full run once stale', () {
      final stale = tool.SmartTestState(
        modsSinceFullRun: 1,
        lastFullRun: now.subtract(Duration(days: tool.fullRunEveryDays)),
        totalRuns: 4,
      );
      final d = tool.decide(
        classification: tool.classify(['lib/models/alarm.dart']),
        state: stale,
        now: now,
      );
      expect(d.full, isTrue);
      expect(d.reason, contains('days'));
    });

    test('just under the weekly threshold stays targeted', () {
      final almostStale = tool.SmartTestState(
        modsSinceFullRun: 1,
        lastFullRun: now.subtract(Duration(days: tool.fullRunEveryDays - 1)),
        totalRuns: 4,
      );
      final d = tool.decide(
        classification: tool.classify(['lib/models/alarm.dart']),
        state: almostStale,
        now: now,
      );
      expect(d.full, isFalse);
    });
  });
}
