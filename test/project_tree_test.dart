// Flattening is pure over what has been loaded so far: a directory the user
// has not opened has unknown contents, which is why this cannot reuse the
// changed-file tree builder.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/project_tree.dart';
import 'package:mergelio/state/project_files.dart';

DirListing _dir(List<String> dirs, List<String> files, {int truncated = 0}) =>
    DirListing(
      entries: [
        for (final d in dirs) DirEntry(name: d, isDir: true),
        for (final f in files) DirEntry(name: f, isDir: false),
      ],
      truncated: truncated,
    );

List<String> _labels(List<ProjectRow> rows) => [
  for (final r in rows)
    switch (r) {
      ProjectDirRow() => 'D:${r.name}(${r.depth})${r.open ? '+' : '-'}',
      ProjectFileRow() => 'F:${r.name}(${r.depth})',
      ProjectLoadingRow() => 'L:${r.path}(${r.depth})',
      ProjectMoreRow() => 'M:${r.count}(${r.depth})',
      ProjectErrorRow() => 'E:${r.message}(${r.depth})',
    },
];

void main() {
  test('an unloaded root is a single loading row', () {
    final rows = flattenProject(loaded: {}, expanded: {});
    expect(_labels(rows), ['L:(0)']);
  });

  test('collapsed directories emit no children', () {
    final rows = flattenProject(
      loaded: {
        '': _dir(['lib'], ['README.md']),
        'lib': _dir([], ['main.dart']),
      },
      expanded: {},
    );
    expect(_labels(rows), ['D:lib(0)-', 'F:README.md(0)']);
  });

  test('expanded directories emit their loaded children at greater depth', () {
    final rows = flattenProject(
      loaded: {
        '': _dir(['lib'], ['README.md']),
        'lib': _dir(['ui'], ['main.dart']),
        'lib/ui': _dir([], ['app.dart']),
      },
      expanded: {'lib', 'lib/ui'},
    );
    expect(_labels(rows), [
      'D:lib(0)+',
      'D:ui(1)+',
      'F:app.dart(2)',
      'F:main.dart(1)',
      'F:README.md(0)',
    ]);
  });

  test('a directory chain is never compacted', () {
    // buildFileTree would render this as one "lib/ui/graph" row. Here each
    // level must stay separately expandable, since its children are unknown
    // until it is opened.
    final rows = flattenProject(
      loaded: {
        '': _dir(['lib'], []),
        'lib': _dir(['ui'], []),
      },
      expanded: {'lib'},
    );
    expect(_labels(rows), ['D:lib(0)+', 'D:ui(1)-']);
  });

  test('an expanded but unloaded directory emits a loading row', () {
    final rows = flattenProject(
      loaded: {
        '': _dir(['lib'], []),
      },
      expanded: {'lib'},
    );
    expect(_labels(rows), ['D:lib(0)+', 'L:lib(1)']);
  });

  test('a truncated listing appends a "more" row after its entries', () {
    final rows = flattenProject(
      loaded: {
        '': _dir([], ['a.txt'], truncated: 12),
      },
      expanded: {},
    );
    expect(_labels(rows), ['F:a.txt(0)', 'M:12(0)']);
  });

  test('a listing error replaces that directory\'s children', () {
    final rows = flattenProject(
      loaded: {
        '': _dir(['secret'], []),
        'secret': const DirListing(error: 'Permission denied'),
      },
      expanded: {'secret'},
    );
    expect(_labels(rows), ['D:secret(0)+', 'E:Permission denied(1)']);
  });

  test('rows carry full repo-relative paths', () {
    final rows = flattenProject(
      loaded: {
        '': _dir(['lib'], []),
        'lib': _dir([], ['main.dart']),
      },
      expanded: {'lib'},
    );
    expect(rows.map((r) => r.path), ['lib', 'lib/main.dart']);
  });

  test('hideIgnored drops ignored entries', () {
    final rows = flattenProject(
      loaded: {
        '': _dir(['build'], ['a.txt']),
      },
      expanded: {},
      hideIgnored: true,
      ignored: {'build'},
    );
    expect(_labels(rows), ['F:a.txt(0)']);
  });

  test('ignored entries are kept when hideIgnored is off', () {
    final rows = flattenProject(
      loaded: {
        '': _dir(['build'], ['a.txt']),
      },
      expanded: {},
      ignored: {'build'},
    );
    expect(_labels(rows), ['D:build(0)-', 'F:a.txt(0)']);
  });
}
