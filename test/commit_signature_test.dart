import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';

class _CapturingGit implements GitService {
  final calls = <List<String>>[];
  final String output;
  _CapturingGit([this.output = '']);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    return GitResult(0, output, '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

/// `%G?` makes git verify each commit's signature, spawning gpg per signed
/// commit. On a repository that enforces signing this turns the bulk graph
/// read into thousands of gpg invocations (observed: ~4s for 4493 commits).
/// Bulk reads must therefore skip verification; only the single commit shown
/// in the details panel is verified, on demand.
void main() {
  test('bulk commits read does not verify signatures', () async {
    final git = _CapturingGit();
    await GitReader(git, '/repo').commits(maxCount: 100);

    expect(git.calls, isNotEmpty);
    for (final args in git.calls) {
      for (final a in args) {
        expect(
          a.contains('%G?'),
          isFalse,
          reason: 'git ${args.join(' ')} must not verify signatures',
        );
      }
    }
  });

  test('file history read does not verify signatures', () async {
    final git = _CapturingGit();
    await GitReader(git, '/repo').fileHistory('a.txt');

    expect(git.calls, isNotEmpty);
    for (final args in git.calls) {
      for (final a in args) {
        expect(
          a.contains('%G?'),
          isFalse,
          reason: 'git ${args.join(' ')} must not verify signatures',
        );
      }
    }
  });

  test('signatureStatus verifies exactly one commit on demand', () async {
    final git = _CapturingGit('G\n');
    final status = await GitReader(git, '/repo').signatureStatus('abc123');

    expect(status, 'G');
    expect(git.calls.single, ['log', '-1', '--format=%G?', 'abc123']);
  });

  test('signatureStatus maps empty output to N (unsigned)', () async {
    final git = _CapturingGit();
    expect(await GitReader(git, '/repo').signatureStatus('abc123'), 'N');
  });
}
