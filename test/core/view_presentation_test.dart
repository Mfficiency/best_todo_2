import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/models/view_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ViewPresentation.forView', () {
    test('an unconfigured/null view id shows every section', () {
      const defaults = ViewPresentation();
      expect(ViewPresentation.forView(null).showReminderSection,
          defaults.showReminderSection);
      expect(ViewPresentation.forView(null).showCountdownSection,
          defaults.showCountdownSection);
      expect(ViewPresentation.forView('not-a-real-view').showReminderSection,
          isTrue);
    });

    test('active views (home, wishlist, projects, ...) show every section',
        () {
      for (final viewId in [
        ViewFilterRules.home,
        ViewFilterRules.wishlist,
        ViewFilterRules.approval,
        ViewFilterRules.projects,
        ViewFilterRules.foodDiary,
        ViewFilterRules.alarms,
        ViewFilterRules.countdown,
      ]) {
        final p = ViewPresentation.forView(viewId);
        expect(p.showReminderSection, isTrue, reason: viewId);
        expect(p.showCountdownSection, isTrue, reason: viewId);
      }
    });

    test('terminal views (archived, bin) hide item-linked capability '
        'sections', () {
      for (final viewId in [ViewFilterRules.archived, ViewFilterRules.bin]) {
        final p = ViewPresentation.forView(viewId);
        expect(p.showReminderSection, isFalse, reason: viewId);
        expect(p.showCountdownSection, isFalse, reason: viewId);
        expect(p, same(ViewPresentation.terminal));
      }
    });
  });
}
