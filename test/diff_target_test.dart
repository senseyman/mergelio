import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/diff_target.dart';

void main() {
  test('staged distinguishes equality and hashCode', () {
    const a = DiffTarget(repoPath: '/r', path: 'x.txt', staged: false);
    const b = DiffTarget(repoPath: '/r', path: 'x.txt', staged: true);
    expect(a == b, isFalse);
    expect(a.hashCode == b.hashCode, isFalse);
    expect(
      a == const DiffTarget(repoPath: '/r', path: 'x.txt'),
      isTrue, // staged defaults to false
    );
  });

  test('withStaged flips only the side', () {
    const a = DiffTarget(repoPath: '/r', path: 'x.txt');
    final b = a.withStaged(true);
    expect(b.staged, isTrue);
    expect(b.repoPath, '/r');
    expect(b.path, 'x.txt');
    expect(b.commitSha, isNull);
    expect(b.withStaged(false), a);
  });

  group('showsSameFile', () {
    const a = DiffTarget(
      repoPath: '/r',
      path: 'new.dart',
      origPath: 'old.dart',
      commitSha: 'c1',
    );

    test('ignores how the diff is shown and where a rename came from', () {
      expect(a.showsSameFile(a.withWholeFile(true)), isTrue);
      expect(
        a.showsSameFile(
          const DiffTarget(repoPath: '/r', path: 'new.dart', commitSha: 'c1'),
        ),
        isTrue,
      );
    });

    test('tells apart another file, revision, side, or repository', () {
      for (final other in const [
        DiffTarget(repoPath: '/r', path: 'x.dart', commitSha: 'c1'),
        DiffTarget(repoPath: '/r', path: 'new.dart', commitSha: 'c2'),
        DiffTarget(
          repoPath: '/r',
          path: 'new.dart',
          commitSha: 'c1',
          baseRev: 'b',
        ),
        DiffTarget(
          repoPath: '/r',
          path: 'new.dart',
          commitSha: 'c1',
          fromStash: true,
        ),
        DiffTarget(repoPath: '/s', path: 'new.dart', commitSha: 'c1'),
        DiffTarget(repoPath: '/r', path: 'new.dart'),
      ]) {
        expect(a.showsSameFile(other), isFalse, reason: '$other');
      }
    });

    test('a working-tree diff tells its two sides apart', () {
      const unstaged = DiffTarget(repoPath: '/r', path: 'f');
      expect(unstaged.showsSameFile(unstaged.withStaged(true)), isFalse);
    });

    test('nothing open is never the same file', () {
      expect(a.showsSameFile(null), isFalse);
    });
  });
}
