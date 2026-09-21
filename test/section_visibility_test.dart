import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/settings.dart';

void main() {
  group('sectionOpenIn', () {
    test('reads the same rule the settings extension does', () {
      // The sidebar calls the map form directly, because it already holds
      // the map for branch folders. Two entry points, one rule.
      const s = AppSettings(collapsedSections: {'reflog': true});
      expect(
        sectionOpenIn(s.collapsedSections, 'reflog', defaultOpen: false),
        s.sectionOpen('reflog', defaultOpen: false),
      );
      expect(sectionOpenIn(const {}, 'branches'), isTrue);
    });
  });

  group('sectionOpen', () {
    test('a section nobody has touched is showing', () {
      expect(const AppSettings().sectionOpen('branches'), isTrue);
    });

    test('a collapsed section is not', () {
      const s = AppSettings(collapsedSections: {'branches': true});
      expect(s.sectionOpen('branches'), isFalse);
    });

    test('one section says nothing about another', () {
      const s = AppSettings(collapsedSections: {'branches': true});
      expect(s.sectionOpen('tags'), isTrue);
    });

    group('a section that starts life collapsed', () {
      // The reflog is one: a recovery tool, not something read daily. Its
      // stored entry therefore means the opposite of every other section's,
      // which is exactly the trap a shared helper has to survive.
      test('is closed until someone opens it', () {
        expect(
          const AppSettings().sectionOpen('reflog', defaultOpen: false),
          isFalse,
        );
      });

      test('stays open once opened', () {
        const s = AppSettings(collapsedSections: {'reflog': false});
        expect(s.sectionOpen('reflog', defaultOpen: false), isTrue);
      });

      test('closes again when collapsed', () {
        const s = AppSettings(collapsedSections: {'reflog': true});
        expect(s.sectionOpen('reflog', defaultOpen: false), isFalse);
      });
    });
  });
}
