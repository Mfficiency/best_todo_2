import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/permission_flow.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory tempDir;

  File marker() => File('${tempDir.path}/${PermissionFlow.markerFileName}');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    PackageInfo.setMockInitialValues(
      appName: 'BestToDo',
      packageName: 'com.mfficiency.besttodo',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
    PermissionFlow.resetForTest();
    Config.modeChosen = true;
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('first open with no marker runs the flow and records the version',
      () async {
    await PermissionFlow.maybeRequestAfterUpdate();
    expect(PermissionFlow.requestedThisSession, isTrue);
    expect(await marker().readAsString(), '1.2.3+45');
  });

  test('first open after an update (marker differs) runs the flow', () async {
    await marker().writeAsString('1.2.2+44');
    await PermissionFlow.maybeRequestAfterUpdate();
    expect(PermissionFlow.requestedThisSession, isTrue);
    expect(await marker().readAsString(), '1.2.3+45');
  });

  test('same version again does not run the flow', () async {
    await marker().writeAsString('1.2.3+45');
    await PermissionFlow.maybeRequestAfterUpdate();
    expect(PermissionFlow.requestedThisSession, isFalse);
  });

  test('skipped until the mode picker has been answered', () async {
    Config.modeChosen = false;
    await PermissionFlow.maybeRequestAfterUpdate();
    expect(PermissionFlow.requestedThisSession, isFalse);
    expect(await marker().exists(), isFalse);
  });

  test('picking simple mode settles the version without asking', () async {
    await PermissionFlow.markVersionHandled();
    expect(PermissionFlow.requestedThisSession, isFalse);
    expect(await marker().readAsString(), '1.2.3+45');
    // The settled marker keeps the next open quiet too.
    await PermissionFlow.maybeRequestAfterUpdate();
    expect(PermissionFlow.requestedThisSession, isFalse);
  });

  test('requestAll runs at most once per session', () async {
    await PermissionFlow.requestAll(trigger: 'test');
    expect(PermissionFlow.requestedThisSession, isTrue);
    // The second call must hit the session latch and stay a no-op.
    await PermissionFlow.requestAll(trigger: 'test again');
    expect(await marker().readAsString(), '1.2.3+45');
  });
}
