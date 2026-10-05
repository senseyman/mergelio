import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/signature.dart';
import 'package:mergelio/state/signatures.dart';

class _CapturingGit implements GitService {
  final calls = <List<String>>[];
  final String output;
  final String err;
  final int code;
  final timeouts = <Duration?>[];
  final cancels = <GitCancel?>[];
  _CapturingGit([this.output = '', this.err = '', this.code = 0]);

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
    timeouts.add(timeout);
    cancels.add(cancel);
    return GitResult(code, output, err);
  }

  @override
  Future<String> version() async => 'git version 2.55.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

/// `%G?` makes git verify each commit's signature, spawning gpg per signed
/// commit. On a repository that enforces signing this turns the bulk graph
/// read into thousands of gpg invocations (observed: ~4s for 4493 commits).
/// Bulk reads must therefore skip verification; only the single commit shown
/// in the details panel is verified, on demand.
void main() {
  test('bulk commits read does not verify signatures', () async {
    final git = _CapturingGit();
    await GitReader(git, '/repo').commits(maxCount: 100);

    expect(git.calls, isNotEmpty);
    for (final args in git.calls) {
      for (final a in args) {
        expect(
          a.contains('%G?'),
          isFalse,
          reason: 'git ${args.join(' ')} must not verify signatures',
        );
      }
    }
  });

  test('file history read does not verify signatures', () async {
    final git = _CapturingGit();
    await GitReader(git, '/repo').fileHistory('a.txt');

    expect(git.calls, isNotEmpty);
    for (final args in git.calls) {
      for (final a in args) {
        expect(
          a.contains('%G?'),
          isFalse,
          reason: 'git ${args.join(' ')} must not verify signatures',
        );
      }
    }
  });

  test('signatureVerdict verifies exactly one commit on demand', () async {
    final git = _CapturingGit('G\x1fme\x1fKEY\x1fFPR\x1f\x1ffully\n');
    final v = await GitReader(git, '/repo').signatureVerdict('abc123');

    expect(v.state, SignatureState.good);
    expect(v.signer, 'me');
    expect(git.calls.single, [
      'log',
      '-1',
      '--format=$kSignatureFormat',
      'abc123',
    ]);
  });

  test('signatureVerdict maps empty output to unsigned', () async {
    final git = _CapturingGit();
    final v = await GitReader(git, '/repo').signatureVerdict('abc123');
    expect(v.state, SignatureState.none);
  });

  test('allowedSignersFile reads the repo config', () async {
    final git = _CapturingGit('/home/me/.ssh/allowed_signers\n');
    expect(
      await GitReader(git, '/repo').allowedSignersFile(),
      '/home/me/.ssh/allowed_signers',
    );
    expect(git.calls.single, ['config', '--get', 'gpg.ssh.allowedSignersFile']);
  });

  test('allowedSignersFile is null when unset', () async {
    // `git config --get` exits 1 for a missing key.
    final git = _CapturingGit('', '', 1);
    expect(await GitReader(git, '/repo').allowedSignersFile(), isNull);
  });

  test('signedTagsAt lists only tags that carry a signature', () async {
    final git = _CapturingGit('v1\t1\nv2\t\nv3\t\n');
    final tags = await GitReader(git, '/repo').signedTagsAt('abc123');
    expect(tags, ['v1']);
    expect(git.calls.single.take(3), ['tag', '--points-at', 'abc123']);
  });

  test('verifyTag parses stderr even when git exits non-zero', () async {
    final git = _CapturingGit(
      '',
      'Good "git" signature with ED25519 key SHA256:abc\nNo principal matched.\n',
      1,
    );
    final v = await GitReader(git, '/repo').verifyTag('v1');
    expect(v.state, SignatureState.untrusted);
    expect(git.calls.single, ['verify-tag', '--raw', 'refs/tags/v1']);
  });

  test('signatureAudit walks base..HEAD with a long timeout', () async {
    final git = _CapturingGit(
      'a1\x1fN\x1f\x1f\x1f\x1f\x1f\x1fAnn\x1fsubject\x00',
    );
    final audit = await GitReader(
      git,
      '/repo',
    ).signatureAudit('origin/main', limit: 50);

    expect(audit.checked, 1);
    expect(audit.unverified.single.sha, 'a1');
    expect(git.calls.single, [
      'log',
      '-z',
      '--max-count=51',
      '--format=$kSignatureAuditFormat',
      '--end-of-options',
      'origin/main..HEAD',
    ]);
    // Verification spawns gpg per commit; the 30s default is too short.
    expect(git.timeouts.single, isNotNull);
    expect(git.timeouts.single!.inMinutes, greaterThanOrEqualTo(5));
  });

  test('signatureAudit surfaces a bad base ref as an error', () async {
    final git = _CapturingGit('', "fatal: bad revision 'nope..HEAD'", 128);
    expect(
      GitReader(git, '/repo').signatureAudit('nope'),
      throwsA(isA<GitException>()),
    );
  });

  test('signatureAudit hands its cancel handle to git', () async {
    final git = _CapturingGit();
    final cancel = GitCancel();
    await GitReader(git, '/repo').signatureAudit('main', cancel: cancel);
    expect(git.cancels.single, same(cancel));
  });

  test('disposing the audit provider cancels the running check', () async {
    final git = _CapturingGit();
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    final key = (repo: '/repo', base: 'main');
    final sub = container.listen(signatureAuditProvider(key), (_, _) {});
    await container.read(signatureAuditProvider(key).future);
    expect(git.cancels.single!.isCancelled, isFalse);

    sub.close();
    container.dispose();
    expect(git.cancels.single!.isCancelled, isTrue);
  });
}
