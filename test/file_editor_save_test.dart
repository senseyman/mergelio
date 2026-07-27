import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> a) async {
    final r = await svc.run(a, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  Future<String> read(String name) => File('${dir.path}/$name').readAsString();

  RepoActions actions() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c.read(repoActionsProvider(dir.path));
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_fileedit_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${dir.path}/a.txt').writeAsString('one\ntwo\nthree\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('saveFileText refuses while another operation holds the repo', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(busyProvider.notifier).state = BusyState('Fetch');

    // Callers keep the user's text when this reports false, so a refusal that
    // looked like a success would throw the edits away.
    expect(
      await c.read(repoActionsProvider(dir.path)).saveFileText('a.txt', 'no\n'),
      isFalse,
    );
    expect(await read('a.txt'), 'one\ntwo\nthree\n');
  });

  test('saveFileText writes the working tree; undo restores it', () async {
    final a = actions();

    expect(await a.saveFileText('a.txt', 'one\nEDITED\nthree\n'), isTrue);
    expect(await read('a.txt'), 'one\nEDITED\nthree\n');

    await a.undo();
    expect(await read('a.txt'), 'one\ntwo\nthree\n');

    await a.redo();
    expect(await read('a.txt'), 'one\nEDITED\nthree\n');
  });

  test('saveFileText leaves the change unstaged', () async {
    await actions().saveFileText('a.txt', 'one\nEDITED\nthree\n');

    final staged = await svc.run([
      'diff',
      '--cached',
      '--name-only',
    ], repoPath: dir.path);
    expect(staged.out.trim(), isEmpty);

    final unstaged = await svc.run(['diff', '--name-only'], repoPath: dir.path);
    expect(unstaged.out.trim(), 'a.txt');
  });

  test('saveFileText creates a new file; undo removes it', () async {
    final a = actions();

    await a.saveFileText('new.txt', 'hello\n');
    expect(await read('new.txt'), 'hello\n');

    await a.undo();
    expect(File('${dir.path}/new.txt').existsSync(), isFalse);
  });
}
