import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/stage_patch.dart';

FileDiff _oneHunk(String body) => parseUnifiedDiff(
  'diff --git a/foo b/foo\n--- a/foo\n+++ b/foo\n$body',
).single;

void main() {
  group('buildStagePatch', () {
    final file = _oneHunk('@@ -1,3 +1,4 @@\n ctx\n-old\n+new1\n+new2\n tail\n');

    test('a whole hunk reproduces every change with recomputed counts', () {
      final patch = buildStagePatch(file, 0);
      expect(patch, '''
diff --git a/foo b/foo
--- a/foo
+++ b/foo
@@ -1,3 +1,4 @@
 ctx
-old
+new1
+new2
 tail
''');
    });

    test('staging one added line turns the rest into context', () {
      // Select only the first added line (line index 2 within the hunk).
      final patch = buildStagePatch(file, 0, lineIndexes: {2});
      expect(patch, '''
diff --git a/foo b/foo
--- a/foo
+++ b/foo
@@ -1,3 +1,4 @@
 ctx
 old
+new1
 tail
''');
    });

    test('staging one deleted line drops sibling additions', () {
      // Select only the deletion (line index 1).
      final patch = buildStagePatch(file, 0, lineIndexes: {1});
      expect(patch, '''
diff --git a/foo b/foo
--- a/foo
+++ b/foo
@@ -1,3 +1,2 @@
 ctx
-old
 tail
''');
    });

    test('returns null when the selection touches no change line', () {
      expect(buildStagePatch(file, 0, lineIndexes: const {}), isNull);
    });
  });

  test('preserves the no-newline-at-eof marker in the patch', () {
    // git emits the marker after a line that lacks a trailing newline.
    final file = _oneHunk(
      '@@ -1,1 +1,1 @@\n-old\n\\ No newline at end of file\n+new\n'
      '\\ No newline at end of file\n',
    );
    final patch = buildStagePatch(file, 0)!;
    expect('\\ No newline at end of file'.allMatches(patch).length, 2);
  });

  group('changeLineGroup', () {
    // del l1 / add X1 / ctx l2 / ctx l3
    final mod = _oneHunk('@@ -1,3 +1,3 @@\n-l1\n+X1\n l2\n l3\n').hunks.single;

    test('a modified line pairs its deletion and addition', () {
      // Clicking either side stages both, so the index is not duplicated.
      expect(changeLineGroup(mod.lines, 0), {0, 1});
      expect(changeLineGroup(mod.lines, 1), {0, 1});
    });

    test('context lines are not stageable', () {
      expect(changeLineGroup(mod.lines, 2), isEmpty);
    });

    test('a pure addition stands alone', () {
      final add = _oneHunk('@@ -1,1 +1,2 @@\n keep\n+extra\n').hunks.single;
      expect(changeLineGroup(add.lines, 1), {1});
    });

    test('a pure deletion stands alone', () {
      final del = _oneHunk('@@ -1,2 +1,1 @@\n keep\n-gone\n').hunks.single;
      expect(changeLineGroup(del.lines, 1), {1});
    });
  });
}
