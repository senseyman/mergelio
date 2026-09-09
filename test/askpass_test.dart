// A GUI app has no terminal for git or ssh to prompt on, so an operation that
// needs a passphrase or password fails cryptically instead of asking. These
// cover the helper that turns such a prompt into a Mergelio dialog.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/askpass.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:path/path.dart' as p;

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  String coreSshCommand = '';

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    if (args.contains('core.sshCommand')) {
      return GitResult(coreSshCommand.isEmpty ? 1 : 0, coreSshCommand, '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  group('askpassPrompt', () {
    test('is null for a normal launch', () {
      expect(askpassPrompt(const []), isNull);
      expect(askpassPrompt(const ['--verbose']), isNull);
    });

    test('returns the prompt git or ssh passed', () {
      expect(
        askpassPrompt(const ['--askpass', "Enter passphrase for key '/k':"]),
        "Enter passphrase for key '/k':",
      );
    });

    test('rejoins a prompt a shell split on spaces', () {
      expect(
        askpassPrompt(const ['--askpass', 'Password', 'for', 'user:']),
        'Password for user:',
      );
    });

    test('is empty, not null, when no prompt text came with the flag', () {
      expect(askpassPrompt(const ['--askpass']), '');
    });
  });

  group('askpassWantsMarker', () {
    test('is asked for by the helper script', () {
      expect(
        askpassWantsMarker(const ['--marked', '--askpass', 'Password: ']),
        isTrue,
      );
    });

    test('is off for a bare launch', () {
      expect(askpassWantsMarker(const ['--askpass', 'Password: ']), isFalse);
    });

    test('cannot be turned on by the prompt text itself', () {
      expect(
        askpassWantsMarker(const ['--askpass', '--marked', 'is not a flag']),
        isFalse,
      );
    });
  });

  group('askpassAnswerLine', () {
    test('is tagged when the script asked for it', () {
      expect(
        askpassAnswerLine('hunter2', marked: true),
        'MERGELIO-ASKPASS:hunter2',
      );
    });

    test('is the bare answer otherwise', () {
      expect(askpassAnswerLine('hunter2', marked: false), 'hunter2');
    });

    test('an empty answer stays answerable, tag and all', () {
      expect(askpassAnswerLine('', marked: true), 'MERGELIO-ASKPASS:');
    });
  });

  group('askpassKindOf', () {
    test('a passphrase or password is masked', () {
      expect(
        askpassKindOf("Enter passphrase for key '/k/id_ed25519': "),
        AskpassKind.secret,
      );
      expect(askpassKindOf("git@github.com's password: "), AskpassKind.secret);
      expect(
        askpassKindOf("Password for 'https://u@github.com': "),
        AskpassKind.secret,
      );
    });

    test('a username is not a secret, so it stays readable', () {
      expect(
        askpassKindOf("Username for 'https://github.com': "),
        AskpassKind.text,
      );
    });

    test('a host-key question is answered with buttons, not a field', () {
      expect(
        askpassKindOf(
          'The authenticity of host ... continue connecting '
          '(yes/no/[fingerprint])? ',
        ),
        AskpassKind.confirm,
      );
    });

    test('an unrecognised prompt is treated as a secret', () {
      expect(askpassKindOf(''), AskpassKind.secret);
    });
  });

  group('askpassScript', () {
    test('re-launches the app in askpass mode, passing the prompt through', () {
      final sh = askpassScript('/Apps/mergelio.app/x/mergelio', windows: false);

      expect(sh, startsWith('#!/bin/sh\n'));
      expect(
        sh,
        contains('"/Apps/mergelio.app/x/mergelio" --marked --askpass "\$@"'),
      );
    });

    test('hands back only the tagged line, and a refusal as a status', () {
      final sh = askpassScript('/apps/mergelio', windows: false);

      expect(sh, contains('|| exit 1'));
      expect(sh, contains("sed -n 's/^MERGELIO-ASKPASS://p'"));
    });

    test('quotes the executable so a path with spaces still runs', () {
      final cmd = askpassScript(
        r'C:\Program Files\mergelio.exe',
        windows: true,
      );

      expect(cmd, contains(r'"C:\Program Files\mergelio.exe" --askpass %*'));
    });
  });

  group('installAskpassHelper', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mergelio_askpass_');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('writes a helper the user alone can run', () async {
      final path = await installAskpassHelper(
        executable: '/apps/mergelio',
        dir: dir,
      );

      expect(path, isNotNull);
      expect(p.isWithin(dir.path, path!), isTrue);
      expect(File(path).readAsStringSync(), contains('--askpass'));
      if (!Platform.isWindows) {
        final mode = File(path).statSync().modeString();
        expect(mode, 'rwx------');
      }
    });

    test('rewrites the helper when the executable moved', () async {
      await installAskpassHelper(executable: '/old/mergelio', dir: dir);
      final path = await installAskpassHelper(
        executable: '/new/mergelio',
        dir: dir,
      );

      expect(File(path!).readAsStringSync(), contains('/new/mergelio'));
    });

    test(
      'initAskpass publishes the path every network command reads',
      () async {
        final before = askpassHelper;
        addTearDown(() => askpassHelper = before);

        await initAskpass(executable: '/apps/mergelio', dir: dir);

        expect(askpassHelper, isNotNull);
        expect(File(askpassHelper!).existsSync(), isTrue);
      },
    );

    test(
      'returns null rather than failing when it cannot be written',
      () async {
        final path = await installAskpassHelper(
          executable: '/apps/mergelio',
          dir: Directory('/proc/nonexistent/mergelio'),
        );

        expect(path, isNull);
      },
    );
  });

  group('networkEnv', () {
    test('disables the terminal prompt there is no terminal for', () {
      expect(networkEnv()['GIT_TERMINAL_PROMPT'], '0');
    });

    test('keeps the ssh watchdog options', () {
      expect(
        networkEnv(sshCommand: 'ssh -i /k')['GIT_SSH_COMMAND'],
        allOf(startsWith('ssh -i /k '), contains('ConnectTimeout=10')),
      );
    });

    test('points git and ssh at the helper, and forces ssh to use it', () {
      final env = networkEnv(askpass: '/tmp/askpass.sh');

      expect(env['GIT_ASKPASS'], '/tmp/askpass.sh');
      expect(env['SSH_ASKPASS'], '/tmp/askpass.sh');
      expect(env['SSH_ASKPASS_REQUIRE'], 'force');
    });

    test('leaves the askpass variables unset when there is no helper', () {
      final env = networkEnv();

      expect(env.containsKey('GIT_ASKPASS'), isFalse);
      expect(env.containsKey('SSH_ASKPASS'), isFalse);
    });
  });

  group('resolveNetworkEnv', () {
    test(
      'builds on core.sshCommand, asking the config git would use',
      () async {
        final git = _FakeGit()..coreSshCommand = 'ssh -i /keys/deploy';

        final env = await resolveNetworkEnv(git, askpass: '/tmp/a.sh');

        expect(env['GIT_SSH_COMMAND'], startsWith('ssh -i /keys/deploy '));
        expect(env['GIT_ASKPASS'], '/tmp/a.sh');
        expect(git.calls.single, ['config', '--get', 'core.sshCommand']);
      },
    );

    test('falls back to plain ssh when nothing is configured', () async {
      final env = await resolveNetworkEnv(_FakeGit());

      expect(env['GIT_SSH_COMMAND'], startsWith('ssh -o '));
    });
  });
}
