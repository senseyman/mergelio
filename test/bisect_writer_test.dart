import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

class _RecordingGit implements GitService {
  final calls = <List<String>>[];
  GitResult result = const GitResult(0, '', '');
  GitCancel? lastCancel;

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
    lastCancel = cancel;
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

  test('bisectLog returns the verdict trail git printed', () async {
    git.result = const GitResult(
      0,
      'git bisect start\ngit bisect bad aaa\n',
      '',
    );

    final log = await writer.bisectLog();

    expect(git.calls.single, ['bisect', 'log']);
    expect(log, contains('git bisect bad aaa'));
  });

  test('a failing bisect log throws with its stderr attached', () async {
    git.result = const GitResult(1, '', 'fatal: not a valid object name');
    // Handlers here read result.err ahead of the exception's own message, so
    // a throw without its GitResult reaches the user as empty text.
    await expectLater(
      writer.bisectLog(),
      throwsA(
        isA<GitException>().having(
          (e) => e.result?.err,
          'stderr',
          contains('fatal: not a valid object name'),
        ),
      ),
    );
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

  test('the command is handed to a shell, never split on spaces', () {
    final args = bisectRunArgs('npm test -- --grep "two words"');
    expect(args[0], 'bisect');
    expect(args[1], 'run');
    // The whole command survives as ONE argument: splitting it would break
    // quoting, pipes and shell builtins.
    expect(args.last, 'npm test -- --grep "two words"');
    expect(args.length, 5);
  });

  test('a command containing a pipe is not mangled', () {
    final args = bisectRunArgs('make 2>&1 | grep -q FAIL');
    expect(args.last, 'make 2>&1 | grep -q FAIL');
  });

  test(
    'bisectRun returns the result rather than throwing on failure',
    () async {
      // The exit code IS the outcome here, so throwing would discard it.
      git.result = const GitResult(1, '', "error: bogus exit code 127");
      final r = await writer.bisectRun('false');
      expect(r.exitCode, 1);
      expect(r.err, contains('bogus exit code'));
    },
  );

  test('bisectRun passes the cancel handle through', () async {
    final cancel = GitCancel();
    await writer.bisectRun('true', cancel: cancel);
    expect(git.lastCancel, same(cancel));
  });
}
