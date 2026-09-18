// A real `git credential` round trip against a scratch credential file.
//
// The erase body this app sends is only right or wrong in terms of what a
// credential helper does with it, and no fake can answer that. Everything
// here runs `git-credential-store` with an explicit --file under a throwaway
// directory, with the user's own configuration switched off, so nothing
// reaches the system keychain or the real $HOME.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/domain/git/git_service.dart';

/// Records the body [ForgeCredentials] would hand to git, so the same bytes
/// can then be fed to a real git process.
class _BodyRecordingGit implements GitService {
  String? body;
  List<String>? args;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    this.args = args;
    body = stdin;
    return const GitResult(0, '', '');
  }

  @override
  Future<bool> isRepository(String path) async => true;

  @override
  Future<String> version() async => 'git version 2.55.0';
}

void main() {
  late Directory scratch;
  late File store;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('mergelio_credential_');
    store = File('${scratch.path}/credentials');
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  /// Runs one `git credential <verb>` with [body] on stdin, against the
  /// scratch store and nothing else.
  ///
  /// GIT_CONFIG_GLOBAL and GIT_CONFIG_SYSTEM point at /dev/null so the
  /// developer's own helper — the macOS keychain, most likely — is never
  /// asked to act on these requests.
  Future<void> credential(String verb, String body) async {
    final process = await Process.start(
      'git',
      [
        '-c',
        'credential.helper=',
        '-c',
        'credential.helper=store --file=${store.path}',
        'credential',
        verb,
      ],
      workingDirectory: scratch.path,
      environment: {
        'GIT_CONFIG_GLOBAL': '/dev/null',
        'GIT_CONFIG_SYSTEM': '/dev/null',
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_ASKPASS': '',
        'SSH_ASKPASS': '',
        'HOME': scratch.path,
      },
    );
    process.stdin.write(body);
    await process.stdin.close();
    await process.stdout.drain<void>();
    await process.stderr.drain<void>();
    expect(await process.exitCode, 0, reason: 'git credential $verb failed');
  }

  /// Runs `git credential fill` with [body] and returns what git answered,
  /// so a test can assert on the credential that comes back rather than only
  /// on the store file.
  Future<String> fill(String body) async {
    final process = await Process.start(
      'git',
      [
        '-c',
        'credential.helper=',
        '-c',
        'credential.helper=store --file=${store.path}',
        'credential',
        'fill',
      ],
      workingDirectory: scratch.path,
      environment: {
        'GIT_CONFIG_GLOBAL': '/dev/null',
        'GIT_CONFIG_SYSTEM': '/dev/null',
        'GIT_TERMINAL_PROMPT': '0',
        'GIT_ASKPASS': '',
        'SSH_ASKPASS': '',
        'HOME': scratch.path,
      },
    );
    process.stdin.write(body);
    await process.stdin.close();
    final out = await process.stdout
        .transform(const SystemEncoding().decoder)
        .join();
    await process.stderr.drain<void>();
    return out;
  }

  Future<void> seed(String username, String password) => credential(
    'approve',
    'protocol=https\nhost=github.com\nusername=$username\n'
        'password=$password\n\n',
  );

  test('reading back finds the account this app wrote, not whichever one '
      'the host already had', () async {
    // The user's own push credential is stored first, so it is the one a
    // lookup that does not name an account will find. Writing under a
    // specific username and then reading without naming it means reading
    // somebody else's credential and sending it to the API as though it
    // were ours.
    await seed('someone', 'the-users-own-push-token');
    await seed(forgeTokenUsername, 'the-token-mergelio-stored');

    final reply = await fill(
      credentialRequestFor('github.com', forgeTokenUsername)!,
    );

    expect(
      parseCredentialReply(reply)['password'],
      'the-token-mergelio-stored',
    );
  });

  test('disconnecting erases only the entry this app stored, leaving the '
      "user's own github.com credential alone", () async {
    // Two accounts on one host: the one Mergelio wrote for API reads, and
    // whatever the user already had for pushing.
    await seed(forgeTokenUsername, 'ghp_app_token');
    await seed('octocat', 'ghp_personal_token');

    final recorder = _BodyRecordingGit();
    await ForgeCredentials(recorder)
        .reject('github.com', forgeTokenUsername, const ForgeToken(''));
    expect(recorder.args, const ['credential', 'reject']);

    await credential('reject', recorder.body!);

    final left = store.readAsStringSync();
    expect(
      left,
      isNot(contains('ghp_app_token')),
      reason: "the app's own entry must be gone",
    );
    expect(
      left,
      contains('ghp_personal_token'),
      reason: "the user's push credential must survive a disconnect",
    );
  });

  test(
    'an erase body with no username takes every account on the host with it',
    () async {
      // Why the username above is load-bearing rather than decoration: this
      // is what the same disconnect did before it named an account.
      await seed(forgeTokenUsername, 'ghp_app_token');
      await seed('octocat', 'ghp_personal_token');

      await credential('reject', 'protocol=https\nhost=github.com\n\n');

      expect(store.readAsStringSync().trim(), isEmpty);
    },
  );

  test(
    'the account the connect path writes under is the one it reads back',
    () async {
      // The erase is only aimed at the right credential while store and read
      // agree on the account name.
      final recorder = _BodyRecordingGit();
      await ForgeCredentials(recorder).approve(
        'github.com',
        forgeTokenUsername,
        const ForgeToken('ghp_app_token'),
      );
      await credential('approve', recorder.body!);

      expect(store.readAsStringSync(), contains(forgeTokenUsername));
      expect(store.readAsStringSync(), contains('ghp_app_token'));
    },
  );
}
