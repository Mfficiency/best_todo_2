import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/utils/date_utils.dart';

void main() {
  test('dateDiffInDays ignores time of day', () {
    final from = DateTime(2026, 2, 16, 23, 59);
    final to = DateTime(2026, 2, 16, 0, 1);

    expect(dateDiffInDays(from, to), 0);
  });
}
