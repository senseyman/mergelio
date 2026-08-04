// Ignore classification against the real git binary: the navigator dims and
// hides entries on the strength of this, so a fake that answers whatever we
// expect would not tell us the command actually runs.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/project_tree.dart';
import 'package:mergelio/state/project_files.dart';

void main() {
  late Directory repo;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  File file(String name) => File('${repo.path}/$name');

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_ignored_');
    await g(['init', '-q', '-b', 'main']);
    await file('.gitignore').writeAsString('build/\n*.log\n');
    await Directory('${repo.path}/build').create();
    await file('build/out.o').writeAsString('');
    await file('app.log').writeAsString('');
    await file('keep.txt').writeAsString('');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('the ignored children of a directory are reported', () async {
    final c = container();

    final ignored = await c.read(
      ignoredInDirProvider(DirKey(repo.path, '')).future,
    );

    expect(ignored, containsAll(['build', 'app.log']));
    expect(ignored, isNot(contains('keep.txt')));
    expect(ignored, isNot(contains('.gitignore')));
  });

  test('a nested directory is asked about with its own paths', () async {
    final c = container();

    final ignored = await c.read(
      ignoredInDirProvider(DirKey(repo.path, 'build')).future,
    );

    expect(ignored, contains('build/out.o'));
  });

  test('hiding ignored entries drops them from the rows', () async {
    final c = container();
    final listing = await c.read(
      dirListingProvider(DirKey(repo.path, '')).future,
    );
    final ignored = await c.read(
      ignoredInDirProvider(DirKey(repo.path, '')).future,
    );

    final shown = flattenProject(
      loaded: {'': listing},
      expanded: const {},
      hideIgnored: true,
      ignored: ignored,
    );

    expect(shown.map((r) => r.path), contains('keep.txt'));
    expect(shown.map((r) => r.path), isNot(contains('app.log')));
    expect(shown.map((r) => r.path), isNot(contains('build')));
  });

  test('a name git has to quote still comes back as that name', () async {
    // Windows has no such filename to test with.
    if (Platform.isWindows) return;
    await file('quo"te.log').writeAsString('');
    final c = container();

    final ignored = await c.read(
      ignoredInDirProvider(DirKey(repo.path, '')).future,
    );

    expect(ignored, contains('quo"te.log'));
  });
}
