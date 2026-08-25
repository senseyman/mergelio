import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Answers enough for the rebase pre-flight, with a settable commit log (shas,
/// summaries and `%G?` statuses), settable signature statuses on their own and
/// a settable signing configuration.
class _FakeGit implements GitService {
  _FakeGit({
    this.log = '',
    this.statuses = '',
    this.signingKey = '',
    this.gpgsign = '',
  });
  final String log;
  final String statuses;
  final String signingKey;

  /// As written in the config file — git only normalises it when asked to.
  final String gpgsign;
  final List<List<String>> calls = [];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    if (args.first == 'log') {
      return GitResult(
        0,
        '${args.contains('--format=%G?') ? statuses : log}\n',
        '',
      );
    }
    // Every switch lands on the branch it asked for.
    if (args.contains('--abbrev-ref')) return const GitResult(0, 'side\n', '');
    if (args.first == 'config') {
      if (args.contains('user.signingkey')) return GitResult(0, signingKey, '');
      final on = const ['true', '1', 'yes', 'on'].contains(gpgsign);
      return GitResult(0, args.contains('--bool') ? '$on' : gpgsign, '');
    }
    if (args.first == 'rev-parse') return const GitResult(0, 'c0ffee\n', '');
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  RepoActions actions(_FakeGit git) {
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(container.dispose);
    return container.read(repoActionsProvider('/r'));
  }

  group('rebaseStepsFrom', () {
    test('carries each commit signature status into its step', () async {
      final git = _FakeGit(
        log: 'aaa\x1fsigned\x1fG\nbbb\x1fplain\x1fN\nccc\x1fkeyless\x1fE',
      );

      final steps = await actions(git).rebaseStepsFrom('base');

      // 'N' is the only status meaning "no signature at all"; 'E' (key missing
      // locally) still describes a commit that was signed.
      expect(steps.map((s) => s.sign), [true, false, true]);
      expect(steps.map((s) => s.message), ['signed', 'plain', 'keyless']);
    });

    test(
      'a summary holding the field separator does not shift the status',
      () async {
        final git = _FakeGit(log: 'aaa\x1fsub\x1fject\x1fN');

        final steps = await actions(git).rebaseStepsFrom('base');

        expect(steps.single.sign, isFalse);
        expect(steps.single.message, 'sub\x1fject');
      },
    );
  });

  group('rebase', () {
    Future<List<String>> rebaseArgs(_FakeGit git, List<bool> signs) async {
      await actions(git).rebase('base', [
        for (var i = 0; i < signs.length; i++)
          RebaseStep('sha$i', RebaseAction.pick, sign: signs[i]),
      ]);
      return git.calls.firstWhere(
        (c) => c.contains('rebase'),
        orElse: () => const [],
      );
    }

    test('re-signs the replayed commits when the branch was signed', () async {
      final args = await rebaseArgs(_FakeGit(signingKey: 'ABC123'), [
        false,
        true,
      ]);

      expect(args, contains('-S'));
    });

    test('leaves an unsigned branch unsigned', () async {
      final args = await rebaseArgs(_FakeGit(signingKey: 'ABC123'), [
        false,
        false,
      ]);

      expect(args, isNot(contains('-S')));
    });

    test('does not ask for a signature it cannot produce', () async {
      // -S without a configured key fails outright, and a rebase that dies on
      // its first commit strands the repository mid-rebase.
      final args = await rebaseArgs(_FakeGit(), [true, true]);

      expect(args, isNot(contains('-S')));
    });

    test('signs for a repository that signs every commit', () async {
      // git spells its booleans several ways, so it has to normalise this one.
      final args = await rebaseArgs(_FakeGit(gpgsign: '1'), [false, true]);

      expect(args, contains('-S'));
    });

    test('a dropped commit is not a reason to sign', () async {
      final git = _FakeGit(signingKey: 'ABC123');
      await actions(git).rebase('base', const [
        RebaseStep('sha0', RebaseAction.pick),
        RebaseStep('sha1', RebaseAction.drop, sign: true),
      ]);

      // Nothing signed survives the plan, so nothing needs re-signing.
      expect(
        git.calls.firstWhere((c) => c.contains('rebase')),
        isNot(contains('-S')),
      );
    });
  });

  group('rebaseOnto', () {
    Future<List<String>> rebaseArgs(_FakeGit git) async {
      await actions(git).rebaseOnto('side', 'main');
      return git.calls.firstWhere(
        (c) => c.contains('rebase'),
        orElse: () => const [],
      );
    }

    test('re-signs the replayed commits when the branch was signed', () async {
      final args = await rebaseArgs(
        _FakeGit(statuses: 'N\nG', signingKey: 'ABC123'),
      );

      expect(args, contains('-S'));
    });

    test('leaves an unsigned branch unsigned', () async {
      final args = await rebaseArgs(
        _FakeGit(statuses: 'N\nN', signingKey: 'ABC123'),
      );

      expect(args, isNot(contains('-S')));
    });

    test('does not ask for a signature it cannot produce', () async {
      final args = await rebaseArgs(_FakeGit(statuses: 'G\nG'));

      expect(args, isNot(contains('-S')));
    });
  });
}
