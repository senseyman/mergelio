import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/signature.dart';

/// Integration tests: SSH-sign commits and tags in a real temporary
/// repository and read them back through [GitReader]. The parser tests feed
/// hand-written strings; this checks them against what git and ssh-keygen
/// actually print. SSH rather than GPG because it needs no agent or keyring.
void main() {
  const svc = SystemGitService();
  // `ssh-keygen -?` exits non-zero with usage; only a missing binary throws.
  bool probe() {
    try {
      Process.runSync('ssh-keygen', ['-?']);
      return true;
    } on ProcessException {
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

  test('without allowed signers an SSH signature is untrusted', () async {
    final v = await reader().signatureVerdict('HEAD~1');
    expect(v.state, SignatureState.untrusted);
    expect(v.signer, isEmpty);
    expect(v.isSsh, isTrue);
    expect(await reader().allowedSignersFile(), isNull);
    expect(
      signatureHint(v, allowedSignersFile: null),
      SignatureHint.sshNoAllowedSigners,
    );
  }, skip: !hasSshKeygen);

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
    final raw = await g(repo, ['cat-file', 'commit', 'HEAD~1']);
    final forged = await svc.run(
      ['hash-object', '-t', 'commit', '-w', '--stdin'],
      repoPath: repo,
      stdin: '${raw.replaceFirst('\nsigned', '\nforged')}\n',
    );
    final v = await reader().signatureVerdict(forged.out);
    expect(v.state, SignatureState.bad);
  }, skip: !hasSshKeygen);

  test('only the signed tag is listed, and it verifies', () async {
    final sha = await g(repo, ['rev-parse', 'HEAD~1']);
    expect(await reader().signedTagsAt(sha), ['v1']);

    expect((await reader().verifyTag('v1')).state, SignatureState.untrusted);

    await File(allowed).writeAsString('t@example.com $pubKey\n');
    await g(repo, ['config', 'gpg.ssh.allowedSignersFile', allowed]);
    final v = await reader().verifyTag('v1');
    expect(v.state, SignatureState.good);
    expect(v.signer, 't@example.com');
    expect(v.isSsh, isTrue);

    expect((await reader().verifyTag('v1-plain')).state, SignatureState.none);
  }, skip: !hasSshKeygen);

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
}
