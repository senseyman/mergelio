import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';

/// The 30s default guards against a network operation that stalls. Walking the
/// history of a large monorepo is neither network-bound nor stalled — it is
/// simply long — so the bulk read gets its own, generous budget rather than
/// being killed and reported to the user as a failed repository.
void main() {
  test('gives the history walk a longer budget than the default', () async {
    final git = _RecordingGit();

    await GitReader(git, '/repo').commits(maxCount: 50000);

    final log = git.calls.firstWhere((c) => c.args.first == 'log');
    expect(log.timeout, isNotNull);
    expect(log.timeout!, greaterThan(const Duration(seconds: 30)));
  });

  test('leaves the cheap lookups on the default timeout', () async {
    final git = _RecordingGit();

    await GitReader(git, '/repo').commits();

    final stash = git.calls.firstWhere((c) => c.args.first == 'stash');
    expect(stash.timeout, isNull);
  });
}

class _Call {
  final List<String> args;
  final Duration? timeout;
  _Call(this.args, this.timeout);
}

class _RecordingGit implements GitService {
  final List<_Call> calls = [];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(_Call(args, timeout));
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}
