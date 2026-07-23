import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> a) async {
    final r = await svc.run(a, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  Future<String> read(String name) => File('${dir.path}/$name').readAsString();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_discard_');
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

  test(
    'discardFile reverts a tracked file to HEAD; undo restores work + index',
    () async {
      // Stage one edit, then add an unstaged edit on top.
      await File('${dir.path}/a.txt').writeAsString('one\nTWO\nthree\n');
      await g(['add', 'a.txt']);
      await File('${dir.path}/a.txt').writeAsString('one\nTWO\nTHREE\n');

      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      await actions.discardFile(
        const WorkingFile(
          path: 'a.txt',
          index: GitChange.modified,
          worktree: GitChange.modified,
        ),
      );
      expect(await read('a.txt'), 'one\ntwo\nthree\n'); // back to HEAD

      await actions.undo();
      expect(await read('a.txt'), 'one\nTWO\nTHREE\n'); // work restored
      // The staged edit is back in the index.
      expect(
        (await svc.run([
          'diff',
          '--cached',
          '--name-only',
        ], repoPath: dir.path)).out,
        'a.txt',
      );
    },
  );

  test('discardFile deletes an untracked file; undo recreates it', () async {
    await File('${dir.path}/new.txt').writeAsString('hi\n');
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await actions.discardFile(
      const WorkingFile(path: 'new.txt', worktree: GitChange.untracked),
    );
    expect(await File('${dir.path}/new.txt').exists(), isFalse);

    await actions.undo();
    expect(await read('new.txt'), 'hi\n');
  });

  test(
    'discardHunk reverts one hunk in the working tree; undo restores it',
    () async {
      // Make an edit to capture a real patch via git diff.
      await File('${dir.path}/a.txt').writeAsString('ONE\ntwo\nthree\n');

      // Capture the patch from git diff.
      final patch = (await svc.run([
        'diff',
        '--',
        'a.txt',
      ], repoPath: dir.path)).stdout;

      // Reset the file to HEAD so we can test the discard.
      await g(['checkout', '--', 'a.txt']);

      // Re-apply the edit.
      await File('${dir.path}/a.txt').writeAsString('ONE\ntwo\nthree\n');

      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      await actions.discardHunk(patch);
      expect(await read('a.txt'), 'one\ntwo\nthree\n');

      await actions.undo();
      expect(await read('a.txt'), 'ONE\ntwo\nthree\n');
    },
  );

  test('discardHunk reverts only the targeted hunk, leaving others', () async {
    final lines = List.generate(15, (i) => 'l${i + 1}');
    await File('${dir.path}/b.txt').writeAsString('${lines.join('\n')}\n');
    await g(['add', 'b.txt']);
    await g(['commit', '-q', '-m', 'b']);

    // Capture a one-hunk patch that only touches line 2.
    await File(
      '${dir.path}/b.txt',
    ).writeAsString('${([...lines]..[1] = 'TOP').join('\n')}\n');
    final patch = (await svc.run([
      'diff',
      '--',
      'b.txt',
    ], repoPath: dir.path)).stdout;
    await g(['checkout', '--', 'b.txt']);

    // Now edit both line 2 and line 14 — two separate hunks.
    await File('${dir.path}/b.txt').writeAsString(
      '${([...lines]
        ..[1] = 'TOP'
        ..[13] = 'BOTTOM').join('\n')}\n',
    );

    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(repoActionsProvider(dir.path)).discardHunk(patch);

    // Line 2 reverted, line 14 untouched.
    expect(
      await read('b.txt'),
      '${([...lines]..[13] = 'BOTTOM').join('\n')}\n',
    );
  });
}
