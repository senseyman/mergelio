import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

/// Real git with the host's own configuration shut out, so an installed
/// git-lfs (whose global `filter.lfs.process` wins over anything a repository
/// sets) or a host signing setup cannot change what these tests exercise.
/// Records the timeout each command was given.
class _IsolatedGit implements GitService {
  _IsolatedGit(this.emptyConfig);
  final String emptyConfig;
  final _git = const SystemGitService();
  final timeouts = <({List<String> args, Duration? timeout})>[];

  /// Commands matching this fail without reaching git.
  bool Function(List<String> args)? failWhen;

  Map<String, String> _isolate(Map<String, String>? env) => {
    ...?env,
    'GIT_CONFIG_GLOBAL': emptyConfig,
    'GIT_CONFIG_NOSYSTEM': '1',
  };

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) {
    timeouts.add((args: args, timeout: timeout));
    if (failWhen?.call(args) ?? false) {
      return Future.value(const GitResult(1, '', 'error: injected failure'));
    }
    return _git.run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: _isolate(environment),
      cancel: cancel,
      stdin: stdin,
    );
  }

  @override
  Future<String> version() => _git.version();
  @override
  Future<bool> isRepository(String path) => _git.isRepository(path);
}

void main() {
  late Directory dir;
  late _IsolatedGit git;

  Future<void> g(List<String> args) async {
    final r = await git.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await git.run(args, repoPath: dir.path)).out.trim();

  Future<void> write(String file, String text) =>
      File('${dir.path}/$file').writeAsString('$text\n');

  Future<String> script(String name, String body) async {
    // Beside the repository, not in it, so it never shows as untracked.
    final f = File('${dir.path}_$name');
    await f.writeAsString('#!/bin/sh\n$body\n');
    await Process.run('chmod', ['+x', f.path]);
    addTearDown(() async {
      if (await f.exists()) await f.delete();
    });
    return f.path;
  }

  late ProviderContainer c;
  late RepoActions actions;
  late List<BusyState?> seen;

  List<String> toastTitles() => [
    for (final t in c.read(toastProvider)) t.title,
  ];

  Future<void> cancelWhenOffered() async {
    final until = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(until)) {
      final cancel = seen.lastOrNull?.onCancel;
      if (cancel != null) {
        // Let git get into the slow part first.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return cancel();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Cancel was never offered');
  }

  void open({required bool lfsInstalled}) {
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        lfsToolProvider.overrideWith(
          (ref) async => lfsInstalled ? '3.6.0' : null,
        ),
      ],
    );
    actions = c.read(repoActionsProvider(dir.path));
    seen = [];
    c.listen(busyProvider, (_, next) => seen.add(next));
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_longop_');
    final empty = File('${dir.path}.gitconfig')..writeAsStringSync('');
    addTearDown(() async {
      if (await empty.exists()) await empty.delete();
    });
    git = _IsolatedGit(empty.path);
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    c.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('checkout in a repository using LFS', () {
    /// `topic` changes `0.txt` and adds `00new.txt` (both written first), adds
    /// an LFS file whose smudge takes 20 s, and leaves `same.txt` alone.
    setUp(() async {
      await File('${dir.path}/.gitattributes')
          .writeAsString('*.bin filter=lfs diff=lfs merge=lfs -text\n');
      await g(['config', 'filter.lfs.clean', 'cat']);
      await g(['config', 'filter.lfs.smudge', 'cat']);
      await write('0.txt', 'main');
      await write('same.txt', 'same');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'base']);
      await g(['checkout', '-q', '-b', 'topic']);
      await write('0.txt', 'topic');
      await write('00new.txt', 'new');
      await write('a.bin', 'blob');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'topic']);
      await g(['checkout', '-q', 'main']);
      await g(['config', 'filter.lfs.smudge', 'sleep 20; cat']);
    });

    test('can be cancelled, and leaves the tree as it was', () async {
      open(lfsInstalled: true);
      final watch = Stopwatch()..start();
      final run = actions.checkout('topic');
      await cancelWhenOffered();
      await run;

      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'main');
      // What the stopped checkout had already written is put back.
      expect(await out(['status', '--porcelain']), isEmpty);
      expect(File('${dir.path}/.git/index.lock').existsSync(), isFalse);
      expect(toastTitles(), contains('Checkout topic cancelled'));
      expect(c.read(busyProvider), isNull);

      // And the checkout can simply be tried again.
      await g(['config', 'filter.lfs.smudge', 'cat']);
      await actions.checkout('topic');
      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'topic');
    });

    test('switching ahead of a drag-and-drop merge can be cancelled', () async {
      open(lfsInstalled: true);
      final before = await out(['rev-parse', 'topic']);
      final run = actions.mergeInto('main', 'topic');
      await cancelWhenOffered();
      await run;

      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'main');
      expect(await out(['status', '--porcelain']), isEmpty);
      expect(await out(['rev-parse', 'topic']), before);
      expect(toastTitles(), contains('Checkout topic cancelled'));
      expect(toastTitles(), isNot(contains('Checkout failed')));
      expect(c.read(busyProvider), isNull);
    });

    test('a cancel in post-checkout comes after the checkout landed', () async {
      open(lfsInstalled: true);
      await g(['config', 'filter.lfs.smudge', 'cat']);
      final hook = File('${dir.path}/.git/hooks/post-checkout');
      await hook.writeAsString('#!/bin/sh\nsleep 20\n');
      await Process.run('chmod', ['+x', hook.path]);

      final run = actions.checkout('topic');
      await cancelWhenOffered();
      await run;

      // HEAD and the tree moved before the hook ran, so the checkout is done:
      // reported as cancelled it would hide that, and leave nothing to undo.
      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'topic');
      expect(await out(['status', '--porcelain']), isEmpty);
      expect(toastTitles(), isNot(contains('Checkout topic cancelled')));
      expect(c.read(undoProvider(dir.path)).canUndo, isTrue);
    });

    test('a switch cancelled in post-checkout still stops the merge', () async {
      open(lfsInstalled: true);
      await g(['config', 'filter.lfs.smudge', 'cat']);
      final before = await out(['rev-parse', 'topic']);
      final hook = File('${dir.path}/.git/hooks/post-checkout');
      await hook.writeAsString('#!/bin/sh\nsleep 20\n');
      await Process.run('chmod', ['+x', hook.path]);

      final run = actions.mergeInto('main', 'topic');
      await cancelWhenOffered();
      await run;

      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'topic');
      expect(await out(['rev-parse', 'topic']), before);
      expect(toastTitles(), contains('Checkout topic cancelled'));
      expect(c.read(busyProvider), isNull);
    });

    test('a put-back that fails still reports the cancel', () async {
      open(lfsInstalled: true);
      git.failWhen = (args) => args.contains('--pathspec-from-file=-');
      await g(['update-ref', 'refs/remotes/origin/feature', 'topic']);
      await g(['remote', 'add', 'origin', dir.path]);

      final run = actions.mergeIntoRemote(
        'main',
        const RemoteBranch(remote: 'origin', branch: 'feature'),
      );
      await cancelWhenOffered();
      await run;

      expect(toastTitles(), contains('Checkout origin/feature cancelled'));
      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'main');
      // Not taken for a branch that already existed and tried again.
      expect(
        git.timeouts.where(
          (c) => c.args.first == 'checkout' && c.args.contains('feature'),
        ),
        isEmpty,
      );
    });

    test('a cancel keeps unrelated uncommitted edits', () async {
      open(lfsInstalled: true);
      await write('same.txt', 'mine');
      final run = actions.checkout('topic');
      await cancelWhenOffered();
      await run;

      expect(await out(['status', '--porcelain']), 'M same.txt');
      expect(await File('${dir.path}/same.txt').readAsString(), 'mine\n');
    });

    test('runs under the LFS transfer ceiling', () async {
      open(lfsInstalled: true);
      await g(['config', 'filter.lfs.smudge', 'cat']);
      await actions.checkout('topic');
      final checkout = git.timeouts.lastWhere(
        (c) => c.args.first == 'checkout',
      );
      expect(checkout.timeout, GitWriter.lfsTransferTimeout);
    });

    test('a remote branch checks out under the same ceiling', () async {
      open(lfsInstalled: true);
      await g(['config', 'filter.lfs.smudge', 'cat']);
      // --track wants a configured remote behind the ref, not just the ref.
      await g(['remote', 'add', 'origin', dir.path]);
      await g(['update-ref', 'refs/remotes/origin/feature', 'topic']);
      await actions.checkoutRemote(
        const RemoteBranch(remote: 'origin', branch: 'feature'),
      );
      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'feature');
      final sw = git.timeouts.lastWhere((c) => c.args.first == 'switch');
      expect(sw.timeout, GitWriter.lfsTransferTimeout);
    });

    test('stashing runs under the LFS transfer ceiling', () async {
      open(lfsInstalled: true);
      await g(['config', 'filter.lfs.smudge', 'cat']);
      await write('same.txt', 'mine');
      await actions.stashPush();
      expect(await out(['status', '--porcelain']), isEmpty);
      final stash = git.timeouts.lastWhere((c) => c.args.first == 'stash');
      expect(stash.timeout, GitWriter.lfsTransferTimeout);
    });

    test('without git-lfs it is an ordinary checkout', () async {
      open(lfsInstalled: false);
      await g(['config', 'filter.lfs.smudge', 'cat']);
      await actions.checkout('topic');
      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'topic');
      final checkout = git.timeouts.lastWhere(
        (c) => c.args.first == 'checkout',
      );
      expect(checkout.timeout, isNull);
      expect(
        seen.whereType<BusyState>().every((b) => b.onCancel == null),
        isTrue,
      );
    });
  });

  test('a checkout in a repository without LFS offers no cancel', () async {
    await write('f.txt', 'base');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    await g(['branch', 'topic']);
    open(lfsInstalled: true);
    await actions.checkout('topic');
    expect(await out(['symbolic-ref', '--short', 'HEAD']), 'topic');
    expect(seen.whereType<BusyState>(), isNotEmpty);
    expect(
      seen.whereType<BusyState>().every((b) => b.onCancel == null),
      isTrue,
    );
  });

  group('a signed rebase', () {
    late String fastGpg, slowGpg;

    /// A stand-in gpg: signing prints a well-formed status line and armour;
    /// verifying reports the key as missing, which git reads as signed but
    /// uncheckable (`%G?` E). The slow one stalls only when signing, as a
    /// passphrase prompt would.
    setUp(() async {
      const verify = r'''
case "$*" in *--verify*)
  echo "[GNUPG:] NEWSIG"
  echo "[GNUPG:] ERRSIG 0000000000000000 1 8 00 1792150000 9 -"
  exit 2;;
esac''';
      const sign = '''
cat >/dev/null
echo "[GNUPG:] SIG_CREATED D 1 8 00 0 0" >&2
echo "-----BEGIN PGP SIGNATURE-----"
echo "fake"
echo "-----END PGP SIGNATURE-----"''';
      fastGpg = await script('gpg_fast', '$verify\n$sign');
      slowGpg = await script('gpg_slow', '$verify\nsleep 20\n$sign');
      await g(['config', 'gpg.program', fastGpg]);
      await g(['config', 'user.signingkey', 'TESTKEY']);
      await write('f.txt', 'base');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'base']);
      await g(['checkout', '-q', '-b', 'topic']);
      await write('t.txt', 'topic');
      await g(['add', '.']);
      await g(['commit', '-q', '-S', '-m', 'topic']);
      await g(['checkout', '-q', 'main']);
      await write('m.txt', 'main');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'main']);
    });

    /// Stopped mid-pick, git has staged the pick with nothing recorded that
    /// would commit it, and refuses to continue over it. A rebase left like
    /// that is stuck, so the pick goes back on the list: the tree is clean,
    /// and continuing picks it again.
    Future<void> expectPausedBeforeTheStoppedPick() async {
      expect(Directory('${dir.path}/.git/rebase-merge').existsSync(), isTrue);
      expect(await out(['status', '--porcelain']), isEmpty);
      expect(File('${dir.path}/.git/index.lock').existsSync(), isFalse);
      expect(toastTitles(), contains('Rebase cancelled'));
      expect(toastTitles(), isNot(contains('Rebase failed')));
      expect(c.read(busyProvider), isNull);

      await g(['config', 'gpg.program', fastGpg]);
      await actions.continueOp();
      expect(Directory('${dir.path}/.git/rebase-merge').existsSync(), isFalse);
      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'topic');
      expect(
        await out(['rev-parse', 'topic^']),
        await out(['rev-parse', 'main']),
      );
      expect(await out(['show', 'topic:t.txt']), 'topic');
      expect(await out(['log', '-1', '--format=%G?', 'topic']), 'E');
    }

    test('onto a branch can be cancelled, and continued later', () async {
      open(lfsInstalled: false);
      await g(['config', 'gpg.program', slowGpg]);

      final watch = Stopwatch()..start();
      final run = actions.rebaseOnto('topic', 'main');
      await cancelWhenOffered();
      await run;

      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
      await expectPausedBeforeTheStoppedPick();
    });

    test('of picks alone can be cancelled, and continued later', () async {
      open(lfsInstalled: false);
      await g(['checkout', '-q', 'topic']);
      final pick = await out(['rev-parse', 'HEAD']);
      await g(['config', 'gpg.program', slowGpg]);

      final run = actions.rebase('main', [
        RebaseStep(pick, RebaseAction.pick, sign: true),
      ]);
      await cancelWhenOffered();
      await run;

      await expectPausedBeforeTheStoppedPick();
    });

    test('being continued keeps the resolution when a later pick is '
        'cancelled', () async {
      open(lfsInstalled: false);
      // Conflicts, as intended: both sides rewrite f.txt. The pick after the
      // conflicted one is the one left mid-signing.
      await g(['checkout', '-q', 'topic']);
      await g(['reset', '-q', '--hard', 'HEAD^']);
      await write('f.txt', 'topic');
      await g(['commit', '-q', '-S', '-am', 'topic f']);
      await write('t.txt', 'topic');
      await g(['add', '.']);
      await g(['commit', '-q', '-S', '-m', 'topic']);
      await g(['checkout', '-q', 'main']);
      await write('f.txt', 'main');
      await g(['commit', '-q', '-am', 'main f']);
      await g(['checkout', '-q', 'topic']);
      await git.run(['rebase', '-S', 'main'], repoPath: dir.path);
      await write('f.txt', 'resolved');
      await g(['add', '.']);
      // Signs the resolved commit at once, then stalls on the next one.
      final count = '${dir.path}_gpg_count';
      addTearDown(() async {
        if (await File(count).exists()) await File(count).delete();
      });
      final secondSlow = await script(
        'gpg_second_slow',
        (await File(slowGpg).readAsString()).replaceFirst(
          'sleep 20',
          'n=\$(cat "$count" 2>/dev/null || echo 0); n=\$((n+1)); '
              'echo \$n > "$count"; [ \$n -ge 2 ] && sleep 20',
        ),
      );
      await g(['config', 'gpg.program', secondSlow]);

      final run = actions.continueOp();
      await cancelWhenOffered();
      await run;

      expect(await out(['show', 'HEAD:f.txt']), 'resolved');
      expect(
        toastTitles(),
        contains(allOf(startsWith('Continue rebase'), endsWith('cancelled'))),
      );
      expect(await out(['status', '--porcelain']), isEmpty);
      await g(['config', 'gpg.program', fastGpg]);
      await actions.continueOp();
      expect(Directory('${dir.path}/.git/rebase-merge').existsSync(), isFalse);
      expect(await out(['show', 'topic:f.txt']), 'resolved');
      expect(await out(['show', 'topic:t.txt']), 'topic');
    });

    test('being continued can be cancelled', () async {
      open(lfsInstalled: false);
      // Conflicts, as intended: both sides rewrite f.txt.
      await g(['checkout', '-q', 'topic']);
      await write('f.txt', 'topic');
      await g(['commit', '-q', '-S', '-am', 'topic f']);
      await g(['checkout', '-q', 'main']);
      await write('f.txt', 'main');
      await g(['commit', '-q', '-am', 'main f']);
      await g(['checkout', '-q', 'topic']);
      await git.run(['rebase', '-S', 'main'], repoPath: dir.path);
      expect(
        File('${dir.path}/.git/rebase-merge/gpg_sign_opt').existsSync(),
        isTrue,
      );
      await write('f.txt', 'resolved');
      await g(['add', '.']);
      await g(['config', 'gpg.program', slowGpg]);

      final watch = Stopwatch()..start();
      final run = actions.continueOp();
      await cancelWhenOffered();
      await run;

      expect(watch.elapsed, lessThan(const Duration(seconds: 15)));
      expect(
        toastTitles(),
        contains(allOf(startsWith('Continue rebase'), endsWith('cancelled'))),
      );
      expect(c.read(busyProvider), isNull);
      // Still stopped where it was, so it can be continued again.
      expect(Directory('${dir.path}/.git/rebase-merge').existsSync(), isTrue);
      expect(File('${dir.path}/.git/index.lock').existsSync(), isFalse);
      await g(['config', 'gpg.program', fastGpg]);
      await actions.continueOp();
      expect(Directory('${dir.path}/.git/rebase-merge').existsSync(), isFalse);
      expect(await out(['symbolic-ref', '--short', 'HEAD']), 'topic');
      expect(await out(['show', 'topic:f.txt']), 'resolved');
    });
  });
}
