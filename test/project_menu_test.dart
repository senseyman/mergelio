// Which navigator context-menu items a row offers. Gating is decided here so
// the menu itself stays a rendering of the answer.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/project_menu.dart';
import 'package:mergelio/domain/project_status.dart';

void main() {
  List<ProjectMenuItem> dir() =>
      projectMenuItems(isDir: true, status: EntryStatus.clean);

  List<ProjectMenuItem> file(EntryStatus status, {WorkingFile? change}) =>
      projectMenuItems(isDir: false, status: status, change: change);

  test('a directory offers the create items', () {
    expect(
      dir(),
      containsAll([ProjectMenuItem.newFile, ProjectMenuItem.newFolder]),
    );
  });

  test('a file offers no create items', () {
    expect(file(EntryStatus.clean), isNot(contains(ProjectMenuItem.newFile)));
    expect(file(EntryStatus.clean), isNot(contains(ProjectMenuItem.newFolder)));
  });

  test('every row can be renamed, deleted and revealed', () {
    for (final items in [dir(), file(EntryStatus.unknown)]) {
      expect(
        items,
        containsAll([
          ProjectMenuItem.rename,
          ProjectMenuItem.delete,
          ProjectMenuItem.reveal,
        ]),
      );
    }
  });

  test('an unstaged change can be staged', () {
    final items = file(
      EntryStatus.modified,
      change: const WorkingFile(path: 'a.txt', worktree: GitChange.modified),
    );

    expect(items, contains(ProjectMenuItem.stage));
    expect(items, isNot(contains(ProjectMenuItem.unstage)));
  });

  test('an untracked file can be staged', () {
    final items = file(
      EntryStatus.untracked,
      change: const WorkingFile(path: 'a.txt', worktree: GitChange.untracked),
    );

    expect(items, contains(ProjectMenuItem.stage));
  });

  test('a staged change can be unstaged', () {
    final items = file(
      EntryStatus.modified,
      change: const WorkingFile(path: 'a.txt', index: GitChange.modified),
    );

    expect(items, contains(ProjectMenuItem.unstage));
    expect(items, isNot(contains(ProjectMenuItem.stage)));
  });

  test('a partly staged change offers both', () {
    final items = file(
      EntryStatus.modified,
      change: const WorkingFile(
        path: 'a.txt',
        index: GitChange.modified,
        worktree: GitChange.modified,
      ),
    );

    expect(
      items,
      containsAll([ProjectMenuItem.stage, ProjectMenuItem.unstage]),
    );
  });

  test('a clean file offers neither staging item', () {
    final items = file(EntryStatus.clean);

    expect(items, isNot(contains(ProjectMenuItem.stage)));
    expect(items, isNot(contains(ProjectMenuItem.unstage)));
  });

  test('only a changed file can be discarded', () {
    expect(
      file(
        EntryStatus.modified,
        change: const WorkingFile(path: 'a.txt', worktree: GitChange.modified),
      ),
      contains(ProjectMenuItem.discard),
    );
    expect(file(EntryStatus.clean), isNot(contains(ProjectMenuItem.discard)));
  });

  test('an untracked file can be discarded, which deletes it', () {
    final items = file(
      EntryStatus.untracked,
      change: const WorkingFile(path: 'a.txt', worktree: GitChange.untracked),
    );

    expect(items, contains(ProjectMenuItem.discard));
  });

  test('history is offered for tracked files only', () {
    expect(file(EntryStatus.clean), contains(ProjectMenuItem.history));
    expect(
      file(
        EntryStatus.modified,
        change: const WorkingFile(path: 'a.txt', worktree: GitChange.modified),
      ),
      contains(ProjectMenuItem.history),
    );
    expect(
      file(EntryStatus.untracked),
      isNot(contains(ProjectMenuItem.history)),
    );
    // Nothing is known about the file, so nothing is claimed about it.
    expect(file(EntryStatus.unknown), isNot(contains(ProjectMenuItem.history)));
    expect(dir(), isNot(contains(ProjectMenuItem.history)));
  });

  test('an ignored file is still a file on disk', () {
    final items = file(EntryStatus.ignored);

    expect(
      items,
      containsAll([
        ProjectMenuItem.rename,
        ProjectMenuItem.delete,
        ProjectMenuItem.reveal,
      ]),
    );
    expect(items, isNot(contains(ProjectMenuItem.history)));
  });

  test('the root menu offers only what needs nothing selected', () {
    expect(projectRootMenuItems(), [
      ProjectMenuItem.newFile,
      ProjectMenuItem.newFolder,
      ProjectMenuItem.reveal,
    ]);
  });
}
