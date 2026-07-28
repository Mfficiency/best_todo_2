import 'package:app_template/app_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(LogService.clear);

  test('add appends a timestamped, sourced entry', () {
    LogService.add('Test', 'hello');
    expect(LogService.logs.value.single, contains('[Test] hello'));
    expect(LogService.logs.value.single, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T')));
  });

  test('clear empties the buffer', () {
    LogService.add('Test', 'a');
    LogService.clear();
    expect(LogService.logs.value, isEmpty);
  });

  test('prunes entries older than 24 hours', () {
    final old = DateTime.now().subtract(const Duration(days: 2));
    LogService.logs.value = ['${old.toIso8601String()} [Old] stale'];
    LogService.add('New', 'fresh');
    expect(LogService.logs.value.length, 1);
    expect(LogService.logs.value.single, contains('fresh'));
  });
}
