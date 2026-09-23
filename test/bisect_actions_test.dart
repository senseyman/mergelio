import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/bisect.dart';
import 'package:mergelio/state/feedback.dart';
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
      addTearDown(container.dispose);
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
}
