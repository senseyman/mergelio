import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';

void main() {
  group('SystemGitService', () {
    test(
      'kills the process and throws GitException on timeout',
      () async {
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
      },
      skip: Platform.isWindows ? 'no `sleep` on Windows' : false,
    );

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
  });
}
