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

    test('isRepository returns false for a nonexistent path', () async {
      const svc = SystemGitService();
      expect(await svc.isRepository('/no/such/path/mergelio-xyz'), isFalse);
    });
  });
}
