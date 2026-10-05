import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
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
      '--format=$kSignatureDetailFormat',
      '--end-of-options',
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

  test('closing the audit while git runs cancels that run', () async {
    final git = _HangingGit();
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    final key = (repo: '/repo', base: 'main');
    final sub = container.listen(signatureAuditProvider(key), (_, _) {});
    // Let the provider start git; the run is still in flight.
    await Future<void>.delayed(Duration.zero);
    expect(git.started, isTrue);
    expect(git.cancel!.isCancelled, isFalse);

    sub.close();
    container.dispose();
    expect(git.cancel!.isCancelled, isTrue);
    await expectLater(git.result, throwsA(isA<GitCancelledException>()));
  });

  test('signatureVerdict does not trust git\'s letter when the verifier '
      'could not start', () async {
    final git = _CapturingGit(
      'B\x1f\x1f\x1f\x1f\x1fnever\x1f',
      'error: cannot run ssh-keygen: No such file or directory',
    );
    final v = await GitReader(git, '/repo').signatureVerdict('abc123');
    expect(v.state, SignatureState.unverifiable);
    expect(missingVerifier(v.detail), 'ssh-keygen');
  });

  test('signatureAudit fails rather than list wrong verdicts when the '
      'verifier could not start', () async {
    final git = _CapturingGit(
      'a1\x1fB\x1f\x1f\x1f\x1f\x1fnever\x1fAnn\x1fs\x00',
      'error: cannot run ssh-keygen: No such file or directory',
    );
    await expectLater(
      GitReader(git, '/repo').signatureAudit('main'),
      throwsA(
        isA<GitException>().having(
          (e) => e.result?.err,
          'stderr',
          contains('cannot run ssh-keygen'),
        ),
      ),
    );
  });

  test('commit reads one commit in full, refs and body included', () async {
    final git = _CapturingGit(
      'abc123\x1fp1\x1fAnn\x1fa@x.io\x1f2026-10-05T12:00:00+01:00\x1f'
      'HEAD -> refs/heads/main, tag: refs/tags/v1\x1fsubject\x1fbody\n\x00',
    );
    final c = await GitReader(git, '/repo').commit('abc123');
    expect(c, isNotNull);
    expect(c!.sha, 'abc123');
    expect(c.message, 'subject');
    expect(c.body, 'body');
    expect(c.parents, ['p1']);
    expect(c.refs.where((r) => r.kind == RefKind.tag).map((r) => r.name), [
      'v1',
    ]);
    expect(git.calls.single.first, 'log');
    expect(git.calls.single, containsAll(['-1', '--decorate=full', 'abc123']));
  });

  test('commit is null for a sha git does not know', () async {
    final git = _CapturingGit('', 'fatal: bad object nope', 128);
    expect(await GitReader(git, '/repo').commit('nope'), isNull);
  });
}

/// A git that never finishes on its own: it waits until its cancel handle
/// fires and then fails the way [SystemGitService] does.
class _HangingGit implements GitService {
  GitCancel? cancel;
  bool started = false;
  late Future<GitResult> result;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) {
    this.cancel = cancel;
    started = true;
    return result = () async {
      while (!cancel!.isCancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      throw GitCancelledException('cancelled');
    }();
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}
