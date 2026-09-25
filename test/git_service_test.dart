import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/logging.dart';
import 'package:mergelio/domain/git/git_service.dart';

void main() {
  group('SystemGitService', () {
    test('kills the process and throws GitException on timeout', () async {
      // Use `sleep` as a stand-in long-running process.
      const svc = SystemGitService(gitBinary: 'sleep');
      await expectLater(
        svc.run(['5'], timeout: const Duration(milliseconds: 150)),
        throwsA(
          isA<GitException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    }, skip: Platform.isWindows ? 'no `sleep` on Windows' : false);

    test(
      'keeps malformed UTF-8 in command output instead of throwing',
      () async {
        // Octal 303 is a UTF-8 lead byte with no continuation after it:
        // exactly what a repository carrying latin-1 filenames or commit
        // messages hands back. It should come through as the replacement
        // character, with the text around it intact.
        const svc = SystemGitService(gitBinary: '/bin/sh');
        final res = await svc.run(['-c', r'printf "hi\303bye"']);
        expect(res.exitCode, 0);
        expect(res.out, 'hi\u{FFFD}bye');
      },
      skip: Platform.isWindows ? 'no `/bin/sh` on Windows' : false,
    );

    test(
      'reports the timeout of a child that is still writing output',
      () async {
        // The child writes, then outlives the timeout while a grandchild holds
        // its pipe open: the output futures can neither be awaited nor safely
        // abandoned. Nothing from them may escape as an unhandled async error.
        const svc = SystemGitService(gitBinary: '/bin/sh');
        final unhandled = <Object>[];
        Object? thrown;
        // Assertions stay outside the guarded zone: a failing matcher inside
        // it would be captured as an unhandled error rather than reported.
        await runZonedGuarded(() async {
          try {
            await svc.run([
              '-c',
              r'printf "hi\303bye"; sleep 5',
            ], timeout: const Duration(milliseconds: 150));
          } catch (e) {
            thrown = e;
          }
        }, (error, _) => unhandled.add(error));
        // Give a dropped future a chance to surface before asserting.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          thrown,
          isA<GitException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        );
        expect(unhandled, isEmpty);
      },
      skip: Platform.isWindows ? 'no `/bin/sh` on Windows' : false,
    );

    test('isRepository returns false for a nonexistent path', () async {
      const svc = SystemGitService();
      expect(await svc.isRepository('/no/such/path/mergelio-xyz'), isFalse);
    });

    test('writes stdin to the child when given', () async {
      const svc = SystemGitService(gitBinary: '/bin/cat');
      final res = await svc.run(const [], stdin: 'hello\n');
      expect(res.exitCode, 0);
      expect(res.out, 'hello');
    }, skip: Platform.isWindows ? 'no `/bin/cat` on Windows' : false);

    test(
      'still closes stdin when none is given, so a reader does not hang',
      () async {
        const svc = SystemGitService(gitBinary: '/bin/cat');
        final res = await svc.run(
          const [],
          timeout: const Duration(seconds: 5),
        );
        expect(res.exitCode, 0);
        expect(res.out, isEmpty);
      },
      skip: Platform.isWindows ? 'no `/bin/cat` on Windows' : false,
    );

    test('survives a child that exits before reading its stdin', () async {
      // A broken pipe must not escape as an unhandled async error; the
      // child's exit code is the real result.
      const svc = SystemGitService(gitBinary: '/bin/sh');
      final unhandled = <Object>[];
      late GitResult res;
      await runZonedGuarded(() async {
        res = await svc.run(const ['-c', 'exit 3'], stdin: 'x' * 200000);
      }, (error, _) => unhandled.add(error));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(res.exitCode, 3);
      expect(unhandled, isEmpty);
    }, skip: Platform.isWindows ? 'no `/bin/sh` on Windows' : false);

    group('a bisect run command never reaches the log', () {
      // The command is the user's own shell line: `TOKEN=… ./deploy-test.sh`
      // is an ordinary thing to bisect with. They see it before it runs and
      // have no reason to expect it copied into a file that outlives the
      // session, which is what the app log is.
      const secret = 'MERGELIO_SECRET_TOKEN_9f3a';

      /// The argument list production builds for a run, with the secret in the
      /// place the user's own command occupies.
      const runArgs = ['bisect', 'run', '/bin/sh', '-c', 'echo $secret'];

      late List<String> lines;
      late AppLogger logger;

      setUp(() {
        final sink = _CapturingSink();
        lines = sink.lines;
        // Debug level, so nothing is missed because of a filter rather than
        // because of redaction.
        logger = AppLogger(sink: sink, level: LogLevel.debug);
      });

      /// A file that ignores its arguments and outlives any timeout, so a
      /// stand-in git can be handed the real run's argument list and still
      /// hang the way a long command does.
      Future<String> aBinaryThatHangs() async {
        final dir = await Directory.systemTemp.createTemp('mergelio_hang_');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/hang.sh');
        await file.writeAsString('#!/bin/sh\nsleep 5\n');
        await Process.run('chmod', ['+x', file.path]);
        return file.path;
      }

      test('the recorded line names the run without quoting it', () async {
        final svc = SystemGitService(
          // Ignores its arguments and exits at once: the record below is
          // written whatever the command did.
          gitBinary: '/usr/bin/true',
          logger: logger,
          // Every command counts as slow, so this exercises the warn branch —
          // the one a real run takes, and the one that survives the default
          // log level and reaches the file.
          slowAfter: Duration.zero,
        );

        await svc.run(runArgs);

        expect(lines, isNotEmpty);
        final logged = lines.join('\n');
        expect(
          logged,
          isNot(contains(secret)),
          reason: 'the app log is a file on disk that outlives the session',
        );
        // Still enough to diagnose a failed run: that a run happened, which
        // shell carried it, and how long it took.
        expect(logged, contains('bisect run'));
        expect(logged, contains('/bin/sh'));
        expect(logged, contains('ms'));
      });

      test('a timeout reports the run without quoting it', () async {
        final svc = SystemGitService(
          gitBinary: await aBinaryThatHangs(),
          logger: logger,
          slowAfter: Duration.zero,
        );

        Object? thrown;
        try {
          await svc.run(runArgs, timeout: const Duration(milliseconds: 150));
        } catch (e) {
          thrown = e;
        }

        // This message is what `AppLogger.timed` writes into the log when the
        // op it wraps throws, so a command quoted here is a command on disk.
        expect(thrown, isA<GitException>());
        expect('$thrown', isNot(contains(secret)));
        expect('$thrown', contains('timed out'));
        expect(lines.join('\n'), isNot(contains(secret)));
      });

      test('a cancel reports the run without quoting it', () async {
        final svc = SystemGitService(
          gitBinary: await aBinaryThatHangs(),
          logger: logger,
          slowAfter: Duration.zero,
        );
        final cancel = GitCancel();

        Object? thrown;
        final run = svc.run(runArgs, cancel: cancel).catchError((Object e) {
          thrown = e;
          return const GitResult(0, '', '');
        });
        await Future<void>.delayed(const Duration(milliseconds: 80));
        cancel.cancel();
        await run;

        expect(thrown, isA<GitCancelledException>());
        expect('$thrown', isNot(contains(secret)));
        expect(lines.join('\n'), isNot(contains(secret)));
      });
    }, skip: Platform.isWindows ? 'no POSIX shell on Windows' : false);

    group('redactedGitArgs', () {
      test('a command that is not a run is left whole', () {
        // Redacting everything would cost the log its whole value: which
        // command ran is how a failure is diagnosed.
        expect(redactedGitArgs(['rev-parse', 'HEAD']), 'rev-parse HEAD');
        expect(
          redactedGitArgs(['bisect', 'good', 'aaa1111']),
          'bisect good aaa1111',
        );
      });

      test('a run keeps its shell and loses its command', () {
        final line = redactedGitArgs([
          'bisect',
          'run',
          '/bin/zsh',
          '-c',
          'TOKEN=hunter2 ./deploy.sh',
        ]);
        expect(line, isNot(contains('hunter2')));
        expect(line, isNot(contains('deploy.sh')));
        // The shell and its flag stay: neither is the user's to keep private,
        // and which shell was picked is the thing that went wrong last time.
        expect(line, 'bisect run /bin/zsh -c <command redacted>');
      });

      test('a cmd run keeps its own flag', () {
        expect(
          redactedGitArgs(['bisect', 'run', 'cmd.exe', '/c', 'rake test']),
          'bisect run cmd.exe /c <command redacted>',
        );
      });

      test('anything after run that is not a shell flag is redacted too', () {
        // Nothing guarantees a later caller keeps the shell shape. Whatever
        // is not recognisably `<shell> <flag>` is treated as the command.
        expect(
          redactedGitArgs(['bisect', 'run', './t.sh', '--token=abc']),
          'bisect run <command redacted>',
        );
        expect(
          redactedGitArgs(['bisect', 'run', 'make test']),
          'bisect run <command redacted>',
        );
      });

      test('a bare run has nothing to redact', () {
        expect(redactedGitArgs(['bisect', 'run']), 'bisect run');
      });
    });
  });
}

/// Keeps every formatted line the logger produced, so a test can look for what
/// must not be in any of them.
class _CapturingSink implements LogSink {
  final lines = <String>[];
  @override
  void write(String line) => lines.add(line);
}
