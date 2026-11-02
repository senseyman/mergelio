import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

import 'support/hermetic_git.dart';

/// Rename, detached checkout and branch-from-tag, against a real repo.
void main() {
  late Directory dir;
  const svc = HermeticGit();

  Future<void> g(List<String> args, {String? stdin}) async {
    final r = await svc.run(args, repoPath: dir.path, stdin: stdin);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out;

  Future<void> commit(String msg) async {
    await File('${dir.path}/a.txt').writeAsString('$msg\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', msg]);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_tagconv_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    await g(['config', 'tag.gpgSign', 'false']);
    await commit('A');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(c.dispose);
    return c;
  }

  RepoActions actionsOf(ProviderContainer c) =>
      c.read(repoActionsProvider(dir.path));

  Future<List<String>> tags() => GitReader(svc, dir.path).tags();

  group('renameTag', () {
    test('moves a lightweight tag; undo and redo follow', () async {
      final c = container();
      final actions = actionsOf(c);
      await g(['tag', 'v1']);
      final sha = await out(['rev-parse', 'HEAD']);

      await actions.renameTag('v1', 'v2');
      expect(await tags(), ['v2']);
      expect(await out(['rev-parse', 'refs/tags/v2']), sha);

      await actions.undo();
      expect(await tags(), ['v1']);
      expect(await out(['rev-parse', 'refs/tags/v1']), sha);

      await actions.redo();
      expect(await tags(), ['v2']);
    });

    test('an annotated tag carries its new name, message and tagger', () async {
      final c = container();
      final actions = actionsOf(c);
      await g(['tag', '-a', 'v1', '-m', 'release notes']);
      final before = await out(['rev-parse', 'refs/tags/v1']);
      final tagger = await out([
        'for-each-ref',
        '--format=%(taggername) %(taggeremail) %(taggerdate:raw)',
        'refs/tags/v1',
      ]);

      await actions.renameTag('v1', 'v2');

      expect(await tags(), ['v2']);
      // The object's own name matches the ref, so describe does not report
      // the tag as "externally known as" its old name.
      expect(await out(['cat-file', 'tag', 'v2']), contains('\ntag v2\n'));
      expect(
        await out(['for-each-ref', '--format=%(contents)', 'refs/tags/v2']),
        'release notes',
      );
      expect(
        await out([
          'for-each-ref',
          '--format=%(taggername) %(taggeremail) %(taggerdate:raw)',
          'refs/tags/v2',
        ]),
        tagger,
      );
      expect(
        await out(['rev-parse', 'v2^{commit}']),
        await out(['rev-parse', 'HEAD']),
      );

      await actions.undo();
      // Undo brings back the very same object, not a lookalike.
      expect(await tags(), ['v1']);
      expect(await out(['rev-parse', 'refs/tags/v1']), before);
    });

    test(
      'a signed tag keeps its object, so the signature stays valid',
      () async {
        final c = container();
        final actions = actionsOf(c);
        final head = await out(['rev-parse', 'HEAD']);
        // A signature block is recognised by its shape; no signer is needed.
        final r = await svc.run(
          ['mktag'],
          repoPath: dir.path,
          stdin:
              'object $head\n'
              'type commit\n'
              'tag v1\n'
              'tagger Tester <t@example.com> 1700000000 +0000\n'
              '\n'
              'release\n'
              '-----BEGIN PGP SIGNATURE-----\n'
              '\n'
              'AAAA\n'
              '-----END PGP SIGNATURE-----\n',
        );
        expect(r.ok, isTrue, reason: r.err);
        final signed = r.out;
        await g(['update-ref', 'refs/tags/v1', signed]);

        await actions.renameTag('v1', 'v2');

        expect(await tags(), ['v2']);
        expect(await out(['rev-parse', 'refs/tags/v2']), signed);
      },
    );

    test('an existing target name is refused and nothing moves', () async {
      final c = container();
      final actions = actionsOf(c);
      await g(['tag', 'v1']);
      await commit('B');
      await g(['tag', 'v2']);
      final v2 = await out(['rev-parse', 'refs/tags/v2']);

      await actions.renameTag('v1', 'v2');

      expect(await tags(), ['v1', 'v2']);
      expect(await out(['rev-parse', 'refs/tags/v2']), v2);
      expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
    });

    test('an invalid new name is refused and nothing moves', () async {
      final c = container();
      final actions = actionsOf(c);
      await g(['tag', '-a', 'v1', '-m', 'msg']);

      await actions.renameTag('v1', 'bad name..');

      expect(await tags(), ['v1']);
      expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
      // Named as a bad name, not as whatever git said about it.
      final toast = c.read(toastProvider).last;
      expect(toast.kind, ToastKind.error);
      expect(toast.title, '"bad name.." is not a valid tag name');
    });
  });

  group('checkoutTag', () {
    test('detaches at the tag even when a branch has the same name', () async {
      final c = container();
      final actions = actionsOf(c);
      await g(['tag', '-a', 'v1', '-m', 'msg']);
      final tagged = await out(['rev-parse', 'HEAD']);
      await commit('B');
      // A branch named like the tag: plain `git checkout v1` would pick it.
      await g(['branch', 'v1']);

      await actions.checkoutTag('v1');

      expect(await out(['rev-parse', 'HEAD']), tagged);
      expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'HEAD');

      await actions.undo();
      expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'main');
    });
  });

  group('createBranchFromTag', () {
    test('points the branch at the tagged commit; undo removes it', () async {
      final c = container();
      final actions = actionsOf(c);
      await g(['tag', '-a', 'v1', '-m', 'msg']);
      final tagged = await out(['rev-parse', 'HEAD']);
      await commit('B');

      await actions.createBranchFromTag('fix', 'v1');

      expect(await out(['rev-parse', 'refs/heads/fix']), tagged);
      // Not switched to: this matches "Create branch here" on a commit.
      expect(await out(['rev-parse', '--abbrev-ref', 'HEAD']), 'main');

      await actions.undo();
      expect(
        (await svc.run([
          'rev-parse',
          '--verify',
          '-q',
          'refs/heads/fix',
        ], repoPath: dir.path)).ok,
        isFalse,
      );
    });

    test('redo still works after the tag is gone', () async {
      final c = container();
      final actions = actionsOf(c);
      await g(['tag', 'v1']);
      final tagged = await out(['rev-parse', 'HEAD']);

      await actions.createBranchFromTag('fix', 'v1');
      await actions.undo();
      await g(['tag', '-d', 'v1']);
      await actions.redo();

      expect(await out(['rev-parse', 'refs/heads/fix']), tagged);
    });
  });
}
