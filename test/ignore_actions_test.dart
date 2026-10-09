import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/ignore.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> a) async {
    final r = await svc.run(a, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  File f(String name) => File('${dir.path}/$name');

  Future<void> put(String name, String text) async {
    await f(name).parent.create(recursive: true);
    await f(name).writeAsString(text);
  }

  Future<bool> ignored(String path) async =>
      (await svc.run(['check-ignore', '-q', path], repoPath: dir.path)).ok;

  late ProviderContainer c;
  RepoActions actions() => c.read(repoActionsProvider(dir.path));

  setUp(() async {
    c = ProviderContainer();
    dir = await Directory.systemTemp.createTemp('mergelio_ignore_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await put('a.txt', 'a\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
  });

  tearDown(() async {
    c.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('creates the root .gitignore; undo removes it, redo adds it', () async {
    await put('logs/x.log', 'x');
    final a = actions();

    expect(
      await a.addIgnoreRule('logs/x.log', IgnoreScope.file, IgnoreTarget.root),
      isTrue,
    );
    expect(await f('.gitignore').readAsString(), '/logs/x.log\n');
    expect(await ignored('logs/x.log'), isTrue);

    await a.undo();
    expect(f('.gitignore').existsSync(), isFalse);

    await a.redo();
    expect(await f('.gitignore').readAsString(), '/logs/x.log\n');
  });

  test('appends to an existing file; undo restores its exact bytes', () async {
    await put('.gitignore', 'build/'); // no final newline
    await put('x.log', 'x');
    final a = actions();

    await a.addIgnoreRule('x.log', IgnoreScope.extension, IgnoreTarget.root);
    expect(await f('.gitignore').readAsString(), 'build/\n*.log\n');

    await a.undo();
    expect(await f('.gitignore').readAsString(), 'build/');
  });

  test('writes nothing and records no undo when the rule is there', () async {
    await put('.gitignore', '*.log\n');
    await put('x.log', 'x');
    final a = actions();

    expect(
      await a.addIgnoreRule('x.log', IgnoreScope.extension, IgnoreTarget.root),
      isTrue,
    );
    expect(await f('.gitignore').readAsString(), '*.log\n');
    expect(c.read(undoProvider(dir.path)).past, isEmpty);
  });

  test('writes relative to the nearest nested .gitignore', () async {
    await put('pkg/.gitignore', '');
    await put('pkg/gen/out.dart', 'x');
    final a = actions();

    expect(await a.nearestIgnoreDir('pkg/gen/out.dart'), 'pkg');
    expect(
      await a.addIgnoreRule(
        'pkg/gen/out.dart',
        IgnoreScope.folder,
        IgnoreTarget.nearest,
      ),
      isTrue,
    );
    expect(await f('pkg/.gitignore').readAsString(), '/gen/\n');
    expect(await ignored('pkg/gen/out.dart'), isTrue);
  });

  test('nearestIgnoreDir is null with only a root .gitignore', () async {
    await put('.gitignore', '');
    await put('pkg/x.txt', 'x');
    final a = actions();

    expect(await a.nearestIgnoreDir('pkg/x.txt'), isNull);
    expect(
      await a.addIgnoreRule(
        'pkg/x.txt',
        IgnoreScope.file,
        IgnoreTarget.nearest,
      ),
      isFalse,
    );
  });

  test('writes .git/info/exclude and leaves .gitignore alone', () async {
    await put('secret.txt', 'x');
    final a = actions();

    await a.addIgnoreRule('secret.txt', IgnoreScope.file, IgnoreTarget.exclude);
    expect(
      await f('.git/info/exclude').readAsString(),
      endsWith('/secret.txt\n'),
    );
    expect(f('.gitignore').existsSync(), isFalse);
    expect(await ignored('secret.txt'), isTrue);
  });

  test('creates info/ when the clone has none', () async {
    await Directory('${dir.path}/.git/info').delete(recursive: true);
    await put('secret.txt', 'x');

    await actions().addIgnoreRule(
      'secret.txt',
      IgnoreScope.file,
      IgnoreTarget.exclude,
    );
    expect(await f('.git/info/exclude').readAsString(), '/secret.txt\n');
  });

  test('leaves the new rule unstaged', () async {
    await put('x.log', 'x');
    await actions().addIgnoreRule('x.log', IgnoreScope.file, IgnoreTarget.root);

    final staged = await svc.run([
      'diff',
      '--cached',
      '--name-only',
    ], repoPath: dir.path);
    expect(staged.out.trim(), isEmpty);
  });

  test('refuses paths that are not plain repo-relative paths', () async {
    final a = actions();
    for (final bad in ['../x.txt', '/etc/passwd', r'C:\x', 'a/../../x']) {
      expect(
        await a.addIgnoreRule(bad, IgnoreScope.file, IgnoreTarget.root),
        isFalse,
        reason: bad,
      );
    }
    expect(f('.gitignore').existsSync(), isFalse);
  });

  test('refuses a .gitignore symlinked outside the repository', () async {
    final outside = await Directory.systemTemp.createTemp('mergelio_out_');
    addTearDown(() => outside.delete(recursive: true));
    final target = File('${outside.path}/victim')..writeAsStringSync('keep\n');
    await Link('${dir.path}/.gitignore').create(target.path);
    await put('x.log', 'x');

    expect(
      await actions().addIgnoreRule(
        'x.log',
        IgnoreScope.file,
        IgnoreTarget.root,
      ),
      isFalse,
    );
    expect(target.readAsStringSync(), 'keep\n');
  });

  test('refuses while a working-tree operation runs', () async {
    c.read(busyProvider.notifier).state = const BusyState('Pull');
    await put('x.log', 'x');

    expect(
      await actions().addIgnoreRule(
        'x.log',
        IgnoreScope.file,
        IgnoreTarget.root,
      ),
      isFalse,
    );
    expect(f('.gitignore').existsSync(), isFalse);
  });
}
