import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/compare_target.dart';
import 'package:mergelio/state/diff_target.dart';

void main() {
  const sha = '0123456789abcdef0123456789abcdef01234567';

  group('compareRefLabel', () {
    test('shortens a full sha', () {
      expect(compareRefLabel(sha), '0123456');
    });

    test('leaves a ref name alone', () {
      expect(compareRefLabel('feature/login'), 'feature/login');
      expect(compareRefLabel('origin/main'), 'origin/main');
    });

    test('leaves a short hex-looking branch name alone', () {
      expect(compareRefLabel('abcdef'), 'abcdef');
    });
  });

  group('CompareTarget', () {
    const target = CompareTarget(repoPath: '/r', from: 'main', to: sha);

    test('labels each side', () {
      expect(target.fromLabel, 'main');
      expect(target.toLabel, '0123456');
    });

    test('swapped reverses the direction only', () {
      final s = target.swapped;
      expect(s.from, sha);
      expect(s.to, 'main');
      expect(s.repoPath, '/r');
      expect(s.swapped, target);
    });

    test('equality covers both sides', () {
      expect(
        target == const CompareTarget(repoPath: '/r', from: 'main', to: sha),
        isTrue,
      );
      expect(target == target.swapped, isFalse);
      expect(target.hashCode == target.swapped.hashCode, isFalse);
    });

    test('fileTarget opens the file as a read-only two-ref diff', () {
      final d = target.fileTarget('lib/x.dart');
      expect(d.repoPath, '/r');
      expect(d.path, 'lib/x.dart');
      expect(d.baseRev, 'main');
      expect(d.commitSha, sha);
      expect(d.origPath, isNull);
    });

    test('fileTarget carries the pre-rename path when there is one', () {
      final d = target.fileTarget('lib/new.dart', origPath: 'lib/old.dart');
      expect(d.origPath, 'lib/old.dart');
      // Two targets that differ only by the path a file came from are not the
      // same diff, so the provider family must tell them apart.
      expect(d == target.fileTarget('lib/new.dart'), isFalse);
      expect(d.hashCode == target.fileTarget('lib/new.dart').hashCode, isFalse);
    });
  });

  group('DiffTarget with a base ref', () {
    const a = DiffTarget(
      repoPath: '/r',
      path: 'x.txt',
      commitSha: 'bbb',
      baseRev: 'aaa',
    );

    test('is a comparison, not a commit diff', () {
      expect(a.isComparison, isTrue);
      expect(a.isWorkingTree, isFalse);
      expect(
        const DiffTarget(
          repoPath: '/r',
          path: 'x.txt',
          commitSha: 'bbb',
        ).isComparison,
        isFalse,
      );
    });

    test('the base ref takes part in equality', () {
      expect(
        a == const DiffTarget(repoPath: '/r', path: 'x.txt', commitSha: 'bbb'),
        isFalse,
      );
      expect(
        a.hashCode ==
            const DiffTarget(
              repoPath: '/r',
              path: 'x.txt',
              commitSha: 'bbb',
            ).hashCode,
        isFalse,
      );
    });

    test('withWholeFile keeps the base ref and the pre-rename path', () {
      const r = DiffTarget(
        repoPath: '/r',
        path: 'new.txt',
        commitSha: 'bbb',
        baseRev: 'aaa',
        origPath: 'old.txt',
      );
      expect(a.withWholeFile(true).baseRev, 'aaa');
      expect(a.withWholeFile(true).commitSha, 'bbb');
      expect(r.withWholeFile(true).origPath, 'old.txt');
      expect(r.withStaged(true).origPath, 'old.txt');
    });
  });
}
