import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/domain/git/git_service.dart';

/// Records what it was asked to run and answers from a script.
class _RecordingGit implements GitService {
  final GitResult result;
  final List<List<String>> calls = [];
  final List<String?> stdins = [];

  _RecordingGit(this.result);

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
    stdins.add(stdin);
    return result;
  }

  @override
  Future<bool> isRepository(String path) async => true;

  @override
  Future<String> version() async => 'git version 2.55.0';
}

void main() {
  group('credentialRequestFor', () {
    test('builds a request ending in a blank line', () {
      expect(
        credentialRequestFor('github.com'),
        'protocol=https\nhost=github.com\n\n',
      );
    });

    test('refuses a host that could inject extra fields', () {
      // The credential protocol is newline-delimited, so a host carrying one
      // would smuggle in a field of the attacker's choosing.
      for (final host in [
        'github.com\nusername=attacker',
        'github.com\r\nhost=evil.example',
        'github.com${String.fromCharCode(0)}',
        'github.com${String.fromCharCode(0x7f)}',
        'has space.com',
        '',
        '   ',
      ]) {
        expect(credentialRequestFor(host), isNull, reason: host);
      }
    });
  });

  group('parseCredentialReply', () {
    test('reads key=value lines', () {
      final fields = parseCredentialReply(
        'protocol=https\nhost=github.com\nusername=octocat\npassword=ghp_x\n',
      );
      expect(fields['username'], 'octocat');
      expect(fields['password'], 'ghp_x');
    });

    test('tolerates CRLF line endings', () {
      final fields = parseCredentialReply('username=octocat\r\npassword=t\r\n');
      expect(fields['password'], 't');
    });

    test('keeps a value containing an equals sign intact', () {
      final fields = parseCredentialReply('password=abc=def==\n');
      expect(fields['password'], 'abc=def==');
    });

    test('ignores blank and malformed lines', () {
      final fields = parseCredentialReply('\nnonsense\npassword=t\n');
      expect(fields, hasLength(1));
      expect(fields['password'], 't');
    });
  });

  group('ForgeToken', () {
    test('never prints its value', () {
      const token = ForgeToken('ghp_secretvalue');
      expect(token.toString(), isNot(contains('ghp_secretvalue')));
      expect('$token', isNot(contains('ghp_secretvalue')));
      expect('token: $token', 'token: ForgeToken(hidden)');
    });
  });

  group('ForgeCredentials', () {
    test('fill returns the password the helper supplied', () async {
      final git = _RecordingGit(
        const GitResult(0, 'username=octocat\npassword=ghp_x\n', ''),
      );
      final token = await ForgeCredentials(git).fill('github.com');

      expect(token?.value, 'ghp_x');
      expect(git.calls.single, const ['credential', 'fill']);
      expect(git.stdins.single, 'protocol=https\nhost=github.com\n\n');
    });

    test('fill returns null when the helper has nothing', () async {
      final git = _RecordingGit(const GitResult(0, 'protocol=https\n', ''));
      expect(await ForgeCredentials(git).fill('github.com'), isNull);
    });

    test('fill returns null when git itself fails', () async {
      final git = _RecordingGit(const GitResult(1, '', 'no helper configured'));
      expect(await ForgeCredentials(git).fill('github.com'), isNull);
    });

    test('fill refuses an unusable host without running git', () async {
      final git = _RecordingGit(const GitResult(0, '', ''));
      expect(await ForgeCredentials(git).fill('bad\nhost'), isNull);
      expect(git.calls, isEmpty);
    });

    test('approve hands the token to the helper on stdin, never as an argument', () async {
      final git = _RecordingGit(const GitResult(0, '', ''));
      await ForgeCredentials(git)
          .approve('github.com', 'octocat', const ForgeToken('ghp_x'));

      expect(git.calls.single, const ['credential', 'approve']);
      expect(
        git.stdins.single,
        'protocol=https\nhost=github.com\nusername=octocat\npassword=ghp_x\n\n',
      );
      // A token in argv is readable by any process listing; it must only ever
      // travel on stdin.
      expect(git.calls.single.join(' '), isNot(contains('ghp_x')));
    });

    test('reject asks the helper to forget the credential', () async {
      final git = _RecordingGit(const GitResult(0, '', ''));
      await ForgeCredentials(git)
          .reject('github.com', const ForgeToken('ghp_x'));

      expect(git.calls.single, const ['credential', 'reject']);
      expect(git.stdins.single, contains('password=ghp_x'));
    });

    test('approve does nothing when the host is unusable', () async {
      final git = _RecordingGit(const GitResult(0, '', ''));
      await ForgeCredentials(git)
          .approve('bad\nhost', 'u', const ForgeToken('t'));
      expect(git.calls, isEmpty);
    });
  });
}
