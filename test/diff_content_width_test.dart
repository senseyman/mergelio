import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/ui/diff/diff_metrics.dart';

FileDiff _diff(String body) => parseUnifiedDiff(
  'diff --git a/foo b/foo\n--- a/foo\n+++ b/foo\n$body',
).single;

void main() {
  group('longestLineChars', () {
    test('measures the widest code line, ignoring the +/- marker', () {
      final file = _diff('@@ -1,2 +1,2 @@\n ok\n-short\n+a much longer line\n');
      expect(longestLineChars([file]), 'a much longer line'.length);
    });

    test('spans every file and every hunk', () {
      final a = _diff('@@ -1,1 +1,1 @@\n tiny\n');
      final b = _diff('@@ -1,1 +1,1 @@\n the longest one here\n');
      expect(longestLineChars([a, b]), 'the longest one here'.length);
    });

    test('a hunk header counts too, so it is never clipped', () {
      final file = _diff(
        '@@ -1,1 +1,1 @@ fn withAVeryLongEnclosingName()\n x\n',
      );
      expect(
        longestLineChars([file]),
        '@@ -1,1 +1,1 @@ fn withAVeryLongEnclosingName()'.length,
      );
    });

    test('a tab is budgeted as more than one column', () {
      final tabbed = _diff('@@ -1,1 +1,1 @@\n \t\tx\n');
      // Two tabs plus one character must reserve more than three columns.
      expect(longestLineChars([tabbed]), greaterThan(3));
    });

    test('an empty diff has no width to reserve', () {
      expect(longestLineChars(const []), 0);
    });
  });

  group('diffContentWidth', () {
    test('reserves gutter plus text, and never less than the viewport', () {
      // A short line cannot shrink the row below the space available.
      expect(
        diffContentWidth(viewport: 800, chars: 3, charWidth: 7, split: false),
        800,
      );
    });

    test('grows past the viewport for a long line', () {
      final w = diffContentWidth(
        viewport: 400,
        chars: 200,
        charWidth: 7,
        split: false,
      );
      expect(w, greaterThan(400));
      expect(w, greaterThan(200 * 7));
    });

    test('split view has to fit the text twice, side by side', () {
      final inline = diffContentWidth(
        viewport: 400,
        chars: 200,
        charWidth: 7,
        split: false,
      );
      final split = diffContentWidth(
        viewport: 400,
        chars: 200,
        charWidth: 7,
        split: true,
      );
      expect(split, greaterThan(inline));
    });
  });
}
