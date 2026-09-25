import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

class _RecordingGit implements GitService {
  final calls = <List<String>>[];
  GitResult result = const GitResult(0, '', '');
  GitCancel? lastCancel;

  /// The timeout the writer asked for. Null means it asked for nothing, which
  /// is not the same as asking for no limit: the service then applies its own
  /// default, and that is the distinction a long-running command lives or
  /// dies by.
  Duration? lastTimeout;

  /// The environment overrides the writer asked for. Null means it asked for
  /// none, so the command inherits the user's locale whole.
  Map<String, String>? lastEnvironment;

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
    lastTimeout = timeout;
    lastEnvironment = environment;
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

  group('the command flag follows the shell, not the platform', () {
    test('a POSIX shell takes -c whatever the platform is', () {
      // The Windows case that matters: $SHELL is set, by Git Bash or MSYS, so
      // the shell picked is a POSIX one. Keying the flag off the platform
      // handed it `/c`, which bash reads as a path to run.
      expect(shellCommandFlag('/bin/sh'), '-c');
      expect(shellCommandFlag('/bin/zsh'), '-c');
      expect(shellCommandFlag(r'C:\Program Files\Git\usr\bin\bash.exe'), '-c');
      expect(shellCommandFlag('C:/Program Files/Git/bin/bash.exe'), '-c');
    });

    test('cmd takes /c, by whichever spelling it arrives', () {
      expect(shellCommandFlag('cmd.exe'), '/c');
      expect(shellCommandFlag(r'C:\Windows\System32\CMD.EXE'), '/c');
      expect(shellCommandFlag('cmd'), '/c');
    });

    test('the args always agree with the shell they name', () {
      // Holds on every platform: whatever shell got chosen here, the flag
      // beside it is the one that shell understands.
      final args = bisectRunArgs('true');
      expect(args[3], shellCommandFlag(args[2]));
    });
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

  test('bisectRun asks for far more time than the ordinary default', () async {
    await writer.bisectRun('npm test');

    // Asking for nothing is NOT asking for no limit: `run` falls back to
    // `defaultTimeout`, so a null here means a real `npm test` is SIGKILLed
    // 30 seconds into a hunt that legitimately takes hours, and the user is
    // told the command "failed".
    expect(
      git.lastTimeout,
      isNotNull,
      reason: 'no timeout means the 30s default, not an unlimited run',
    );
    expect(
      git.lastTimeout,
      greaterThan(const SystemGitService().defaultTimeout),
    );
    // A run is the command multiplied by the number of steps; anything short
    // of hours is a limit real suites hit.
    expect(git.lastTimeout, greaterThanOrEqualTo(const Duration(hours: 1)));
  });

  group('a run asks git for its own diagnostics in English', () {
    test(
      'the message locale is pinned, whatever the user runs under',
      () async {
        await writer.bisectRun('npm test');

        final env = git.lastEnvironment;
        expect(
          env,
          isNotNull,
          reason:
              'inheriting the locale whole leaves git translating its own '
              'endings, which nothing downstream can then read',
        );
        // LANGUAGE wins over every LC_* for gettext, and an LC_ALL in the
        // environment wins over LC_MESSAGES, so pinning LC_MESSAGES alone is
        // defeated by either of them. An empty value reads as unset.
        expect(env!['LC_MESSAGES'], 'C');
        expect(env['LC_ALL'], isEmpty);
        expect(env['LANGUAGE'], isEmpty);
      },
    );

    test('nothing but the message locale is touched', () async {
      await writer.bisectRun('npm test');

      // The user's own command runs under this environment too. Forcing the
      // whole locale to C would change its character encoding — a Python
      // suite drops to ASCII filesystem handling and starts raising on
      // filenames it read fine yesterday. LC_CTYPE and LANG are left alone,
      // so only the language of diagnostics changes.
      final env = git.lastEnvironment!;
      expect(env.containsKey('LC_CTYPE'), isFalse);
      expect(env.containsKey('LANG'), isFalse);
      expect(env.keys.toSet(), {'LC_ALL', 'LC_MESSAGES', 'LANGUAGE'});
    });

    test('a write that is not a run leaves the environment alone', () async {
      await writer.bisectMark('bad', 'aaa1111');
      expect(git.lastEnvironment, isNull);
    });
  });

  test('a write that is not a run keeps the ordinary default', () async {
    // The generous limit belongs to `bisect run` alone. Handing it to every
    // bisect command would leave a wedged `bisect good` holding its lane for
    // hours instead of failing in seconds.
    await writer.bisectMark('bad', 'aaa1111');
    expect(git.lastTimeout, isNull);
  });
}
