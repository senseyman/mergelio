import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';

class _CapturingGit implements GitService {
  final calls = <({List<String> args, Map<String, String>? environment})>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add((args: args, environment: environment));
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

/// GitReader commands are pure reads, yet plain `git status` opportunistically
/// rewrites `.git/index` (stat-cache refresh under an optional lock). That
/// write is what the disk watcher then sees, causing a refresh loop.
/// `GIT_OPTIONAL_LOCKS=0` tells git to skip those writes.
void main() {
  test('status runs with GIT_OPTIONAL_LOCKS=0', () async {
    final git = _CapturingGit();
    await GitReader(git, '/repo').status();

    expect(git.calls, isNotEmpty);
    expect(git.calls.single.args.first, 'status');
    expect(git.calls.single.environment?['GIT_OPTIONAL_LOCKS'], '0');
  });

  test('every read command carries GIT_OPTIONAL_LOCKS=0', () async {
    final git = _CapturingGit();
    final reader = GitReader(git, '/repo');
    await reader.branches();
    await reader.remotes();
    await reader.tags();
    await reader.stashes();

    expect(git.calls, isNotEmpty);
    for (final call in git.calls) {
      expect(
        call.environment?['GIT_OPTIONAL_LOCKS'],
        '0',
        reason: 'git ${call.args.join(' ')} must not take optional locks',
      );
    }
  });
}
