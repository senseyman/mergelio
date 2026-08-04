// Classification is what the navigator badges and dims by. It is a pure
// function of what git already reported, so it is tested without a repository.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/project_status.dart';

Map<String, WorkingFile> _working(List<WorkingFile> files) => {
  for (final f in files) f.path: f,
};

void main() {
  test('a tracked file with no working change is clean', () {
    expect(
      classifyEntry(
        relPath: 'lib/main.dart',
        tracked: true,
        ignored: false,
        working: const {},
      ),
      EntryStatus.clean,
    );
  });

  test('an unstaged change reports modified', () {
    final working = _working([
      const WorkingFile(path: 'lib/main.dart', worktree: GitChange.modified),
    ]);

    expect(
      classifyEntry(
        relPath: 'lib/main.dart',
        tracked: true,
        ignored: false,
        working: working,
      ),
      EntryStatus.modified,
    );
  });

  test('a staged change reports modified', () {
    final working = _working([
      const WorkingFile(path: 'lib/main.dart', index: GitChange.modified),
    ]);

    expect(
      classifyEntry(
        relPath: 'lib/main.dart',
        tracked: true,
        ignored: false,
        working: working,
      ),
      EntryStatus.modified,
    );
  });

  test('a file git never heard of is untracked', () {
    expect(
      classifyEntry(
        relPath: 'scratch.txt',
        tracked: false,
        ignored: false,
        working: const {},
      ),
      EntryStatus.untracked,
    );
  });

  test('a file git reports as untracked is untracked', () {
    final working = _working([
      const WorkingFile(path: 'scratch.txt', worktree: GitChange.untracked),
    ]);

    expect(
      classifyEntry(
        relPath: 'scratch.txt',
        tracked: false,
        ignored: false,
        working: working,
      ),
      EntryStatus.untracked,
    );
  });

  test('ignored wins over untracked', () {
    expect(
      classifyEntry(
        relPath: 'build/app.o',
        tracked: false,
        ignored: true,
        working: const {},
      ),
      EntryStatus.ignored,
    );
  });

  test(
    'a tracked file inside an ignored directory still reports its change',
    () {
      // git tracks what it was told to track; an ignore rule does not stop the
      // file being edited, and hiding that change would be a lie.
      final working = _working([
        const WorkingFile(path: 'build/keep.txt', worktree: GitChange.modified),
      ]);

      expect(
        classifyEntry(
          relPath: 'build/keep.txt',
          tracked: true,
          ignored: true,
          working: working,
        ),
        EntryStatus.modified,
      );
    },
  );

  test('a conflicted file reports modified', () {
    final working = _working([
      const WorkingFile(path: 'a.txt', worktree: GitChange.conflicted),
    ]);

    expect(
      classifyEntry(
        relPath: 'a.txt',
        tracked: true,
        ignored: false,
        working: working,
      ),
      EntryStatus.modified,
    );
  });

  test('unknown tracking leaves the entry unclassified', () {
    // `git ls-files` failing must not paint every file as untracked.
    expect(
      classifyEntry(
        relPath: 'lib/main.dart',
        tracked: null,
        ignored: false,
        working: const {},
      ),
      EntryStatus.unknown,
    );
  });

  test('working files index once for the whole pass', () {
    final index = indexWorking(const [
      WorkingFile(path: 'a.txt', worktree: GitChange.modified),
      WorkingFile(path: 'b.txt', index: GitChange.added),
    ]);

    expect(index.keys, containsAll(['a.txt', 'b.txt']));
    expect(index['a.txt']!.isUnstaged, isTrue);
  });

  test('a renamed file is indexed under both of its paths', () {
    // The navigator asks by the path it sees on disk, which for a rename is
    // the new one; the old one still matters for a row that lingers.
    final index = indexWorking(const [
      WorkingFile(
        path: 'new.txt',
        index: GitChange.renamed,
        origPath: 'old.txt',
      ),
    ]);

    expect(index['new.txt'], isNotNull);
    expect(index['old.txt'], isNotNull);
  });
}
