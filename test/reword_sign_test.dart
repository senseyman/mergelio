import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Answers just enough for [RepoActions.rewordCommit] to reach the amend, with
/// a settable `%G?` so the signature of the original commit can be varied.
class _FakeGit implements GitService {
  _FakeGit(this.signature);
  final String signature;
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
    if (args.first == 'rev-parse') return const GitResult(0, 'c0ffee\n', '');
    if (args.contains('--format=%G?')) return GitResult(0, '$signature\n', '');
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  Future<List<String>> commitArgs(String signature) async {
    final git = _FakeGit(signature);
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(container.dispose);

    await container
        .read(repoActionsProvider('/r'))
        .rewordCommit('c0ffee', 'reworded');

    return git.calls.firstWhere(
      (c) => c.contains('commit'),
      orElse: () => const [],
    );
  }

  test('rewording a signed commit re-signs it', () async {
    expect(await commitArgs('G'), contains('-S'));
  });

  test('a signature that cannot be verified is still re-signed', () async {
    // 'E' means the key is missing locally, not that the commit is unsigned —
    // dropping the signature would quietly downgrade the commit.
    expect(await commitArgs('E'), contains('-S'));
  });

  test('rewording an unsigned commit does not ask for a signature', () async {
    // -S without a configured key fails outright, so it must not be guessed.
    expect(await commitArgs('N'), isNot(contains('-S')));
  });
}
