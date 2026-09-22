import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

class _RecordingGit implements GitService {
  final calls = <List<String>>[];
  GitResult result = const GitResult(0, '', '');

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
    return result;
  }

  // GitService declares exactly three members; all must be implemented, so
  // there is no noSuchMethod fallback to lean on.
  @override
  Future<String> version() async => 'git version 2.55.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _RecordingGit git;
  late GitWriter writer;

  setUp(() {
    git = _RecordingGit();
    writer = GitWriter(git, '/repo');
  });

  test('bisectStart runs git bisect start', () async {
    await writer.bisectStart();
    expect(git.calls.single, ['bisect', 'start']);
  });

  test('bisectMark spells the repository own term', () async {
    await writer.bisectMark('broken', 'aaa1111');
    expect(git.calls.single, ['bisect', 'broken', 'aaa1111']);
  });

  test('bisectSkip names the rev when given one', () async {
    await writer.bisectSkip(rev: 'bbb2222');
    expect(git.calls.single, ['bisect', 'skip', 'bbb2222']);
  });

  test('bisectSkip without a rev skips the checked-out commit', () async {
    await writer.bisectSkip();
    expect(git.calls.single, ['bisect', 'skip']);
  });

  test('bisectReset runs git bisect reset', () async {
    await writer.bisectReset();
    expect(git.calls.single, ['bisect', 'reset']);
  });

  test('bisectLog returns stdout', () async {
    git.result = const GitResult(
      0,
      'git bisect start\ngit bisect bad aaa\n',
      '',
    );
    final log = await writer.bisectLog();
    expect(log, contains('git bisect bad aaa'));
  });

  test('a failing bisect command throws with its stderr attached', () async {
    git.result = const GitResult(1, '', 'not a valid object name');
    // The handler reads result.err, so the message alone is not enough.
    await expectLater(
      writer.bisectMark('bad', 'nope'),
      throwsA(
        isA<GitException>().having(
          (e) => e.result?.err,
          'stderr',
          contains('not a valid object name'),
        ),
      ),
    );
  });
}
