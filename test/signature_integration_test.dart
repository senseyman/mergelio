import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/signature.dart';

/// Integration tests: SSH-sign commits and tags in a real temporary
/// repository and read them back through [GitReader]. The parser tests feed
/// hand-written strings; this checks them against what git and ssh-keygen
/// actually print. SSH rather than GPG because it needs no agent or keyring.
///
/// git runs with the developer's global and system config switched off: a
/// global `gpg.ssh.allowedSignersFile`, even an empty one, changes what git
/// prints for every SSH signature (this file once passed on a laptop and
/// failed on CI for exactly that reason).
void main() {
  const svc = _HermeticGit();
  // `ssh-keygen -?` exits non-zero with usage; only a missing binary throws.
  bool probe() {
    // Any failure to probe means skip, never a broken file.
    try {
      Process.runSync('ssh-keygen', ['-?']);
      return true;
    } catch (_) {
      return false;
    }
  }

  final hasSshKeygen = probe();

  Future<String> g(String repo, List<String> args) async {
    final r = await svc.run(args, repoPath: repo);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  late Directory dir;
  late String repo;
  late String pubKey;
  late String allowed;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_sig_');
    repo = '${dir.path}/r';
    await Directory(repo).create();
    final key = '${dir.path}/key';
    final k = await Process.run('ssh-keygen', [
      '-q',
      '-t',
      'ed25519',
      '-N',
      '',
      '-C',
      't@example.com',
      '-f',
      key,
    ]);
    if (k.exitCode != 0) throw StateError('ssh-keygen failed: ${k.stderr}');
    pubKey = (await File('$key.pub').readAsString()).trim();
    allowed = '${dir.path}/allowed_signers';

    await g(repo, ['init', '-q']);
    await g(repo, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(repo, ['config', 'user.email', 't@example.com']);
    await g(repo, ['config', 'user.name', 'Tester']);
    await g(repo, ['config', 'gpg.format', 'ssh']);
    await g(repo, ['config', 'user.signingkey', '$key.pub']);
    await g(repo, ['config', 'commit.gpgsign', 'false']);
    await g(repo, ['config', 'tag.gpgsign', 'false']);

    await g(repo, ['commit', '-q', '--allow-empty', '-m', 'base']);
    await g(repo, ['tag', 'base']);
    await g(repo, ['commit', '-q', '--allow-empty', '-S', '-m', 'signed']);
    await g(repo, ['tag', '-s', '-m', 'release', 'v1']);
    await g(repo, ['tag', '-a', '-m', 'plain', 'v1-plain']);
    await g(repo, ['commit', '-q', '--allow-empty', '-m', 'unsigned']);
  });

  tearDown(() => dir.delete(recursive: true));

  GitReader reader() => GitReader(svc, repo);

  Future<void> allowKey() async {
    await File(allowed).writeAsString('t@example.com $pubKey\n');
    await g(repo, ['config', 'gpg.ssh.allowedSignersFile', allowed]);
  }

  test('git\'s default refuses SSH verification; that is never '
      '"unsigned"', () async {
    // No allowed signers file configured: git prints N and explains only on
    // stderr.
    expect(await reader().allowedSignersFile(), isNull);
    final v = await reader().signatureVerdict('HEAD~1');
    expect(v.state, SignatureState.unverifiable);
    expect(sshSignersUnconfigured(v.detail), isTrue);
    expect(
      signatureHint(v, allowedSignersFile: null),
      SignatureHint.sshNoAllowedSigners,
    );

    final tag = await reader().verifyTag('v1');
    expect(tag.state, SignatureState.unverifiable);
    expect(
      signatureHint(tag, allowedSignersFile: null),
      SignatureHint.sshNoAllowedSigners,
    );

    await expectLater(
      reader().signatureAudit('base'),
      throwsA(isA<GitException>()),
    );
  }, skip: !hasSshKeygen);

  test(
    'an empty allowed signers setting checks the key but names no one',
    () async {
      await g(repo, ['config', 'gpg.ssh.allowedSignersFile', '']);
      final v = await reader().signatureVerdict('HEAD~1');
      expect(v.state, SignatureState.untrusted);
      expect(v.signer, isEmpty);
      expect(v.isSsh, isTrue);
      expect(
        signatureHint(v, allowedSignersFile: null),
        SignatureHint.sshNoAllowedSigners,
      );
    },
    skip: !hasSshKeygen,
  );

  test('a listed key verifies and names its principal', () async {
    await File(allowed).writeAsString('t@example.com $pubKey\n');
    await g(repo, ['config', 'gpg.ssh.allowedSignersFile', allowed]);

    final v = await reader().signatureVerdict('HEAD~1');
    expect(v.state, SignatureState.good);
    expect(v.signer, 't@example.com');
    expect(await reader().allowedSignersFile(), allowed);
  }, skip: !hasSshKeygen);

  test('an unsigned commit reads as unsigned', () async {
    final v = await reader().signatureVerdict('HEAD');
    expect(v.state, SignatureState.none);
    expect(v.trust, isEmpty);
  }, skip: !hasSshKeygen);

  test('a tampered commit is bad', () async {
    await allowKey();
    final raw = await g(repo, ['cat-file', 'commit', 'HEAD~1']);
    final forged = await svc.run(
      ['hash-object', '-t', 'commit', '-w', '--stdin'],
      repoPath: repo,
      stdin: '${raw.replaceFirst('\nsigned', '\nforged')}\n',
    );
    final v = await reader().signatureVerdict(forged.out);
    expect(v.state, SignatureState.bad);
  }, skip: !hasSshKeygen);

  test(
    'the commit carries its tags, and only the signed one verifies',
    () async {
      final sha = await g(repo, ['rev-parse', 'HEAD~1']);
      final c = await reader().commit(sha);
      expect(
        c!.refs.where((r) => r.kind == RefKind.tag).map((r) => r.name).toSet(),
        {'v1', 'v1-plain'},
      );

      expect(
        (await reader().verifyTag('v1')).state,
        SignatureState.unverifiable,
      );

      await allowKey();
      final v = await reader().verifyTag('v1');
      expect(v.state, SignatureState.good);
      expect(v.signer, 't@example.com');
      expect(v.isSsh, isTrue);

      expect((await reader().verifyTag('v1-plain')).state, SignatureState.none);
    },
    skip: !hasSshKeygen,
  );

  test(
    'the audit lists every commit since base that is not verified',
    () async {
      await File(allowed).writeAsString('t@example.com $pubKey\n');
      await g(repo, ['config', 'gpg.ssh.allowedSignersFile', allowed]);

      final audit = await reader().signatureAudit('base');
      expect(audit.checked, 2);
      expect(audit.truncated, isFalse);
      expect(audit.unverified.single.subject, 'unsigned');
      expect(audit.unverified.single.verdict.state, SignatureState.none);
    },
    skip: !hasSshKeygen,
  );

  test('a bad base ref fails with git\'s message', () async {
    await expectLater(
      reader().signatureAudit('no-such-ref'),
      throwsA(isA<GitException>()),
    );
  }, skip: !hasSshKeygen);

  test('a missing ssh-keygen is unverifiable, never bad', () async {
    // git checks for an allowed signers file before it runs ssh-keygen.
    await allowKey();
    await g(repo, ['config', 'gpg.ssh.program', 'mergelio-no-such-keygen']);

    final v = await reader().signatureVerdict('HEAD~1');
    expect(v.state, SignatureState.unverifiable);
    expect(
      signatureHint(v, allowedSignersFile: null),
      SignatureHint.verifierMissing,
    );
    expect(missingVerifier(v.detail), 'mergelio-no-such-keygen');

    final tag = await reader().verifyTag('v1');
    expect(tag.state, SignatureState.unverifiable);

    await expectLater(
      reader().signatureAudit('base'),
      throwsA(isA<GitException>()),
    );
  }, skip: !hasSshKeygen);

  test('a configured allowed signers file that is gone is named', () async {
    await g(repo, ['config', 'gpg.ssh.allowedSignersFile', '${dir.path}/gone']);
    final v = await reader().signatureVerdict('HEAD~1');
    expect(v.state, SignatureState.untrusted);
    expect(
      signatureHint(v, allowedSignersFile: '${dir.path}/gone'),
      SignatureHint.sshAllowedSignersUnreadable,
    );
    expect(allowedSignersPathIn(v.detail), '${dir.path}/gone');
  }, skip: !hasSshKeygen);

  test(
    'a key missing from a readable allowed signers file is named so',
    () async {
      final other = '${dir.path}/other';
      await Process.run('ssh-keygen', [
        '-q', '-t', 'ed25519', '-N', '', '-f', other, //
      ]);
      final otherKey = (await File('$other.pub').readAsString()).trim();
      await File(allowed).writeAsString('someone@else $otherKey\n');
      await g(repo, ['config', 'gpg.ssh.allowedSignersFile', allowed]);
      final v = await reader().signatureVerdict('HEAD~1');
      expect(v.state, SignatureState.untrusted);
      expect(
        signatureHint(v, allowedSignersFile: allowed),
        SignatureHint.sshKeyNotAllowed,
      );
    },
    skip: !hasSshKeygen,
  );
}

/// [SystemGitService] with global and system git config ignored, so the
/// developer's own signing setup cannot change what these tests observe.
class _HermeticGit implements GitService {
  const _HermeticGit();

  static const _inner = SystemGitService();
  static const _isolation = {
    'GIT_CONFIG_GLOBAL': '/dev/null',
    'GIT_CONFIG_NOSYSTEM': '1',
  };

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => _inner.run(
    args,
    repoPath: repoPath,
    timeout: timeout,
    environment: {...?environment, ..._isolation},
    cancel: cancel,
    stdin: stdin,
  );

  @override
  Future<String> version() => _inner.version();

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);
}
