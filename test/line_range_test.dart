import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/line_history.dart';

void main() {
  DiffLine ctx(int oldNo, int newNo, String text) => DiffLine(
    type: DiffLineType.context,
    oldNo: oldNo,
    newNo: newNo,
    text: text,
  );
  DiffLine add(int newNo, String text) =>
      DiffLine(type: DiffLineType.add, newNo: newNo, text: text);
  DiffLine del(int oldNo, String text) =>
      DiffLine(type: DiffLineType.del, oldNo: oldNo, text: text);

  group('lineRangeOfHunk', () {
    test('spans the post-image numbers of the picked lines', () {
      final hunk = DiffHunk(
        header: '@@ -10,3 +10,3 @@',
        oldStart: 10,
        newStart: 10,
        lines: [ctx(10, 10, 'a'), add(11, 'b'), add(12, 'c'), ctx(11, 13, 'd')],
      );

      expect(lineRangeOfHunk(hunk, [1, 2]), (11, 12));
    });

    test('reads a single picked line as a one-line range', () {
      final hunk = DiffHunk(
        header: '@@ -1,2 +1,2 @@',
        oldStart: 1,
        newStart: 1,
        lines: [ctx(1, 1, 'a'), add(2, 'b')],
      );

      expect(lineRangeOfHunk(hunk, [1]), (2, 2));
    });

    test('anchors a deletion-only run at the line above it', () {
      final hunk = DiffHunk(
        header: '@@ -5,3 +5,1 @@',
        oldStart: 5,
        newStart: 5,
        lines: [ctx(5, 5, 'a'), del(6, 'b'), del(7, 'c')],
      );

      // The deleted lines have no post-image number of their own, so the range
      // points at the surviving line they sat under.
      expect(lineRangeOfHunk(hunk, [1, 2]), (5, 5));
    });

    test('anchors a deletion at the top of a hunk on the hunk start', () {
      final hunk = DiffHunk(
        header: '@@ -5,2 +5,1 @@',
        oldStart: 5,
        newStart: 5,
        lines: [del(5, 'a'), ctx(6, 5, 'b')],
      );

      expect(lineRangeOfHunk(hunk, [0]), (5, 5));
    });

    test('ignores indices outside the hunk', () {
      final hunk = DiffHunk(
        header: '@@ -1,1 +1,1 @@',
        oldStart: 1,
        newStart: 1,
        lines: [ctx(1, 1, 'a')],
      );

      expect(lineRangeOfHunk(hunk, [0, 7, -1]), (1, 1));
    });

    test('has no range when nothing is picked', () {
      final hunk = DiffHunk(
        header: '@@ -1,1 +1,1 @@',
        oldStart: 1,
        newStart: 1,
        lines: [ctx(1, 1, 'a')],
      );

      expect(lineRangeOfHunk(hunk, const []), isNull);
    });
  });
}
