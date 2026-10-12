import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// Records how each command was asked to run, so the timeout a batch gets can
/// be checked without running one long enough to hit it.
class _RecordingGit implements GitService {
  final calls = <({List<String> args, Duration? timeout})>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add((args: args, timeout: timeout));
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _RecordingGit git;
  late GitWriter w;

  setUp(() {
    git = _RecordingGit();
    w = GitWriter(git, '/r');
  });

  test('passes the shas in the order given', () async {
    await w.cherryPickAll(['c', 'a', 'b']);
    expect(git.calls.single.args, ['cherry-pick', 'c', 'a', 'b']);
  });

  test('no-commit asks git not to commit', () async {
    await w.cherryPickAll(['a', 'b'], noCommit: true);
    expect(git.calls.single.args, ['cherry-pick', '--no-commit', 'a', 'b']);
  });

  test('a batch gets more than the default read timeout', () async {
    await w.cherryPickAll(['a', 'b']);
    await w.cherryPickAll(['a', 'b'], noCommit: true);
    for (final c in git.calls) {
      expect(c.timeout, GitWriter.pickSequenceTimeout);
    }
    expect(
      GitWriter.pickSequenceTimeout,
      greaterThan(const Duration(seconds: 30)),
    );
  });
}
