// Files mode refreshes only the directories a filesystem event touched, so a
// save in one folder does not re-list the whole project.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/project_watch.dart';

void main() {
  test('a changed file marks the directory holding it', () {
    expect(changedDirOf('/r', '/r/lib/main.dart'), 'lib');
  });

  test('a change at the root marks the root', () {
    expect(changedDirOf('/r', '/r/README.md'), '');
  });

  test('a nested change marks only its own directory', () {
    expect(changedDirOf('/r', '/r/lib/ui/files/view.dart'), 'lib/ui/files');
  });

  test('a windows-shaped path is understood too', () {
    expect(changedDirOf(r'C:\r', r'C:\r\lib\main.dart'), 'lib');
  });

  test('a path outside the repository marks nothing', () {
    expect(changedDirOf('/r', '/elsewhere/a.txt'), isNull);
  });

  test('a sibling repository with a shared prefix marks nothing', () {
    // `/r2` starts with `/r`, and a prefix test alone would claim it.
    expect(changedDirOf('/r', '/r2/a.txt'), isNull);
  });

  test('git machinery marks nothing', () {
    // .git changes drive the repository read, not the file listing.
    expect(changedDirOf('/r', '/r/.git/index'), isNull);
  });

  test('the repository directory itself marks nothing', () {
    expect(changedDirOf('/r', '/r'), isNull);
  });

  test('a changed file is reported repo-relative', () {
    expect(relPathOf('/r', '/r/lib/main.dart'), 'lib/main.dart');
  });

  test('a windows-shaped path is made repo-relative too', () {
    expect(relPathOf(r'C:\r', r'C:\r\lib\main.dart'), 'lib/main.dart');
  });

  test('paths outside the repository and git machinery report nothing', () {
    expect(relPathOf('/r', '/elsewhere/a.txt'), isNull);
    expect(relPathOf('/r', '/r2/a.txt'), isNull);
    expect(relPathOf('/r', '/r/.git/index'), isNull);
    expect(relPathOf('/r', '/r'), isNull);
  });
}
