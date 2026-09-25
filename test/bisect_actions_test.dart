import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Answers every git invocation with a scripted result keyed on the exact
/// argument list, falling back to a bare success. Lets a test stand up
/// exactly the bisect state it wants without a real repository.
class _ScriptedGit implements GitService {
  final calls = <List<String>>[];
  final Map<String, GitResult> responses = {};

  /// Argument lists that cannot run at all, the way every command fails while
  /// there is no usable git binary to run it.
  final unrunnable = <String>{};

  /// Result for a `bisect run` invocation, scripted separately from
  /// [responses]: `bisectRunArgs` appends the caller's shell and its flag, so
  /// the full argument list varies by platform and by `$SHELL` and cannot be
  /// keyed exactly the way every other command is.
  GitResult? bisectRunResult;

  /// When true, the `bisect run` invocation throws [GitCancelledException]
  /// instead of returning [bisectRunResult] — the way a real cancel reaches
  /// the caller, from inside the process run rather than from its result.
  bool bisectRunCancelled = false;

  /// When set, the `bisect run` invocation waits on this before returning or
  /// throwing, so a test can assert on state while the run is still in
  /// flight and then let it finish on its own schedule.
  Completer<void>? bisectRunGate;

  /// Runs when the `bisect run` invocation arrives, before its result is
  /// handed back. Lets a test dirty the tree the way the user's own command
  /// does — during the run — rather than before it, which is a refusal.
  void Function()? onBisectRun;

  bool _isBisectRun(List<String> args) =>
      args.length >= 2 && args[0] == 'bisect' && args[1] == 'run';

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    if (unrunnable.contains(args.join(' '))) {
      throw GitUnavailableException('git could not be found');
    }
    if (_isBisectRun(args)) {
      onBisectRun?.call();
      final gate = bisectRunGate;
      if (gate != null) await gate.future;
      if (bisectRunCancelled) {
        throw GitCancelledException('git ${args.join(' ')} cancelled');
      }
      return bisectRunResult ?? const GitResult(0, '', '');
    }
    return responses[args.join(' ')] ?? const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// Wraps a real [GitWriter] but records which method each bisect verdict
/// actually reached. Raw CLI args cannot show this: `bisectSkip(rev: sha)`
/// and `bisectMark('skip', sha)` both end up as `['bisect', 'skip', sha]`,
/// so a mutation that routes skip through the term path would still pass an
/// assertion made only against git.calls.
class _RecordingWriter extends GitWriter {
  final calls = <String>[];
  _RecordingWriter(super.git, super.repoPath);

  @override
  Future<void> bisectMark(String term, String rev) {
    calls.add('mark:$term:$rev');
    return super.bisectMark(term, rev);
  }

  @override
  Future<void> bisectSkip({String? rev}) {
    calls.add('skip:${rev ?? ''}');
    return super.bisectSkip(rev: rev);
  }

  @override
  Future<void> bisectStart() {
    calls.add('start');
    return super.bisectStart();
  }

  @override
  Future<void> bisectReset() {
    calls.add('reset');
    return super.bisectReset();
  }
}

/// A [Ref] backed by a real container, so [RepoActions] can be built
/// directly with a [_RecordingWriter] instead of the plain [GitWriter] that
/// `repoActionsProvider` wires up.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('bisectCommandFor', () {
    test('good and bad go through the term, skip goes through skip', () {
      // Guards the one asymmetry in git's CLI: good and bad are terms that
      // follow `git bisect`, but skip is a subcommand of its own. Routing
      // skip as a term produces a command git rejects.
      expect(bisectCommandFor(BisectKind.good, const BisectTerms()), 'good');
      expect(bisectCommandFor(BisectKind.bad, const BisectTerms()), 'bad');
      expect(bisectCommandFor(BisectKind.skip, const BisectTerms()), 'skip');
    });

    test('a repository own terms replace good and bad but never skip', () {
      const t = BisectTerms(good: 'working', bad: 'broken');
      expect(bisectCommandFor(BisectKind.good, t), 'working');
      expect(bisectCommandFor(BisectKind.bad, t), 'broken');
      expect(bisectCommandFor(BisectKind.skip, t), 'skip');
    });
  });

  group('markBisect routing (bisect already running)', () {
    late Directory gitDir;
    late _ScriptedGit git;
    late ProviderContainer container;
    late _RecordingWriter writer;
    late RepoActions actions;

    setUp(() {
      gitDir = Directory.systemTemp.createTempSync('bisect_state_');
      git = _ScriptedGit();
      git.responses['rev-parse --git-path BISECT_START'] = GitResult(
        0,
        '${gitDir.path}/BISECT_START',
        '',
      );
      git.responses['rev-parse --git-path BISECT_TERMS'] = GitResult(
        0,
        '${gitDir.path}/BISECT_TERMS',
        '',
      );
      File('${gitDir.path}/BISECT_START').writeAsStringSync('main\n');

      container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      writer = _RecordingWriter(git, '/r');
      actions = RepoActions(container.read(_refProvider), '/r', writer);
      addTearDown(() {
        // Built directly rather than through repoActionsProvider, so the
        // provider's onDispose never runs: without this the refresh
        // coalescer's timer outlives the container and fires against it.
        actions.dispose();
        container.dispose();
        gitDir.deleteSync(recursive: true);
      });
    });

    test('good and bad with default terms reach bisectMark spelled '
        'literally', () async {
      await actions.markBisect('sha4', BisectKind.good);
      await actions.markBisect('sha5', BisectKind.bad);

      expect(writer.calls, ['mark:good:sha4', 'mark:bad:sha5']);
    });

    test('good and bad reach bisectMark spelled in the repository own '
        'terms, never the literal word', () async {
      File('${gitDir.path}/BISECT_TERMS')
          .writeAsStringSync('broken\nworking\n');

      await actions.markBisect('sha1', BisectKind.good);
      await actions.markBisect('sha2', BisectKind.bad);

      expect(writer.calls, ['mark:working:sha1', 'mark:broken:sha2']);
    });

    test(
      'skip reaches bisectSkip, never bisectMark, even with renamed terms',
      () async {
        File('${gitDir.path}/BISECT_TERMS')
            .writeAsStringSync('broken\nworking\n');

        await actions.markBisect('sha3', BisectKind.skip);

        // A mutation that instead calls
        // `_writer.bisectMark(bisectCommandFor(kind, state.terms), sha)`
        // unconditionally happens to send the identical CLI args here (both
        // resolve to ['bisect', 'skip', 'sha3']), so the only thing that can
        // catch it is which GitWriter method actually ran.
        expect(writer.calls, ['skip:sha3']);
        expect(writer.calls.any((c) => c.startsWith('mark:')), isFalse);
      },
    );

    test('skipBisect skips the commit currently checked out', () async {
      git.responses['rev-parse HEAD'] = const GitResult(0, 'deadbeef', '');

      await actions.skipBisect();

      expect(writer.calls, ['skip:deadbeef']);
    });

    // These run from buttons nobody awaits, so an error thrown out of the
    // pre-flight read has nowhere to land: the user presses the button and
    // absolutely nothing happens, not even a complaint.
    test('markBisect reports a state read that could not run', () async {
      git.unrunnable.add('rev-parse --git-path BISECT_START');

      await actions.markBisect('sha1', BisectKind.bad);

      // And emphatically does not read the failure as "no bisect running"
      // and open a fresh one over the hunt already in progress.
      expect(writer.calls, isEmpty);
      expect(
        container.read(toastProvider).any((t) => t.kind == ToastKind.error),
        isTrue,
      );
    });

    test('skipBisect reports a state read that could not run', () async {
      git.unrunnable.add('rev-parse --git-path BISECT_START');

      await actions.skipBisect();

      expect(writer.calls, isEmpty);
      expect(
        container.read(toastProvider).any((t) => t.kind == ToastKind.error),
        isTrue,
      );
    });

    // Not every way a state read fails is a git failure. The read tests a
    // state file with existsSync() and then reads it, and the read throws a
    // FileSystemException of its own — a file that vanished in between, a
    // corrupt one that will not decode, an I/O fault on the disk. Caught
    // only as a GitException, that escapes a button callback nobody awaits
    // and the press does nothing at all, not even complain.
    void corruptTermsFile() =>
        File('${gitDir.path}/BISECT_TERMS')
            .writeAsBytesSync([0xC3, 0x28, 0xFF]);

    test('markBisect reports a state read that faulted outside git', () async {
      corruptTermsFile();

      await actions.markBisect('sha1', BisectKind.bad);

      expect(writer.calls, isEmpty);
      expect(
        container.read(toastProvider).any((t) => t.kind == ToastKind.error),
        isTrue,
      );
    });

    test('skipBisect reports a state read that faulted outside git', () async {
      corruptTermsFile();

      await actions.skipBisect();

      expect(writer.calls, isEmpty);
      expect(
        container.read(toastProvider).any((t) => t.kind == ToastKind.error),
        isTrue,
      );
    });
  });

  group('startBisect / markBisect with no bisect running', () {
    late _ScriptedGit git;
    late ProviderContainer container;
    late _RecordingWriter writer;
    late RepoActions actions;

    setUp(() {
      git = _ScriptedGit();
      container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      writer = _RecordingWriter(git, '/r');
      actions = RepoActions(container.read(_refProvider), '/r', writer);
      addTearDown(() {
        // Cancels the refresh coalescer's pending timer. These actions are
        // built directly rather than through repoActionsProvider, so the
        // provider's onDispose never runs and the timer would otherwise fire
        // against an already-disposed container.
        actions.dispose();
        container.dispose();
      });
    });

    test('startBisect refuses a dirty tree and touches nothing', () async {
      git.responses['status --porcelain'] = const GitResult(
        0,
        ' M file.txt\n',
        '',
      );

      await actions.startBisect('sha6');

      expect(writer.calls, isEmpty);
      expect(
        container.read(toastProvider).any((t) => t.kind == ToastKind.error),
        isTrue,
      );
    });

    test('startBisect reports a dirty-tree check that could not run', () async {
      git.unrunnable.add('status --porcelain');

      await actions.startBisect('sha6');

      expect(writer.calls, isEmpty);
      expect(
        container.read(toastProvider).any((t) => t.kind == ToastKind.error),
        isTrue,
      );
    });

    test(
      'startBisect on a clean tree opens the session and marks the sha bad',
      () async {
        await actions.startBisect('sha7');

        expect(writer.calls, ['start', 'mark:bad:sha7']);
      },
    );

    test('markBisect with kind bad and no bisect running starts one', () async {
      await actions.markBisect('sha8', BisectKind.bad);

      expect(writer.calls, ['start', 'mark:bad:sha8']);
    });

    test('markBisect with kind good/skip and no bisect running refuses and '
        'toasts instead of guessing a start', () async {
      await actions.markBisect('sha9', BisectKind.good);

      expect(writer.calls, isEmpty);
      expect(
        container.read(toastProvider).any((t) => t.kind == ToastKind.error),
        isTrue,
      );
    });

    test('skipBisect is a no-op when no bisect is running', () async {
      await actions.skipBisect();

      expect(writer.calls, isEmpty);
    });

    test('resetBisect ends the session', () async {
      await actions.resetBisect();

      expect(writer.calls, ['reset']);
    });
  });

  group('bisectLog', () {
    late _ScriptedGit git;
    late ProviderContainer container;
    late RepoActions actions;

    setUp(() {
      git = _ScriptedGit();
      container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      actions = RepoActions(
        container.read(_refProvider),
        '/r',
        GitWriter(git, '/r'),
      );
      addTearDown(() {
        // Cancels the refresh coalescer's pending timer. These actions are
        // built directly rather than through repoActionsProvider, so the
        // provider's onDispose never runs and the timer would otherwise fire
        // against an already-disposed container.
        actions.dispose();
        container.dispose();
      });
    });

    List<Toast> errors() => container
        .read(toastProvider)
        .where((t) => t.kind == ToastKind.error)
        .toList();

    test('hands back the trail git printed', () async {
      git.responses['bisect log'] = const GitResult(
        0,
        'git bisect start\ngit bisect bad aaa1111\ngit bisect good ccc3333\n',
        '',
      );

      final log = await actions.bisectLog();

      expect(log, contains('git bisect good ccc3333'));
      expect(errors(), isEmpty);
    });

    test('reports a failed read and hands back nothing', () async {
      git.responses['bisect log'] = const GitResult(
        1,
        '',
        'fatal: not a valid object name',
      );

      final log = await actions.bisectLog();

      // Null rather than an empty string: the caller has to tell "git said
      // nothing" apart from "git could not be asked", or a failed fetch
      // renders as a blank panel.
      expect(log, isNull);
      // Git's own words, not the wrapper this code put around them — which
      // only arrives when the exception carried its GitResult.
      expect(
        errors().single.description,
        contains('fatal: not a valid object name'),
      );
    });

    test('reports a log that could not run at all', () async {
      // A broken toolchain throws a type of its own carrying no result, and
      // a handler that catches only the narrow one lets this escape a
      // callback nobody awaits, where it is never reported at all.
      git.unrunnable.add('bisect log');

      final log = await actions.bisectLog();

      expect(log, isNull);
      expect(errors(), hasLength(1));
    });
  });

  group('bisectStateProvider', () {
    test('surfaces null when no bisect is in progress', () async {
      final git = _ScriptedGit();
      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(container.dispose);

      final state = await container.read(bisectStateProvider('/r').future);

      expect(state, isNull);
    });
  });

  group('runBisect', () {
    late _ScriptedGit git;
    late ProviderContainer container;
    late RepoActions actions;

    setUp(() {
      git = _ScriptedGit();
      container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      actions = RepoActions(
        container.read(_refProvider),
        '/r',
        GitWriter(git, '/r'),
      );
      addTearDown(() {
        // Cancels the refresh coalescer's pending timer. These actions are
        // built directly rather than through repoActionsProvider, so the
        // provider's onDispose never runs and the timer would otherwise fire
        // against an already-disposed container.
        actions.dispose();
        container.dispose();
      });
    });

    /// Error toasts raised so far, newest last.
    Iterable<Toast> errors() =>
        container.read(toastProvider).where((t) => t.kind == ToastKind.error);

    /// The status the journal ended up recording for the run, or null when it
    /// recorded no run at all.
    OpStatus? runStatus() => container
        .read(operationJournalProvider('/r'))
        .records
        .where((r) => r.label == 'Bisect: run')
        .lastOrNull
        ?.status;

    /// What git says when the command exits with a code it refuses to read as
    /// a verdict — measured: `sh -c 'exit 200'` makes git exit 56 saying this.
    /// The classifier recognises none of it, which is the whole point: it is
    /// the case where nothing else in the app has anything to say.
    const unrecognised = GitResult(
      56,
      '',
      "error: bisect run failed: exit code 200 from '/bin/sh' '-c' 'exit 200' "
          'is < 0 or >= 128',
    );

    test('a clean run reports a finished hunt', () async {
      // Default scripted response for `bisect run` is exit code 0.
      final outcome = await actions.runBisect('./t.sh');
      expect(outcome, BisectRunOutcome.finished);
      expect(errors(), isEmpty);
      expect(runStatus(), OpStatus.done);
    });

    test('an unrecognised failure reaches the user in git own words', () async {
      git.bisectRunResult = unrecognised;

      final outcome = await actions.runBisect('exit 200');

      expect(outcome, BisectRunOutcome.failed);
      // Without this the command exits 200, git exits 56, and the user is
      // shown nothing whatsoever: no toast, and a bar that stays silent on
      // `failed` because it believes this layer already spoke.
      expect(errors(), hasLength(1));
      // Git's own stderr, not a wrapper of our own around it — the same
      // preference every other failing op here honours.
      expect(errors().single.description, contains('exit code 200'));
    });

    test('a failed run is journaled as failed, not as done', () async {
      git.bisectRunResult = unrecognised;

      await actions.runBisect('exit 200');

      // Recording it as done makes the journal claim a hunt completed that
      // in fact stopped wherever git happened to be standing.
      expect(runStatus(), OpStatus.failed);
    });

    /// Makes the tracked-file check answer dirty from the moment the run
    /// starts, which is when the user's own command does the dirtying.
    void dirtyTheTreeDuringTheRun() => git.onBisectRun = () {
      git.responses['status --porcelain --untracked-files=no'] =
          const GitResult(0, ' M file.txt\n', '');
    };

    test('a run that dirtied the tree is journaled as failed', () async {
      git.bisectRunResult = const GitResult(1, '', 'some failure');
      dirtyTheTreeDuringTheRun();

      final outcome = await actions.runBisect('./t.sh');

      expect(outcome, BisectRunOutcome.treeDirtied);
      expect(runStatus(), OpStatus.failed);
      // No toast: the bar names this outcome in its own words, and the same
      // complaint in two places at once is worse than one.
      expect(errors(), isEmpty);
    });

    test('a command git could not run at all is journaled as failed', () async {
      git.bisectRunResult = const GitResult(
        1,
        '',
        'error: bogus exit code 127 (only 0-127 are valid)',
      );

      final outcome = await actions.runBisect('./missing.sh');

      expect(outcome, BisectRunOutcome.commandUnrunnable);
      expect(runStatus(), OpStatus.failed);
      expect(errors(), isEmpty);
    });

    test('exhaustion is an ending, not a failure', () async {
      git.bisectRunResult = const GitResult(
        2,
        '',
        'error: bisect run cannot continue any more',
      );

      final outcome = await actions.runBisect('./t.sh');

      // Git narrowed as far as the marks allow and said so. Nothing went
      // wrong, so nothing is reported as having gone wrong.
      expect(outcome, BisectRunOutcome.exhausted);
      expect(runStatus(), OpStatus.done);
      expect(errors(), isEmpty);
    });

    test('a run that dirties the tree is named for the real cause', () async {
      git.bisectRunResult = const GitResult(1, '', 'some failure');
      // The run asks about tracked files only: a command's own scratch files
      // do not stop git checking the next commit out, so they are no
      // explanation for a failure.
      dirtyTheTreeDuringTheRun();

      final outcome = await actions.runBisect('./t.sh');

      expect(outcome, BisectRunOutcome.treeDirtied);
    });

    test('untracked files a run left behind are not a dirtied tree', () async {
      git.bisectRunResult = const GitResult(
        2,
        '',
        'error: bisect run cannot continue any more',
      );
      // What `status --porcelain` would have reported, and what the run asks
      // for instead. Reported as a dirtied tree, the exhaustion the user can
      // act on would be replaced by a claim about tracked files they never
      // touched.
      git.responses['status --porcelain'] = const GitResult(
        0,
        '?? scratch.log\n',
        '',
      );
      git.responses['status --porcelain --untracked-files=no'] =
          const GitResult(0, '', '');

      final outcome = await actions.runBisect('./t.sh');

      expect(outcome, BisectRunOutcome.exhausted);
    });

    test(
      'the running command is published while it runs and cleared after',
      () async {
        final gate = Completer<void>();
        git.bisectRunGate = gate;

        expect(container.read(bisectRunProvider('/r')), isNull);
        final future = actions.runBisect('./slow.sh');
        // Lets the journal write (itself async, but no real timer) run to
        // completion, landing squarely inside the gated git call — still
        // "while it runs" rather than testing only the synchronous prologue.
        await Future<void>.delayed(Duration.zero);
        expect(container.read(bisectRunProvider('/r')), './slow.sh');

        gate.complete();
        await future;

        expect(container.read(bisectRunProvider('/r')), isNull);
      },
    );

    test('a run belongs to its own repository only', () async {
      final gate = Completer<void>();
      git.bisectRunGate = gate;

      final future = actions.runBisect('./slow.sh');
      await Future<void>.delayed(Duration.zero);

      // Bisect state is per repository, so this has to be too. Shared, a run
      // in one tab renders as "Running …" in another repository's bar and
      // takes that repository's verdict buttons away with it.
      expect(container.read(bisectRunProvider('/r')), './slow.sh');
      expect(container.read(bisectRunProvider('/other')), isNull);

      gate.complete();
      await future;
    });

    test('cancelling a run reports cancelled and keeps the bisect', () async {
      git.bisectRunCancelled = true;

      final outcome = await actions.runBisect('./t.sh');

      expect(outcome, BisectRunOutcome.cancelled);
      // The marks already recorded survive: abandoning automation is not
      // abandoning the hunt.
      expect(container.read(bisectRunProvider('/r')), isNull);
    });

    test('a run offers a cancel through the shared busy state', () async {
      final gate = Completer<void>();
      git.bisectRunGate = gate;

      final future = actions.runBisect('./slow.sh');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(busyProvider)?.onCancel, isNotNull);

      gate.complete();
      await future;

      expect(container.read(busyProvider), isNull);
    });

    test('a run refuses to start while another operation holds the lane', () {
      container.read(busyProvider.notifier).state = const BusyState('Merge');

      return expectLater(actions.runBisect('./t.sh'), completion(isNull)).then((
        _,
      ) {
        // Git was never asked: a run alongside a merge races on the same
        // index and ref locks.
        expect(
          git.calls.where((c) => c.length >= 2 && c[1] == 'run'),
          isEmpty,
          reason: 'bisect run must not be started while the lane is taken',
        );
        // The operation that does hold the lane still holds it. Overwriting
        // it is the actual damage: this run's `finally` would then clear the
        // merge's busy state while the merge is still going.
        expect(container.read(busyProvider)?.label, 'Merge');
        expect(
          container.read(toastProvider).last.kind,
          ToastKind.warning,
          reason: 'a refused run has to say why it did nothing',
        );
      });
    });

    test('a second run cannot start on top of the first', () async {
      final gate = Completer<void>();
      git.bisectRunGate = gate;

      final first = actions.runBisect('./slow.sh');
      await Future<void>.delayed(Duration.zero);

      // The first run holds the lane, so the second is turned away rather
      // than left to clear the first one's busy state out from under it.
      expect(await actions.runBisect('./other.sh'), isNull);
      expect(container.read(bisectRunProvider('/r')), './slow.sh');

      gate.complete();
      await first;
      expect(container.read(busyProvider), isNull);
    });

    /// Every `bisect run` invocation git was actually asked to make.
    Iterable<List<String>> runCalls() => git.calls.where(
      (c) => c.length >= 2 && c[0] == 'bisect' && c[1] == 'run',
    );

    group('a dirty tree is refused before the run, not explained after', () {
      test('modified tracked files stop the run reaching git', () async {
        git.responses['status --porcelain --untracked-files=no'] =
            const GitResult(0, ' M lib/main.dart\n', '');

        final outcome = await actions.runBisect('./t.sh');

        // Null, not an outcome: nothing ran, so there is nothing to report
        // beyond the refusal itself.
        expect(outcome, isNull);
        // The damage a run over a modified tree does is not a confusing
        // message, it is a false verdict: the command tests the user's
        // uncommitted edits, git records the answer against the commit it
        // checked out, and the hunt then convicts a commit on the strength of
        // code that commit does not contain.
        expect(
          runCalls(),
          isEmpty,
          reason:
              'a run over modified tracked files records a verdict about '
              'code the commit under test does not contain',
        );
        final last = container.read(toastProvider).last;
        expect(last.kind, ToastKind.error);
        expect(
          last.description,
          contains('Commit or stash'),
          reason: 'a refusal has to say what to do about it',
        );
        // The lane is left exactly as it was found: nothing started, so
        // nothing may be holding the status bar or the run indicator.
        expect(container.read(busyProvider), isNull);
        expect(container.read(bisectRunProvider('/r')), isNull);
      });

      test('an untracked scratch file does not stop a run', () async {
        // What `status --porcelain` would say; the guard must not be reading
        // that. A command's own scratch files never stop git checking the
        // next commit out, so blocking on them would refuse ordinary work.
        git.responses['status --porcelain'] = const GitResult(
          0,
          '?? scratch.log\n',
          '',
        );

        final outcome = await actions.runBisect('./t.sh');

        expect(outcome, BisectRunOutcome.finished);
        expect(runCalls(), hasLength(1));
      });

      test('a tracked-file check that cannot run refuses the run', () async {
        git.unrunnable.add('status --porcelain --untracked-files=no');

        final outcome = await actions.runBisect('./t.sh');

        // Unknown is not clean. Starting anyway would be the false-verdict
        // case again, on a tree nobody could vouch for.
        expect(outcome, isNull);
        expect(runCalls(), isEmpty);
        expect(errors(), hasLength(1));
        expect(container.read(busyProvider), isNull);
      });

      test(
        'the refusal is not written to the journal as a failed run',
        () async {
          git.responses['status --porcelain --untracked-files=no'] =
              const GitResult(0, ' M lib/main.dart\n', '');

          await actions.runBisect('./t.sh');

          // No run happened, so the journal must not carry one. A pending or
          // failed marker here reads on the next launch as a run that died.
          expect(runStatus(), isNull);
        },
      );
    });

    // A run is a second git process walking .git/BISECT_* on its own. Every
    // verdict button, the graph's own per-commit menu and the quit dialog's
    // Reset all reach the same state, and the bar disabling one of them is
    // not a boundary — the actions are.
    group('bisect changes are refused while a run is in flight', () {
      /// How many git calls had been made by the time the run was parked, so
      /// what a refused action adds on top can be counted exactly. The run's
      /// own calls — its tracked-file check and the `bisect run` it is sitting
      /// in — are all before this mark.
      late int callsBeforeTheAttempt;

      /// Leaves a run hanging inside git. The run is let go on tear-down, so
      /// a test only has to say what it tried to do meanwhile.
      Future<void> aRunInFlight() async {
        final gate = Completer<void>();
        git.bisectRunGate = gate;
        final future = actions.runBisect('./slow.sh');
        // Lets the synchronous prologue and the journal write finish, so the
        // run is genuinely parked inside the git call.
        await Future<void>.delayed(Duration.zero);
        expect(container.read(bisectRunProvider('/r')), './slow.sh');
        callsBeforeTheAttempt = git.calls.length;
        addTearDown(() async {
          if (!gate.isCompleted) gate.complete();
          await future;
        });
      }

      /// The warning a refusal owes the user, and nothing new asked of git.
      void expectRefused() {
        expect(
          git.calls.skip(callsBeforeTheAttempt),
          isEmpty,
          reason:
              'a second git process on the same .git/BISECT_* state races the '
              'run for the refs and for HEAD',
        );
        expect(container.read(toastProvider).last.kind, ToastKind.warning);
      }

      test('markBisect good is refused', () async {
        await aRunInFlight();
        await actions.markBisect('sha1', BisectKind.good);
        expectRefused();
      });

      test('markBisect bad is refused', () async {
        await aRunInFlight();
        await actions.markBisect('sha2', BisectKind.bad);
        expectRefused();
      });

      test('markBisect skip is refused', () async {
        await aRunInFlight();
        await actions.markBisect('sha3', BisectKind.skip);
        expectRefused();
      });

      test('skipBisect is refused', () async {
        await aRunInFlight();
        await actions.skipBisect();
        // Refused before the state read too: that read is a git call of its
        // own and there is nothing it could usefully tell anyone here.
        expectRefused();
      });

      test('startBisect is refused', () async {
        await aRunInFlight();
        await actions.startBisect('sha4');
        expectRefused();
      });

      test('resetBisect is refused', () async {
        await aRunInFlight();
        await actions.resetBisect();
        // The one the quit dialog offers. Throwing the refs away under a run
        // still adding to them is the worst of these, and leaving the hunt
        // standing is recoverable — it is still there on the next launch.
        expectRefused();
      });

      test('the same changes go through once the run has landed', () async {
        final gate = Completer<void>();
        git.bisectRunGate = gate;
        final future = actions.runBisect('./slow.sh');
        await Future<void>.delayed(Duration.zero);
        gate.complete();
        await future;

        // Guard against a refusal that never lifts: the provider is cleared
        // in the run's `finally`, and a guard reading anything else would
        // leave the hunt frozen for the rest of the session.
        await actions.resetBisect();
        expect(
          git.calls.where((c) => c.join(' ') == 'bisect reset'),
          isNotEmpty,
        );
      });
    });
  });
}
