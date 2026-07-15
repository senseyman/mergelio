import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/file_tree.dart';

void main() {
  test('groups files into a directory tree, dirs before files, sorted', () {
    final rows = buildFileTree([
      'lib/main.dart',
      'lib/ui/graph/commit_row.dart',
      'lib/ui/graph/graph_view.dart',
      'README.md',
    ], {});

    // Directory 'lib/ui/graph' is compacted (single-child chain), and its
    // files come after the dir; root file README.md sorts after the dir.
    final labels = rows.map((r) {
      if (r is FileDirRow) return 'D:${r.name}(${r.depth})';
      return 'F:${(r as FileLeafRow).name}(${r.depth})';
    }).toList();

    expect(labels, [
      'D:lib(0)',
      'D:ui/graph(1)',
      'F:commit_row.dart(2)',
      'F:graph_view.dart(2)',
      'F:main.dart(1)',
      'F:README.md(0)',
    ]);
  });

  test('a collapsed directory hides its descendants', () {
    final rows = buildFileTree(['lib/a.dart', 'lib/b.dart'], {'lib'});
    expect(rows.length, 1);
    expect((rows.single as FileDirRow).open, isFalse);
  });

  test('leaf paths are the full path; names are the basename', () {
    final rows = buildFileTree(['src/deep/x.txt'], {});
    final leaf = rows.whereType<FileLeafRow>().single;
    expect(leaf.path, 'src/deep/x.txt');
    expect(leaf.name, 'x.txt');
  });

  test('a flat list of root files yields only leaves', () {
    final rows = buildFileTree(['a.txt', 'b.txt'], {});
    expect(rows.every((r) => r is FileLeafRow), isTrue);
    expect(rows.map((r) => (r as FileLeafRow).name), ['a.txt', 'b.txt']);
  });
}
