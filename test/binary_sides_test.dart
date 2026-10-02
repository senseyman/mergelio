import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blob.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/binary_diff.dart';
import 'package:mergelio/state/diff_target.dart';

const _repo = '/r';

FileDiff _file(GitChange status, {String path = 'a.png', String? oldPath}) =>
    FileDiff(path: path, oldPath: oldPath, status: status, binary: true);

void main() {
  test('a commit compares its first parent with itself', () {
    const t = DiffTarget(repoPath: _repo, path: 'a.png', commitSha: 'abc');
    final s = binarySidesFor(t, _file(GitChange.modified), staged: false);
    expect(s.before, const RevisionBlob('abc^', 'a.png'));
    expect(s.after, const RevisionBlob('abc', 'a.png'));
  });

  test('a renamed file reads its old content under its old name', () {
    const t = DiffTarget(repoPath: _repo, path: 'new.png', commitSha: 'abc');
    final s = binarySidesFor(
      t,
      _file(GitChange.renamed, path: 'new.png', oldPath: 'old.png'),
      staged: false,
    );
    expect(s.before, const RevisionBlob('abc^', 'old.png'));
    expect(s.after, const RevisionBlob('abc', 'new.png'));
  });

  test('a comparison reads the base and the head revisions', () {
    const t = DiffTarget(
      repoPath: _repo,
      path: 'a.png',
      commitSha: 'head',
      baseRev: 'main',
    );
    final s = binarySidesFor(t, _file(GitChange.modified), staged: false);
    expect(s.before, const RevisionBlob('main', 'a.png'));
    expect(s.after, const RevisionBlob('head', 'a.png'));
  });

  test('added has no before side and deleted has no after side', () {
    const t = DiffTarget(repoPath: _repo, path: 'a.png', commitSha: 'abc');
    final added = binarySidesFor(t, _file(GitChange.added), staged: false);
    expect(added.before, isNull);
    expect(added.after, isNotNull);
    final deleted = binarySidesFor(t, _file(GitChange.deleted), staged: false);
    expect(deleted.before, isNotNull);
    expect(deleted.after, isNull);
  });

  test('staged working-tree changes go from HEAD to the index', () {
    const t = DiffTarget(repoPath: _repo, path: 'a.png', staged: true);
    final s = binarySidesFor(t, _file(GitChange.modified), staged: true);
    expect(s.before, const RevisionBlob('HEAD', 'a.png'));
    expect(s.after, const IndexBlob('a.png'));
  });

  test('unstaged working-tree changes go from the index to the file on disk', () {
    // The document decides which side is shown, not the target: a target
    // asking for the staged side falls back to unstaged when nothing is staged.
    const t = DiffTarget(repoPath: _repo, path: 'a.png', staged: true);
    final s = binarySidesFor(t, _file(GitChange.modified), staged: false);
    expect(s.before, const IndexBlob('a.png'));
    expect(s.after, const WorktreeBlob('a.png'));
  });

  test('the unstaged side of a staged rename reads the index under its new '
      'name', () {
    // The index already holds the file as new.png; the old name only means
    // something on the staged side.
    const t = DiffTarget(repoPath: _repo, path: 'new.png', origPath: 'old.png');
    final s = binarySidesFor(
      t,
      _file(GitChange.modified, path: 'new.png'),
      staged: false,
    );
    expect(s.before, const IndexBlob('new.png'));
  });

  test('an untracked file has only the file on disk', () {
    const t = DiffTarget(repoPath: _repo, path: 'a.png');
    final s = binarySidesFor(t, _file(GitChange.added), staged: false);
    expect(s.before, isNull);
    expect(s.after, const WorktreeBlob('a.png'));
  });

  test('a file deleted from disk has only its index copy', () {
    const t = DiffTarget(repoPath: _repo, path: 'a.png');
    final s = binarySidesFor(t, _file(GitChange.deleted), staged: false);
    expect(s.before, const IndexBlob('a.png'));
    expect(s.after, isNull);
  });

  test('a conflict compares the two stages git left in the index', () {
    final s = conflictSidesFor('art/a.png');
    expect(s.before, const IndexBlob('art/a.png', stage: 2));
    expect(s.after, const IndexBlob('art/a.png', stage: 3));
  });
}
