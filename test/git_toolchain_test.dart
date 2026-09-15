import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_toolchain.dart';

void main() {
  group('gitBinaryCandidates', () {
    test('prefers Homebrew prefixes on macOS', () {
      expect(gitBinaryCandidates('macos'), [
        '/opt/homebrew/bin/git',
        '/usr/local/bin/git',
      ]);
    });

    test('covers the standard Git for Windows install locations', () {
      expect(
        gitBinaryCandidates(
          'windows',
          environment: {
            'ProgramFiles': r'C:\Program Files',
            'ProgramFiles(x86)': r'C:\Program Files (x86)',
            'LOCALAPPDATA': r'C:\Users\dev\AppData\Local',
          },
        ),
        [
          r'C:\Program Files\Git\cmd\git.exe',
          r'C:\Program Files (x86)\Git\cmd\git.exe',
          r'C:\Users\dev\AppData\Local\Programs\Git\cmd\git.exe',
        ],
      );
    });

    test('skips a Windows location whose variable is unset', () {
      expect(
        gitBinaryCandidates(
          'windows',
          environment: {'ProgramFiles': r'C:\Program Files'},
        ),
        [r'C:\Program Files\Git\cmd\git.exe'],
      );
    });

    test('leaves Linux to PATH, where the packages guarantee git', () {
      expect(gitBinaryCandidates('linux'), isEmpty);
    });
  });

  group('missingGitMessage', () {
    test('points Windows users at the PATH option they missed', () {
      final message = missingGitMessage('windows');
      expect(message, contains('Git for Windows'));
      expect(message, contains('PATH'));
    });

    test('points macOS users at an installer', () {
      expect(missingGitMessage('macos'), contains('xcode-select --install'));
    });

    test('points Linux users at their package manager', () {
      expect(missingGitMessage('linux'), contains('package manager'));
    });
  });

  group('resolveGitBinary', () {
    test('takes the first candidate that exists', () {
      final probed = <String>[];
      final picked = resolveGitBinary(
        candidates: ['/a/git', '/b/git'],
        exists: (p) {
          probed.add(p);
          return true;
        },
      );
      expect(picked, '/a/git');
      expect(probed, ['/a/git']);
    });

    test('falls through to a later candidate when the first is absent', () {
      final picked = resolveGitBinary(
        candidates: ['/a/git', '/b/git'],
        exists: (p) => p == '/b/git',
      );
      expect(picked, '/b/git');
    });

    test('falls back to PATH lookup when no candidate exists', () {
      expect(
        resolveGitBinary(candidates: ['/a/git'], exists: (_) => false),
        'git',
      );
      expect(
        resolveGitBinary(candidates: const [], exists: (_) => false),
        'git',
      );
    });
  });

  group('toolchainFailure', () {
    test('names the fix for an unaccepted Xcode license', () {
      final message = toolchainFailure(
        69,
        'You have not agreed to the Xcode license agreements. Please run '
        "'sudo xcodebuild -license' from within a Terminal window to review "
        'and agree to the Xcode and Apple SDKs license.',
      );
      expect(message, isNotNull);
      expect(message, contains('sudo xcodebuild -license accept'));
    });

    test('names the fix for missing command line tools', () {
      final message = toolchainFailure(
        1,
        'xcrun: error: invalid active developer path '
        '(/Library/Developer/CommandLineTools), missing xcrun at: ...',
      );
      expect(message, isNotNull);
      expect(message, contains('xcode-select --install'));
    });

    test('ignores a successful command', () {
      expect(
        toolchainFailure(0, 'You have not agreed to the Xcode license'),
        isNull,
      );
    });

    test('ignores an ordinary git failure', () {
      expect(
        toolchainFailure(
          128,
          'fatal: not a git repository (or any of the '
          'parent directories): .git',
        ),
        isNull,
      );
    });
  });

  group('SystemGitService toolchain reporting', () {
    test(
      'throws GitUnavailableException when the toolchain refuses to run',
      () async {
        const svc = SystemGitService(gitBinary: '/bin/sh');
        await expectLater(
          svc.run([
            '-c',
            'echo "You have not agreed to the Xcode license agreements." >&2; '
                'exit 69',
          ]),
          throwsA(
            isA<GitUnavailableException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('sudo xcodebuild -license accept'),
                )
                .having((e) => e, 'is a GitException', isA<GitException>()),
          ),
        );
      },
      skip: Platform.isWindows ? 'no `/bin/sh` on Windows' : false,
    );

    test(
      'keeps the actionable message where handlers prefer git stderr',
      () async {
        // Error handlers show `e.result?.err ?? e.message`, preferring git's
        // own words. For a broken toolchain those words are the raw shim
        // complaint; the advice we wrote is the better of the two, so it must
        // not be hidden behind a result.
        const svc = SystemGitService(gitBinary: '/bin/sh');
        try {
          await svc.run([
            '-c',
            'echo "You have not agreed to the Xcode license agreements." >&2; '
                'exit 69',
          ]);
          fail('expected GitUnavailableException');
        } on GitException catch (e) {
          final shown = e.result?.err ?? e.message;
          expect(shown, contains('sudo xcodebuild -license accept'));
        }
      },
      skip: Platform.isWindows ? 'no `/bin/sh` on Windows' : false,
    );

    test(
      'lets a broken toolchain out of isRepository instead of saying no',
      () async {
        // Answering "not a repository" for a git that cannot run turns a
        // toolchain problem into a lie about the user's directory.
        const svc = SystemGitService(gitBinary: '/nonexistent/git');
        await expectLater(
          svc.isRepository('/tmp'),
          throwsA(isA<GitUnavailableException>()),
        );
      },
    );

    test('still answers no for a path that is not a repository', () async {
      const svc = SystemGitService();
      expect(await svc.isRepository('/nonexistent/path/xyz'), isFalse);
    });

    test('discovers a git to run when none was configured', () async {
      // No gitBinary: the service must find one on its own, the way the app
      // does when the launcher hands it a bare PATH.
      const svc = SystemGitService();
      expect(await svc.version(), startsWith('git version'));
    });

    test(
      'reports a missing git as unavailable, with the install hint',
      () async {
        const svc = SystemGitService(gitBinary: '/nonexistent/git');
        await expectLater(
          svc.run(['--version']),
          throwsA(
            isA<GitUnavailableException>()
                .having(
                  (e) => e.message,
                  'names the attempted binary',
                  contains('/nonexistent/git'),
                )
                .having(
                  (e) => e.message,
                  'carries the install hint',
                  contains(missingGitMessage(Platform.operatingSystem)),
                ),
          ),
        );
      },
    );

    test(
      'blames a missing working directory on the repository, not on git',
      () async {
        // Same ProcessException, different cause: git is fine, the path is
        // not. Telling the user to install git would send them nowhere.
        const svc = SystemGitService(gitBinary: '/bin/sh');
        await expectLater(
          svc.run(['-c', 'true'], repoPath: '/nonexistent/repo'),
          throwsA(
            allOf(isA<GitException>(), isNot(isA<GitUnavailableException>())),
          ),
        );
      },
      skip: Platform.isWindows ? 'no `/bin/sh` on Windows' : false,
    );

    test('leaves an ordinary non-zero exit as a plain result', () async {
      const svc = SystemGitService(gitBinary: '/bin/sh');
      final res = await svc.run([
        '-c',
        'echo "fatal: not a git repository" >&2; exit 128',
      ]);
      expect(res.exitCode, 128);
      expect(res.err, contains('not a git repository'));
    }, skip: Platform.isWindows ? 'no `/bin/sh` on Windows' : false);
  });
}
