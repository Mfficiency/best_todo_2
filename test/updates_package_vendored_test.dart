// Written by flutter_app_template/tool/sync_updates_package.sh: don't edit.
// module-file:updates (deleted with the updates module)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/vendoring.dart';

void main() {
  test('packages/mfficiency_updates is the template\'s copy (see its ORIGIN)',
      () {
    expect(
      vendoredCopyProblems(Directory('packages/mfficiency_updates')),
      isEmpty,
      reason: 'Change the package in flutter_app_template, then run '
          'tool/sync_updates_package.sh <this app> there.',
    );
  });
}
