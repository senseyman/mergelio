// Files mode end to end over a real directory: list it, walk into it, read a
// file for editing, save it back, and check what landed on disk. Git is faked
// — the round trip under test is the filesystem one.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/project_tree.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/project_files.dart';
import 'package:mergelio/state/project_ops_provider.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:path/path.dart' as p;

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late Directory repo;
  late ProviderContainer c;

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_files');
    await Directory(p.join(repo.path, 'lib')).create();
    await File(
      p.join(repo.path, 'lib', 'main.dart'),
    ).writeAsString('void main() {}\n');
    c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_FakeGit())],
    );
  });

  tearDown(() async {
    c.dispose();
    if (repo.existsSync()) await repo.delete(recursive: true);
  });

  Future<Map<String, DirListing>> listing(List<String> dirs) async {
    final loaded = <String, DirListing>{};
    for (final dir in dirs) {
      loaded[dir] = await c.read(
        dirListingProvider(DirKey(repo.path, dir)).future,
      );
    }
    return loaded;
  }

  test('a folder is read when it is expanded, and its file opens', () async {
    final closed = flattenProject(
      loaded: await listing(['']),
      expanded: const {},
    );
    expect(
      closed.whereType<ProjectDirRow>().map((r) => r.path),
      contains('lib'),
    );
    expect(closed.whereType<ProjectFileRow>(), isEmpty);

    final open = flattenProject(
      loaded: await listing(['', 'lib']),
      expanded: const {'lib'},
    );
    expect(open.whereType<ProjectFileRow>().map((r) => r.path), [
      'lib/main.dart',
    ]);

    final file = await c.read(
      editableFileForPathProvider(FileRef(repo.path, 'lib/main.dart')).future,
    );
    expect(file.canEdit, isTrue);
    expect(file.text, 'void main() {}\n');
  });

  test('an edit saved from the editor lands on disk', () async {
    final saved = await c
        .read(repoActionsProvider(repo.path))
        .saveFileText('lib/main.dart', 'void main() { print(1); }\n');

    expect(saved, isTrue);
    expect(
      await File(p.join(repo.path, 'lib', 'main.dart')).readAsString(),
      'void main() { print(1); }\n',
    );
  });

  test(
    'a file created from the navigator is listed and can be opened',
    () async {
      final r = await c
          .read(projectOpsProvider(repo.path))
          .createFile('lib', 'extra.dart');
      expect(r.ok, isTrue);

      c.invalidate(dirListingProvider(DirKey(repo.path, 'lib')));
      final rows = flattenProject(
        loaded: await listing(['', 'lib']),
        expanded: const {'lib'},
      );

      expect(
        rows.whereType<ProjectFileRow>().map((r) => r.path),
        containsAll(['lib/extra.dart', 'lib/main.dart']),
      );
      final file = await c.read(
        editableFileForPathProvider(
          FileRef(repo.path, 'lib/extra.dart'),
        ).future,
      );
      expect(file.canEdit, isTrue);
      expect(file.text, isEmpty);
    },
  );

  test('a rename from the navigator moves the file on disk', () async {
    final r = await c
        .read(projectOpsProvider(repo.path))
        .rename('lib/main.dart', 'app.dart');

    expect(r.path, 'lib/app.dart');
    expect(File(p.join(repo.path, 'lib', 'app.dart')).existsSync(), isTrue);
    expect(File(p.join(repo.path, 'lib', 'main.dart')).existsSync(), isFalse);
  });

  test('a file outside the repository is never opened for editing', () async {
    final outside = await c.read(
      editableFileForPathProvider(FileRef(repo.path, '../escape.txt')).future,
    );

    expect(outside.canEdit, isFalse);
  });

  test('saving to a path outside the repository is refused', () async {
    final saved = await c
        .read(repoActionsProvider(repo.path))
        .saveFileText('../escape.txt', 'nope');

    expect(saved, isFalse);
    expect(
      File(p.join(p.dirname(repo.path), 'escape.txt')).existsSync(),
      isFalse,
    );
  });
}
