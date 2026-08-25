import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out;

  Future<String> commit(String file, String content, String msg) async {
    await File('${dir.path}/$file').writeAsString(content);
    await g(['add', '.']);
    await g(['commit', '-q', '-m', msg]);
    return out(['rev-parse', 'HEAD']);
  }

  /// Configures the repository to sign with a throwaway ssh key, or returns
  /// false when there is no ssh-keygen to make one with.
  Future<bool> enableSshSigning() async {
    final key = '${dir.path}/signing_key';
    final gen = await Process.run('ssh-keygen', [
      '-t',
      'ed25519',
      '-N',
      '',
      '-q',
      '-f',
      key,
    ]);
    if (gen.exitCode != 0) return false;
    final allowed = File('${dir.path}/allowed_signers');
    await allowed.writeAsString(
      't@example.com ${await File('$key.pub').readAsString()}',
    );
    await g(['config', 'gpg.format', 'ssh']);
    await g(['config', 'user.signingkey', '$key.pub']);
    await g(['config', 'gpg.ssh.allowedSignersFile', allowed.path]);
    return true;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_rflow_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a clean rebase reorders history and is undoable', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('base.txt', 'base\n', 'base');
    final c1 = await commit('f1.txt', '1\n', 'C1');
    final c2 = await commit('f2.txt', '2\n', 'C2');

    await actions.rebase(base, [
      RebaseStep(c2, RebaseAction.pick),
      RebaseStep(c1, RebaseAction.pick),
    ]);

    expect((await out(['log', '--format=%s'])).split('\n'), [
      'C1',
      'C2',
      'base',
    ]);
    expect(c.read(mergeSessionProvider(dir.path)), isNull);

    // Undoable back to the original order.
    await actions.undo();
    expect((await out(['log', '--format=%s'])).split('\n'), [
      'C2',
      'C1',
      'base',
    ]);
  });

  test(
    'a conflicting rebase opens the tool in rebase mode; finish continues',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      // base → A (edits x) → B (edits x again). Reorder B before A conflicts.
      final base = await commit('x.txt', 'base\n', 'base');
      final a = await commit('x.txt', 'A\n', 'A');
      final b = await commit('x.txt', 'B\n', 'B');

      await actions.rebase(base, [
        RebaseStep(b, RebaseAction.pick),
        RebaseStep(a, RebaseAction.pick),
      ]);

      expect(c.read(mergeSessionProvider(dir.path))?.kind, MergeKind.rebase);

      // Resolve each conflict round to "theirs" until the rebase completes
      // (reordered picks conflict twice here).
      var guard = 0;
      while (c.read(mergeSessionProvider(dir.path)) != null && guard++ < 5) {
        var session = c.read(mergeSessionProvider(dir.path))!;
        for (var i = 0; i < session.files.length; i++) {
          var file = session.files[i];
          for (final h in file.hunkIndices) {
            file = file.withResolution(h, Resolution.theirs);
          }
          session = session.replaceFile(i, file);
        }
        await actions.finishMerge(session);
      }

      // Rebase completed: session cleared and no rebase is in progress.
      expect(c.read(mergeSessionProvider(dir.path)), isNull);
      expect(Directory('${dir.path}/.git/rebase-merge').existsSync(), isFalse);
    },
  );

  test('moving commits as-is onto a diverged base replays them', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'feature']);
    await commit('f1.txt', '1\n', 'C1');
    await g(['checkout', '-q', 'main']);
    final mainTip = await commit('m.txt', 'm\n', 'M1');
    await g(['checkout', '-q', 'feature']);

    final steps = await actions.rebaseStepsFrom(mainTip);
    final plan = applyPreset(steps, RebasePreset.asIs);

    // The plan is all picks, but the base is not on this branch: replaying it
    // is the whole point of the rebase, not a no-op.
    expect(await actions.isRebaseRedundant(mainTip, steps, plan), isFalse);

    await actions.rebase(mainTip, plan);

    expect((await out(['log', '--format=%s'])).split('\n'), [
      'C1',
      'M1',
      'base',
    ]);
  });

  test(
    'an unchanged plan onto a commit already behind HEAD is redundant',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      final base = await commit('base.txt', 'base\n', 'base');
      await commit('f1.txt', '1\n', 'C1');
      await commit('f2.txt', '2\n', 'C2');

      final steps = await actions.rebaseStepsFrom(base);
      final plan = applyPreset(steps, RebasePreset.asIs);

      expect(await actions.isRebaseRedundant(base, steps, plan), isTrue);
    },
  );

  test('an edited plan is never redundant, ancestor base or not', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('base.txt', 'base\n', 'base');
    await commit('f1.txt', '1\n', 'C1');
    await commit('f2.txt', '2\n', 'C2');

    final steps = await actions.rebaseStepsFrom(base);
    final squashed = applyPreset(steps, RebasePreset.squashAll);

    expect(await actions.isRebaseRedundant(base, steps, squashed), isFalse);
  });

  test('a rebase that fails outright leaves no rebase in progress', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('base.txt', 'base\n', 'base');
    final c1 = await commit('f1.txt', '1\n', 'C1');
    final c2 = await commit('f2.txt', '2\n', 'C2');
    final before = await out(['rev-parse', 'HEAD']);

    // git refuses a todo that squashes with nothing above it, and would
    // otherwise leave .git/rebase-merge behind to poison every later rebase.
    await actions.rebase(base, [
      RebaseStep(c1, RebaseAction.squash),
      RebaseStep(c2, RebaseAction.fixup),
    ]);

    expect(await actions.isRebaseInProgress(), isFalse);
    expect(Directory('${dir.path}/.git/rebase-merge').existsSync(), isFalse);
    expect(await out(['rev-parse', 'HEAD']), before);
    expect(c.read(mergeSessionProvider(dir.path)), isNull);
  });

  test('a rebase started elsewhere is left alone, not clobbered', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('base.txt', 'base\n', 'base');
    final c1 = await commit('f1.txt', '1\n', 'C1');

    // Stop a rebase midway, the way a terminal session would.
    final r = await svc.run(
      ['rebase', '-i', base],
      repoPath: dir.path,
      environment: {
        'GIT_SEQUENCE_EDITOR': "printf 'break\npick $c1\n' >",
        'GIT_EDITOR': 'true',
      },
    );
    expect(r.ok, isTrue, reason: r.err);
    expect(await actions.isRebaseInProgress(), isTrue);

    await actions.rebase(base, [RebaseStep(c1, RebaseAction.pick)]);

    // The in-flight rebase is somebody else's; refuse rather than abort it.
    expect(await actions.isRebaseInProgress(), isTrue);
    expect(
      (await out(['rev-parse', '--git-path', 'rebase-merge'])).isNotEmpty,
      isTrue,
    );
  });

  test(
    'a range containing a merge commit is refused before it starts',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final actions = c.read(repoActionsProvider(dir.path));

      final base = await commit('base.txt', 'base\n', 'base');
      await g(['checkout', '-q', '-b', 'side']);
      await commit('side.txt', 's\n', 'S1');
      await g(['checkout', '-q', 'main']);
      await commit('m.txt', 'm\n', 'M1');
      await g(['merge', '--no-ff', '-m', 'Merge side', 'side']);

      // A linear todo cannot express a merge; git refuses one that names it.
      expect(await actions.rebaseCrossesMerge(base), isTrue);
    },
  );

  test('a linear range crosses no merge', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('base.txt', 'base\n', 'base');
    await commit('f1.txt', '1\n', 'C1');

    expect(await actions.rebaseCrossesMerge(base), isFalse);
  });

  test('an empty base checks the whole history for merges', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'side']);
    await commit('side.txt', 's\n', 'S1');
    await g(['checkout', '-q', 'main']);
    await commit('m.txt', 'm\n', 'M1');
    await g(['merge', '--no-ff', '-m', 'Merge side', 'side']);

    // The reword path passes '' for a root commit, which git spells 'HEAD'.
    expect(await actions.rebaseCrossesMerge(''), isTrue);
  });

  test('replaying signed commits keeps them signed', () async {
    if (!await enableSshSigning()) return;

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    final base = await commit('base.txt', 'base\n', 'base');
    await g(['config', 'commit.gpgsign', 'true']);
    await commit('f1.txt', '1\n', 'C1');
    await commit('f2.txt', '2\n', 'C2');
    // Only the rebase itself may ask for signatures from here on, so a
    // signature on a replayed commit can only have come from the plan.
    await g(['config', 'commit.gpgsign', 'false']);

    final steps = await actions.rebaseStepsFrom(base);
    expect(steps.map((s) => s.sign), [true, true]);

    await actions.rebase(base, steps.reversed.toList());

    expect((await out(['log', '--format=%G? %s'])).split('\n'), [
      'G C1',
      'G C2',
      'N base',
    ]);
  });

  test('a drag-and-drop rebase keeps signatures too', () async {
    if (!await enableSshSigning()) return;

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'side']);
    await g(['config', 'commit.gpgsign', 'true']);
    await commit('side.txt', 's\n', 'S1');
    // Only the rebase itself may ask for signatures from here on.
    await g(['config', 'commit.gpgsign', 'false']);
    await g(['checkout', '-q', 'main']);
    await commit('m.txt', 'm\n', 'M1');
    await g(['checkout', '-q', 'side']);

    await actions.rebaseOnto('side', 'main');

    expect((await out(['log', '--format=%G? %s'])).split('\n'), [
      'G S1',
      'N M1',
      'N base',
    ]);
  });

  test('a drag-and-drop rebase says when it flattened merges', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'side']);
    await commit('side.txt', 's\n', 'S1');
    await g(['checkout', '-q', 'main']);
    await commit('m.txt', 'm\n', 'M1');
    await g(['checkout', '-q', 'side']);
    // A branch that merged main in at some point, then carried on.
    await g(['merge', '--no-ff', '-m', 'Merge main', 'main']);
    await commit('side2.txt', 's2\n', 'S2');
    await g(['checkout', '-q', 'main']);
    await commit('m2.txt', 'm2\n', 'M2');

    await actions.rebaseOnto('side', 'main');

    // git replays the range without the merge, so the branch comes out linear.
    expect((await out(['log', '--format=%s'])).split('\n'), [
      'S2',
      'S1',
      'M2',
      'M1',
      'base',
    ]);
    final toast = c
        .read(toastProvider)
        .lastWhere((t) => t.title == 'Rebase complete');
    expect(toast.description, contains('merge'));
  });

  test('a rebase with no merges to flatten says nothing about them', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final actions = c.read(repoActionsProvider(dir.path));

    await commit('base.txt', 'base\n', 'base');
    await g(['checkout', '-q', '-b', 'side']);
    await commit('side.txt', 's\n', 'S1');
    await g(['checkout', '-q', 'main']);
    await commit('m.txt', 'm\n', 'M1');

    await actions.rebaseOnto('side', 'main');

    final toast = c
        .read(toastProvider)
        .lastWhere((t) => t.title == 'Rebase complete');
    expect(toast.description, isNull);
  });
}
