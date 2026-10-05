import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/signature.dart';

const _fp = 'SHA256:2CJk8/KBP2pP8JLrvMz1AB0SBk6IPsTmfkaqQT/X8QI';

void main() {
  group('signatureStateOf', () {
    test('maps every %G? letter git documents', () {
      expect(signatureStateOf('G'), SignatureState.good);
      expect(signatureStateOf('U'), SignatureState.untrusted);
      expect(signatureStateOf('X'), SignatureState.expired);
      expect(signatureStateOf('Y'), SignatureState.expiredKey);
      expect(signatureStateOf('R'), SignatureState.revoked);
      expect(signatureStateOf('B'), SignatureState.bad);
      expect(signatureStateOf('E'), SignatureState.unverifiable);
      expect(signatureStateOf('N'), SignatureState.none);
    });

    test('empty output means unsigned', () {
      expect(signatureStateOf(''), SignatureState.none);
      expect(signatureStateOf(' \n'), SignatureState.none);
    });

    test('an unknown letter is never read as good', () {
      expect(signatureStateOf('Z'), SignatureState.unverifiable);
    });
  });

  group('signatureTone', () {
    test('only a good signature is verified', () {
      for (final s in SignatureState.values) {
        expect(
          signatureTone(s) == SignatureTone.verified,
          s == SignatureState.good,
          reason: '$s',
        );
      }
    });

    test('bad and revoked are danger', () {
      expect(signatureTone(SignatureState.bad), SignatureTone.danger);
      expect(signatureTone(SignatureState.revoked), SignatureTone.danger);
    });

    test('untrusted, expired and unverifiable are caution', () {
      expect(signatureTone(SignatureState.untrusted), SignatureTone.caution);
      expect(signatureTone(SignatureState.expired), SignatureTone.caution);
      expect(signatureTone(SignatureState.expiredKey), SignatureTone.caution);
      expect(signatureTone(SignatureState.unverifiable), SignatureTone.caution);
    });

    test('unsigned is neutral', () {
      expect(signatureTone(SignatureState.none), SignatureTone.neutral);
    });
  });

  group('parseSignatureVerdict', () {
    test('reads every field of the signature format', () {
      final v = parseSignatureVerdict(
        'G\x1ft@x.io\x1fKEYID\x1fFPR\x1fPRIMARY\x1ffully\n',
      );
      expect(v.state, SignatureState.good);
      expect(v.signer, 't@x.io');
      expect(v.key, 'KEYID');
      expect(v.fingerprint, 'FPR');
      expect(v.primaryFingerprint, 'PRIMARY');
      expect(v.trust, 'fully');
      expect(v.isSsh, isFalse);
    });

    test(
      'an SSH signature with no allowed signers is untrusted, no signer',
      () {
        final v = parseSignatureVerdict(
          'U\x1f\x1f$_fp\x1f$_fp\x1f\x1fundefined',
        );
        expect(v.state, SignatureState.untrusted);
        expect(v.signer, isEmpty);
        expect(v.isSsh, isTrue);
      },
    );

    test('drops the placeholder trust git prints for unsigned commits', () {
      final v = parseSignatureVerdict('N\x1f\x1f\x1f\x1f\x1fundefined');
      expect(v.state, SignatureState.none);
      expect(v.trust, isEmpty);
    });

    test('empty output is unsigned', () {
      expect(parseSignatureVerdict('').state, SignatureState.none);
    });

    test('a bare status letter still parses', () {
      expect(parseSignatureVerdict('B').state, SignatureState.bad);
    });

    test('the format asks git for exactly the parsed fields', () {
      expect(kSignatureFormat, '%G?%x1f%GS%x1f%GK%x1f%GF%x1f%GP%x1f%GT');
      expect(kSignatureDetailFormat, '$kSignatureFormat%x1f%GG');
    });

    test('reads the verifier output that follows the fields', () {
      final v = parseSignatureVerdict(
        'U\x1f\x1f$_fp\x1f$_fp\x1f\x1fundefined\x1fGood "git"\nNo principal matched.\n',
      );
      expect(v.state, SignatureState.untrusted);
      expect(v.trust, 'undefined');
      expect(v.detail, 'Good "git"\nNo principal matched.');
    });
  });

  group('missingVerifier', () {
    test('names a program git could not exec by path', () {
      expect(
        missingVerifier(
          "fatal: cannot exec '/nonexistent/ssh-keygen': No such file or directory",
        ),
        '/nonexistent/ssh-keygen',
      );
    });

    test('names a program git could not find on PATH', () {
      expect(
        missingVerifier('error: cannot run gpg: No such file or directory'),
        'gpg',
      );
    });

    test('is null for ordinary output', () {
      expect(missingVerifier(''), isNull);
      expect(missingVerifier('No principal matched.'), isNull);
    });
  });

  group('withVerifierErrors', () {
    test('a missing ssh-keygen turns git\'s B into unverifiable', () {
      final v = withVerifierErrors(
        const SignatureVerdict(state: SignatureState.bad, trust: 'never'),
        'error: cannot run ssh-keygen: No such file or directory\n',
      );
      expect(v.state, SignatureState.unverifiable);
      expect(v.trust, isEmpty);
      expect(v.detail, contains('cannot run ssh-keygen'));
    });

    test('a missing gpg turns git\'s N into unverifiable', () {
      final v = withVerifierErrors(
        SignatureVerdict.unsigned,
        'error: cannot run gpg: No such file or directory\n',
      );
      expect(v.state, SignatureState.unverifiable);
    });

    test('ordinary stderr leaves the verdict alone', () {
      const good = SignatureVerdict(state: SignatureState.good, signer: 'me');
      expect(withVerifierErrors(good, ''), same(good));
      expect(withVerifierErrors(good, 'warning: something'), same(good));
    });
  });

  group('parseTagVerification', () {
    test('SSH good signature with a principal is good', () {
      final v = parseTagVerification(
        'Good "git" signature for t@x.io with ED25519 key $_fp\n',
      );
      expect(v.state, SignatureState.good);
      expect(v.signer, 't@x.io');
      expect(v.key, _fp);
      expect(v.isSsh, isTrue);
    });

    test('SSH good signature without a principal is untrusted', () {
      final v = parseTagVerification(
        'Good "git" signature with ED25519 key $_fp\nNo principal matched.\n',
      );
      expect(v.state, SignatureState.untrusted);
      expect(v.signer, isEmpty);
      expect(v.key, _fp);
    });

    test('SSH failed verification is bad', () {
      final v = parseTagVerification(
        'Could not verify signature.\n'
        'Signature verification failed: incorrect signature\n',
      );
      expect(v.state, SignatureState.bad);
    });

    test('an annotated tag without a signature is unsigned', () {
      expect(
        parseTagVerification('error: no signature found\n').state,
        SignatureState.none,
      );
    });

    test('a lightweight tag is unsigned', () {
      expect(
        parseTagVerification(
          'error: v3: cannot verify a non-tag object of type commit.\n',
        ).state,
        SignatureState.none,
      );
    });

    test('GPG good signature with full trust is good', () {
      final v = parseTagVerification(
        '[GNUPG:] NEWSIG\n'
        '[GNUPG:] GOODSIG 0123456789ABCDEF Jane <j@x.io>\n'
        '[GNUPG:] VALIDSIG FPR0 2026-10-05 1 0 4 0 22 10 00 PRIMARY0\n'
        '[GNUPG:] TRUST_FULLY 0 pgp\n',
      );
      expect(v.state, SignatureState.good);
      expect(v.signer, 'Jane <j@x.io>');
      expect(v.key, '0123456789ABCDEF');
      expect(v.fingerprint, 'FPR0');
      expect(v.primaryFingerprint, 'PRIMARY0');
      expect(v.trust, 'fully');
      expect(v.isSsh, isFalse);
    });

    test('GPG good signature from an untrusted key is untrusted', () {
      final v = parseTagVerification(
        '[GNUPG:] GOODSIG 0123456789ABCDEF Jane <j@x.io>\n'
        '[GNUPG:] TRUST_UNDEFINED 0 pgp\n',
      );
      expect(v.state, SignatureState.untrusted);
      expect(v.trust, 'undefined');
    });

    test('GPG good signature without any trust line is untrusted', () {
      expect(
        parseTagVerification('[GNUPG:] GOODSIG ABC Jane\n').state,
        SignatureState.untrusted,
      );
    });

    test('GPG states map like %G?', () {
      expect(
        parseTagVerification('[GNUPG:] BADSIG ABC Jane\n').state,
        SignatureState.bad,
      );
      expect(
        parseTagVerification('[GNUPG:] EXPSIG ABC Jane\n').state,
        SignatureState.expired,
      );
      expect(
        parseTagVerification('[GNUPG:] EXPKEYSIG ABC Jane\n').state,
        SignatureState.expiredKey,
      );
      expect(
        parseTagVerification('[GNUPG:] REVKEYSIG ABC Jane\n').state,
        SignatureState.revoked,
      );
      expect(
        parseTagVerification('[GNUPG:] ERRSIG ABC 22 10 00 1 9\n').state,
        SignatureState.unverifiable,
      );
    });

    test('two signature verdicts in one output cannot be verified', () {
      // git rejects more than one GOODSIG/BADSIG/... line the same way.
      final v = parseTagVerification(
        '[GNUPG:] GOODSIG ABC Jane\n'
        '[GNUPG:] TRUST_ULTIMATE 0 pgp\n'
        '[GNUPG:] BADSIG DEF Mallory\n',
      );
      expect(v.state, SignatureState.unverifiable);
      expect(v.signer, isEmpty);
    });

    test('GPG marginal trust is enough for good, as in git', () {
      expect(
        parseTagVerification(
          '[GNUPG:] GOODSIG ABC Jane\n[GNUPG:] TRUST_MARGINAL 0 pgp\n',
        ).state,
        SignatureState.good,
      );
      expect(
        parseTagVerification(
          '[GNUPG:] GOODSIG ABC Jane\n[GNUPG:] TRUST_NEVER 0 pgp\n',
        ).state,
        SignatureState.untrusted,
      );
    });

    test('an SSH principal containing " with " is read whole', () {
      final v = parseTagVerification(
        'Good "git" signature for team with ops with ED25519 key $_fp\n',
      );
      expect(v.state, SignatureState.good);
      expect(v.signer, 'team with ops');
      expect(v.key, _fp);
    });

    test('a missing verifier program is unverifiable, never bad', () {
      final v = parseTagVerification(
        "fatal: cannot exec '/opt/x/ssh-keygen': No such file or directory\n",
      );
      expect(v.state, SignatureState.unverifiable);
      expect(v.detail, contains('cannot exec'));
    });

    test('keeps the raw output for explaining the verdict', () {
      const raw =
          'Good "git" signature with ED25519 key $_fp\nNo principal matched.\n';
      expect(parseTagVerification(raw).detail, raw);
    });

    test('output it cannot read is unverifiable, not good', () {
      expect(
        parseTagVerification('gpg: something odd\n').state,
        SignatureState.unverifiable,
      );
    });
  });

  group('signatureHint', () {
    const sshUntrusted = SignatureVerdict(
      state: SignatureState.untrusted,
      key: _fp,
      fingerprint: _fp,
    );

    test('SSH untrusted with no allowed signers file asks for one', () {
      expect(
        signatureHint(sshUntrusted, allowedSignersFile: null),
        SignatureHint.sshNoAllowedSigners,
      );
    });

    test('SSH untrusted with a file means the key is not listed', () {
      expect(
        signatureHint(sshUntrusted, allowedSignersFile: '~/.ssh/allowed'),
        SignatureHint.sshKeyNotAllowed,
      );
    });

    test('unverifiable means the public key is missing', () {
      expect(
        signatureHint(
          const SignatureVerdict(state: SignatureState.unverifiable),
          allowedSignersFile: null,
        ),
        SignatureHint.missingKey,
      );
    });

    test('a good signature needs no hint', () {
      expect(
        signatureHint(
          const SignatureVerdict(state: SignatureState.good, key: _fp),
          allowedSignersFile: null,
        ),
        SignatureHint.none,
      );
    });

    test('GPG untrusted is not an allowed-signers problem', () {
      expect(
        signatureHint(
          const SignatureVerdict(state: SignatureState.untrusted, key: 'ABC'),
          allowedSignersFile: null,
        ),
        SignatureHint.none,
      );
    });
  });

  group('signatureHint from verifier output', () {
    test('a missing verifier program says so', () {
      expect(
        signatureHint(
          const SignatureVerdict(
            state: SignatureState.unverifiable,
            detail: 'error: cannot run gpg: No such file or directory',
          ),
          allowedSignersFile: null,
        ),
        SignatureHint.verifierMissing,
      );
    });

    test('an allowed signers file that cannot be opened says so', () {
      const v = SignatureVerdict(
        state: SignatureState.untrusted,
        key: _fp,
        detail:
            'Good "git" signature with ED25519 key $_fp\n'
            'Unable to open allowed keys file "/gone/allowed": No such file or directory\n'
            'No principal matched.',
      );
      expect(
        signatureHint(v, allowedSignersFile: '/gone/allowed'),
        SignatureHint.sshAllowedSignersUnreadable,
      );
      expect(allowedSignersPathIn(v.detail), '/gone/allowed');
    });

    test('an empty file name in the error means none is configured', () {
      const v = SignatureVerdict(
        state: SignatureState.untrusted,
        key: _fp,
        detail:
            'Unable to open allowed keys file "": No such file or directory',
      );
      expect(
        signatureHint(v, allowedSignersFile: null),
        SignatureHint.sshNoAllowedSigners,
      );
    });
  });

  group('parseSignatureAudit', () {
    String rec(String sha, String sig, String author, String subject) =>
        '$sha\x1f$sig\x1f$author\x1f$subject';

    test('keeps every commit that is not verified, in log order', () {
      final out = [
        rec('a1', 'N\x1f\x1f\x1f\x1f\x1fundefined', 'Ann', 'unsigned one'),
        rec('b2', 'G\x1fme\x1fK\x1fF\x1fP\x1ffully', 'Bob', 'good one'),
        rec('c3', 'B\x1f\x1fK\x1f\x1f\x1fnever', 'Cy', 'bad one'),
      ].join('\x00');
      final audit = parseSignatureAudit(out, limit: 10);
      expect(audit.checked, 3);
      expect(audit.truncated, isFalse);
      expect(audit.unverified.map((c) => c.sha), ['a1', 'c3']);
      expect(audit.unverified.first.subject, 'unsigned one');
      expect(audit.unverified.first.author, 'Ann');
      expect(audit.unverified.last.verdict.state, SignatureState.bad);
    });

    test('a subject containing the separator survives', () {
      final out = rec('a1', 'N\x1f\x1f\x1f\x1f\x1f', 'Ann', 'x\x1fy');
      expect(
        parseSignatureAudit(out, limit: 10).unverified.single.subject,
        'x\x1fy',
      );
    });

    test('one record past the limit marks the audit truncated', () {
      final out = [
        for (var i = 0; i < 3; i++)
          rec('s$i', 'N\x1f\x1f\x1f\x1f\x1f', 'A', 'm$i'),
      ].join('\x00');
      final audit = parseSignatureAudit(out, limit: 2);
      expect(audit.checked, 2);
      expect(audit.truncated, isTrue);
      expect(audit.unverified.map((c) => c.sha), ['s0', 's1']);
    });

    test('empty output is an empty audit', () {
      final audit = parseSignatureAudit('', limit: 10);
      expect(audit.checked, 0);
      expect(audit.unverified, isEmpty);
    });

    test('tolerates a trailing separator and newline', () {
      final out = '${rec('a1', 'N\x1f\x1f\x1f\x1f\x1f', 'A', 'm')}\x00\n';
      expect(parseSignatureAudit(out, limit: 10).checked, 1);
    });
  });

  group('parseSignatureAudit edge records', () {
    test('a malformed record is not counted as checked', () {
      final out = [
        'a1\x1fN\x1f\x1f\x1f\x1f\x1f\x1fAnn\x1fs',
        'garbage-without-fields',
      ].join('\x00');
      final audit = parseSignatureAudit(out, limit: 10);
      expect(audit.checked, 1);
      expect(audit.unverified.single.sha, 'a1');
    });

    test('a leading newline on any record is dropped', () {
      final out = [
        '\na1\x1fN\x1f\x1f\x1f\x1f\x1f\x1fA\x1fs',
        '\nb2\x1fN\x1f\x1f\x1f\x1f\x1f\x1fB\x1ft',
      ].join('\x00');
      expect(parseSignatureAudit(out, limit: 10).unverified.map((c) => c.sha), [
        'a1',
        'b2',
      ]);
    });
  });

  group('SSH verification with no allowed signers configured', () {
    // git's default: it refuses to verify an SSH signature at all, prints
    // `N` as if the commit were unsigned, and says why only on stderr.
    const unconfigured =
        'error: gpg.ssh.allowedSignersFile needs to be configured and exist for ssh signature verification\n';

    test('is recognised in stderr', () {
      expect(sshSignersUnconfigured(unconfigured), isTrue);
      expect(sshSignersUnconfigured(''), isFalse);
      expect(
        sshSignersUnconfigured('Unable to open allowed keys file "/x"'),
        isFalse,
      );
    });

    test('turns git\'s N into unverifiable, never unsigned', () {
      final v = withVerifierErrors(SignatureVerdict.unsigned, unconfigured);
      expect(v.state, SignatureState.unverifiable);
      expect(v.detail, contains('allowedSignersFile'));
    });

    test('a tag reads unverifiable', () {
      expect(
        parseTagVerification(unconfigured).state,
        SignatureState.unverifiable,
      );
    });

    test('the hint asks for an allowed signers file', () {
      expect(
        signatureHint(
          withVerifierErrors(SignatureVerdict.unsigned, unconfigured),
          allowedSignersFile: null,
        ),
        SignatureHint.sshNoAllowedSigners,
      );
      expect(
        signatureHint(
          parseTagVerification(unconfigured),
          allowedSignersFile: null,
        ),
        SignatureHint.sshNoAllowedSigners,
      );
    });
  });
}
