import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/ui/common/restore_version_items.dart';

void main() {
  const sha = 'c1';
  const parents = ['p1', 'p2'];

  RestoreSources of(CommitFileChange f, {List<String> parents = parents}) =>
      restoreVersionSources(sha, parents, f);

  test('a modified file restores from the commit or its first parent', () {
    final s = of(const CommitFileChange(path: 'a', change: GitChange.modified));
    expect(s.thisVersion, (rev: 'c1', path: 'a'));
    expect(s.parentVersion, (rev: 'p1', path: 'a'));
  });

  test('a deleted file has no version in the commit', () {
    final s = of(const CommitFileChange(path: 'a', change: GitChange.deleted));
    expect(s.thisVersion, isNull);
    expect(s.parentVersion, (rev: 'p1', path: 'a'));
  });

  test('an added or copied file has no version before the commit', () {
    for (final f in const [
      CommitFileChange(path: 'a', change: GitChange.added),
      CommitFileChange(path: 'b', change: GitChange.copied, origPath: 'a'),
    ]) {
      final s = of(f);
      expect(s.thisVersion, (rev: 'c1', path: f.path));
      expect(s.parentVersion, isNull);
    }
  });

  test('a renamed file restores under its old name before the commit', () {
    final s = of(
      const CommitFileChange(
        path: 'new',
        change: GitChange.renamed,
        origPath: 'old',
      ),
    );
    expect(s.thisVersion, (rev: 'c1', path: 'new'));
    expect(s.parentVersion, (rev: 'p1', path: 'old'));
  });

  test('a root commit has no version before it', () {
    final s = of(
      const CommitFileChange(path: 'a', change: GitChange.modified),
      parents: const [],
    );
    expect(s.parentVersion, isNull);
  });
}
