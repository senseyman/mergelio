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
}
