import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args, {String? at}) async {
    final r = await svc.run(args, repoPath: at ?? dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> out(List<String> args) async =>
      (await svc.run(args, repoPath: dir.path)).out;

  Future<String> commit(String file, String msg) async {
    await File('${dir.path}/$file').writeAsString('$msg\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', msg]);
    return out(['rev-parse', 'HEAD']);
  }

  Future<List<String>> subjects() async =>
      (await out(['log', '--format=%s'])).split('\n');

  bool rebasing() => Directory('${dir.path}/.git/rebase-merge').existsSync();

  late ProviderContainer c;
  late RepoActions actions;
  late String base, c1, c2;

  List<String> toastTitles() => [
    for (final t in c.read(toastProvider)) t.title,
  ];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_rbexecflow_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    base = await commit('base.txt', 'base');
    c1 = await commit('f1.txt', 'C1');
    c2 = await commit('f2.txt', 'C2');
    c = ProviderContainer();
    actions = c.read(repoActionsProvider(dir.path));
  });

  tearDown(() async {
    c.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('break', () {
    test('pauses instead of reporting a finished rebase', () async {
      await actions.rebase(base, [
        RebaseStep(c1, RebaseAction.pick),
        const RebaseStep.breakpoint(id: 'b'),
        RebaseStep(c2, RebaseAction.pick),
      ]);

      expect(rebasing(), isTrue);
      expect(toastTitles(), isNot(contains('Rebase complete')));
      expect(toastTitles(), contains('Rebase paused at a break'));
      final pending = await actions.pendingOp();
      expect(pending?.kind, MergeKind.rebase);
      expect(pending?.stop, const RebaseStop.breakpoint());
      // Nothing finished yet, so nothing to undo yet.
      expect(c.read(undoProvider(dir.path)).canUndo, isFalse);
    });

    test('continuing finishes it, and the whole rebase is undoable', () async {
      final before = await out(['rev-parse', 'HEAD']);
      await actions.rebase(base, [
        RebaseStep(c2, RebaseAction.pick),
        const RebaseStep.breakpoint(id: 'b'),
        RebaseStep(c1, RebaseAction.pick),
      ]);
      await actions.continueOp();

      expect(rebasing(), isFalse);
      expect(await subjects(), ['C1', 'C2', 'base']);
      await actions.undo();
      expect(await out(['rev-parse', 'HEAD']), before);
    });

    test('continuing never skips: an unstaged edit survives', () async {
      await actions.rebase(base, [
        RebaseStep(c1, RebaseAction.pick),
        const RebaseStep.breakpoint(id: 'b'),
        RebaseStep(c2, RebaseAction.pick),
      ]);
      // Nothing staged, which for a conflicted pick would mean "skip it".
      await File('${dir.path}/f1.txt').writeAsString('edited\n');
      await actions.continueOp();

      expect(await File('${dir.path}/f1.txt').readAsString(), 'edited\n');
      expect(rebasing(), isTrue);
    });

    test('a second break met while continuing pauses again', () async {
      await actions.rebase(base, [
        const RebaseStep.breakpoint(id: 'b1'),
        RebaseStep(c1, RebaseAction.pick),
        const RebaseStep.breakpoint(id: 'b2'),
        RebaseStep(c2, RebaseAction.pick),
      ]);
      await actions.continueOp();

      expect(rebasing(), isTrue);
      expect(await out(['log', '-1', '--format=%s']), 'C1');
      expect(toastTitles(), isNot(contains('Rebase complete')));
    });
  });

  group('exec', () {
    test('a failing exec pauses with its command and output kept', () async {
      await actions.rebase(base, [
        RebaseStep(c1, RebaseAction.pick),
        const RebaseStep.exec('echo boom-output; exit 1', id: 'x'),
        RebaseStep(c2, RebaseAction.pick),
      ]);

      expect(rebasing(), isTrue);
      final pending = await actions.pendingOp();
      expect(pending?.stop, const RebaseStop.exec('echo boom-output; exit 1'));
      expect(
        c.read(rebaseExecOutputProvider(dir.path)),
        contains('boom-output'),
      );
      expect(toastTitles(), contains('Exec step failed'));
    });

    test('continuing after a failed exec runs the rest', () async {
      await actions.rebase(base, [
        RebaseStep(c1, RebaseAction.pick),
        const RebaseStep.exec('exit 1', id: 'x'),
        RebaseStep(c2, RebaseAction.pick),
      ]);
      await actions.continueOp();

      expect(rebasing(), isFalse);
      expect(await subjects(), ['C2', 'C1', 'base']);
      expect(c.read(rebaseExecOutputProvider(dir.path)), isNull);
    });

    test(
      'an exec failing during continue pauses again with its output',
      () async {
        await actions.rebase(base, [
          const RebaseStep.breakpoint(id: 'b'),
          RebaseStep(c1, RebaseAction.pick),
          const RebaseStep.exec('echo second-fail; exit 2', id: 'x'),
          RebaseStep(c2, RebaseAction.pick),
        ]);
        await actions.continueOp();

        expect(rebasing(), isTrue);
        expect(
          (await actions.pendingOp())?.stop,
          const RebaseStop.exec('echo second-fail; exit 2'),
        );
        expect(
          c.read(rebaseExecOutputProvider(dir.path)),
          contains('second-fail'),
        );
      },
    );

    test(
      'a continue git refuses is an error, not a second exec failure',
      () async {
        await actions.rebase(base, [
          RebaseStep(c1, RebaseAction.pick),
          const RebaseStep.exec('exit 1', id: 'x'),
          RebaseStep(c2, RebaseAction.pick),
        ]);
        // git will not continue over unstaged edits.
        await File('${dir.path}/f1.txt').writeAsString('edited\n');
        await actions.continueOp();

        expect(rebasing(), isTrue);
        expect(
          toastTitles().where((t) => t == 'Exec step failed'),
          hasLength(1),
        );
        expect(await File('${dir.path}/f1.txt').readAsString(), 'edited\n');
      },
    );

    test('aborting clears the kept output', () async {
      await actions.rebase(base, [
        RebaseStep(c1, RebaseAction.pick),
        const RebaseStep.exec('exit 1', id: 'x'),
      ]);
      await actions.abortMerge();
      expect(c.read(rebaseExecOutputProvider(dir.path)), isNull);
    });
  });

  group('stacked branches', () {
    test('lists local branches pointing into the range', () async {
      await g(['branch', 'part1', c1]);
      await g(['branch', 'also-tip', c2]);
      await g(['branch', 'at-base', base]);
      expect(await actions.rebaseStackedBranches(base), {
        c1: ['part1'],
        c2: ['also-tip'],
      });
    });

    test('leaves out a branch checked out in another worktree', () async {
      await g(['branch', 'part1', c1]);
      await g(['branch', 'busy', c1]);
      final wt = '${dir.path}-wt';
      await g(['worktree', 'add', '-q', wt, 'busy']);
      addTearDown(() async {
        if (await Directory(wt).exists()) {
          await Directory(wt).delete(recursive: true);
        }
      });
      expect(await actions.rebaseStackedBranches(base), {
        c1: ['part1'],
      });
    });

    test('updateRefs moves a stacked branch with its commit', () async {
      await g(['branch', 'part1', c1]);
      await actions.rebase(base, [
        RebaseStep(c2, RebaseAction.pick),
        RebaseStep(c1, RebaseAction.pick),
      ], updateRefs: true);

      expect(await subjects(), ['C1', 'C2', 'base']);
      expect(
        await out(['rev-parse', 'part1']),
        await out(['rev-parse', 'HEAD']),
      );
    });

    test('without updateRefs a stacked branch stays behind', () async {
      await g(['branch', 'part1', c1]);
      await actions.rebase(base, [
        RebaseStep(c2, RebaseAction.pick),
        RebaseStep(c1, RebaseAction.pick),
      ]);
      expect(await out(['rev-parse', 'part1']), c1);
    });
  });

  test('prepareFixup pre-fills the composer and commits nothing', () async {
    final head = await out(['rev-parse', 'HEAD']);
    actions.prepareFixup('C1');
    expect(c.read(composerPrefillProvider(dir.path)), 'fixup! C1');
    expect(await out(['rev-parse', 'HEAD']), head);
  });
}
