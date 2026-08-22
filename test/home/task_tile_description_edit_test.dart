import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/task_tile.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  testWidgets('editing description does not toggle task done', (tester) async {
    final task = Task(title: 'Task');
    int toggleCount = 0;
    int saveCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTile(
          task: task,
          onChanged: () => saveCount++,
          onToggle: () => toggleCount++,
          onMove: (_) {},
          onMoveNext: () {},
          onDelete: () {},
          pageIndex: 0,
        ),
      ),
    ));

    // Expand the tile to reveal the description field.
    await tester.tap(find.text('Task').first);
    await tester.pumpAndSettle();

    // Enter description text.
    await tester.enterText(
        find.widgetWithText(TextField, 'Description'), 'New description');
    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(task.description, 'New description');
    expect(toggleCount, 0);
  });

  testWidgets('URL in a task title opens externally instead of expanding',
      (tester) async {
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
    final task = Task(title: 'Read https://example.com/article');
    var changed = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTile(
          task: task,
          onChanged: () => changed++,
          onToggle: () {},
          onMove: (_) {},
          onMoveNext: () {},
          onDelete: () {},
          pageIndex: 0,
        ),
      ),
    ));

    await tester
        .tapOnText(find.textRange.ofSubstring('https://example.com/article'));
    await tester.pump();

    expect(launcher.launched, ['https://example.com/article']);
    expect(find.widgetWithText(TextField, 'Description'), findsNothing);
    expect(changed, 0);
  });
}
