// A remote that stops answering otherwise hangs a network operation until its
// own timeout, minutes later. These SSH options make the connection give up in
// seconds — without discarding whatever ssh command the user already set.
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  final List<Map<String, String>?> envs = [];

  /// Value reported by `git config --get core.sshCommand`.
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
    envs.add(environment);
    if (args.contains('core.sshCommand')) {
      return GitResult(coreSshCommand.isEmpty ? 1 : 0, coreSshCommand, '');
    }
    return const GitResult(0, '', '');
  }

  /// The environment of the last command matching [command].
  Map<String, String>? envFor(String command) {
    for (var i = calls.length - 1; i >= 0; i--) {
      if (calls[i].first == command) return envs[i];
    }
    return null;
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  group('sshCommandWith', () {
    test('falls back to plain ssh when nothing is configured', () {
      expect(sshCommandWith(null), startsWith('ssh -o '));
      expect(sshCommandWith('   '), startsWith('ssh -o '));
    });

    test('keeps the configured command and appends the watchdog options', () {
      final cmd = sshCommandWith('ssh -i ~/.ssh/work');

      expect(cmd, startsWith('ssh -i ~/.ssh/work '));
      expect(cmd, contains('-o ConnectTimeout=10'));
      expect(cmd, contains('-o ServerAliveInterval=5'));
      expect(cmd, contains('-o ServerAliveCountMax=3'));
    });

    test("leaves the user's own value of an option in front, so it wins", () {
      // ssh takes the first value it sees for an option, so anything the user
      // set has to stay ahead of ours.
      final cmd = sshCommandWith('ssh -o ConnectTimeout=60');

      expect(
        cmd.indexOf('ConnectTimeout=60'),
        lessThan(cmd.indexOf('ConnectTimeout=10')),
      );
    });
  });

  group('network commands', () {
    late _FakeGit git;
    late GitWriter writer;

    setUp(() {
      git = _FakeGit();
      writer = GitWriter(git, '/r');
    });

    test('fetch carries the watchdog ssh command', () async {
      await writer.fetch();

      expect(
        git.envFor('fetch')?['GIT_SSH_COMMAND'],
        contains('ConnectTimeout=10'),
      );
    });

    test('push carries the watchdog ssh command', () async {
      await writer.push();

      expect(
        git.envFor('push')?['GIT_SSH_COMMAND'],
        contains('ServerAliveInterval=5'),
      );
    });

    test("builds on the repository's core.sshCommand when it is set", () async {
      git.coreSshCommand = 'ssh -i /keys/deploy';

      await writer.fetch();

      expect(
        git.envFor('fetch')?['GIT_SSH_COMMAND'],
        startsWith('ssh -i /keys/deploy '),
      );
    });

    test('a local command gets no ssh environment', () async {
      await writer.createBranch('feature');

      expect(git.envFor('branch'), isNull);
    });
  });
}
