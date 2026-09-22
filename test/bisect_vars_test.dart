import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/bisect.dart';

void main() {
  group('parseBisectVars', () {
    test('reads rev, nr and steps', () {
      final v = parseBisectVars(
        "bisect_rev='aaa1111'\n"
        "bisect_nr=12\n"
        "bisect_steps=4\n"
        "bisect_all=25\n",
      );
      expect(v.rev, 'aaa1111');
      expect(v.nr, 12);
      expect(v.steps, 4);
    });

    test('missing assignments stay at the not-computed sentinel', () {
      final v = parseBisectVars('bisect_rev=aaa1111\n');
      expect(v.rev, 'aaa1111');
      expect(v.nr, -1);
      expect(v.steps, -1);
    });

    test('empty output yields all sentinels', () {
      final v = parseBisectVars('');
      expect(v.rev, '');
      expect(v.nr, -1);
      expect(v.steps, -1);
    });
  });

  group('bisectVarsArgs', () {
    test('puts the bad rev first and every good rev after --not', () {
      final args = bisectVarsArgs(const [
        BisectMark('bbb2222', BisectKind.good),
        BisectMark('aaa1111', BisectKind.bad),
        BisectMark('ccc3333', BisectKind.good),
      ]);
      expect(args, ['aaa1111', '--not', 'bbb2222', 'ccc3333']);
    });

    test('no good mark means nothing to compute', () {
      final args = bisectVarsArgs(const [
        BisectMark('aaa1111', BisectKind.bad),
      ]);
      expect(args, isEmpty);
    });

    test('no bad mark means nothing to compute', () {
      final args = bisectVarsArgs(const [
        BisectMark('bbb2222', BisectKind.good),
      ]);
      expect(args, isEmpty);
    });

    test('skip marks are not range endpoints', () {
      final args = bisectVarsArgs(const [
        BisectMark('aaa1111', BisectKind.bad),
        BisectMark('bbb2222', BisectKind.good),
        BisectMark('ccc3333', BisectKind.skip),
      ]);
      expect(args, ['aaa1111', '--not', 'bbb2222']);
    });
  });

  group('firstBadFrom', () {
    test('zero revisions left makes the bad mark the first bad commit', () {
      final sha = firstBadFrom(const [
        BisectMark('aaa1111', BisectKind.bad),
        BisectMark('bbb2222', BisectKind.good),
      ], 0);
      expect(sha, 'aaa1111');
    });

    test('revisions still left means no answer yet', () {
      final sha = firstBadFrom(const [
        BisectMark('aaa1111', BisectKind.bad),
        BisectMark('bbb2222', BisectKind.good),
      ], 3);
      expect(sha, isNull);
    });

    test('an uncomputed count is not a finished bisect', () {
      // -1 is the sentinel for "not computed yet", and it must never be
      // mistaken for a narrowed-to-nothing range.
      final sha = firstBadFrom(const [
        BisectMark('aaa1111', BisectKind.bad),
      ], -1);
      expect(sha, isNull);
    });

    test('no bad mark means no answer', () {
      expect(firstBadFrom(const [], 0), isNull);
    });
  });
}
