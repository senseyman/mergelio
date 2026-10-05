/// Commit and tag signature verification: git's `%G?` verdicts, the signer
/// fields that go with them, and `git verify-tag --raw` output, parsed into
/// one shape so every surface states a signature the same way.
library;

/// What verifying a signature concluded, one per `%G?` letter.
enum SignatureState {
  /// `G`: valid signature from a trusted key.
  good,

  /// `U`: valid signature, but the key's validity is unknown or untrusted.
  /// For SSH this is also what an unlisted key (or no allowed signers file)
  /// produces.
  untrusted,

  /// `X`: valid signature that has expired.
  expired,

  /// `Y`: valid signature made by a key that has since expired.
  expiredKey,

  /// `R`: valid signature made by a revoked key.
  revoked,

  /// `B`: the signature does not match the content.
  bad,

  /// `E`: cannot be checked, typically because the public key is missing.
  unverifiable,

  /// `N`: no signature at all.
  none,
}

/// How a state reads at a glance. Only [verified] may look like success; a
/// bad or revoked signature is [danger] so it can never be styled like a good
/// one.
enum SignatureTone { verified, caution, danger, neutral }

/// Why a signature fell short of verified, when the cause is local setup the
/// user can fix rather than the signature itself.
enum SignatureHint {
  none,

  /// SSH signature, and `gpg.ssh.allowedSignersFile` is not configured, so
  /// git has nothing to match the key against.
  sshNoAllowedSigners,

  /// SSH signature whose key is not listed in the allowed signers file.
  sshKeyNotAllowed,

  /// The configured allowed signers file could not be opened.
  sshAllowedSignersUnreadable,

  /// The public key is not available locally.
  missingKey,

  /// git could not start gpg or ssh-keygen at all. git then reports an SSH
  /// signature as bad and a GPG one as absent, so the verdict is replaced.
  verifierMissing,
}

/// The pretty format that fills a [SignatureVerdict]: status, signer, key,
/// fingerprint, primary-key fingerprint and trust level, unit-separated.
const kSignatureFormat = '%G?%x1f%GS%x1f%GK%x1f%GF%x1f%GP%x1f%GT';

/// [kSignatureFormat] plus the verifier's own output (`%GG`), which is what
/// explains an untrusted or uncheckable verdict. Last, as it spans lines.
const kSignatureDetailFormat = '$kSignatureFormat%x1f%GG';

/// Number of fields [kSignatureFormat] produces.
const _verdictFields = 6;

/// One verified (or not) signature and who it names.
class SignatureVerdict {
  final SignatureState state;

  /// The signer: a GPG user id, or the SSH principal from the allowed signers
  /// file. Empty when git could not attribute the signature.
  final String signer;

  /// GPG key id, or the SSH key fingerprint.
  final String key;
  final String fingerprint;
  final String primaryFingerprint;

  /// GPG trust level (`ultimate`, `fully`, `marginal`, `never`, `undefined`),
  /// empty when git reported none.
  final String trust;

  /// What gpg or ssh-keygen printed, empty when not asked for.
  final String detail;

  const SignatureVerdict({
    required this.state,
    this.signer = '',
    this.key = '',
    this.fingerprint = '',
    this.primaryFingerprint = '',
    this.trust = '',
    this.detail = '',
  });

  static const unsigned = SignatureVerdict(state: SignatureState.none);

  /// Whether this is an SSH signature. git reports SSH keys by their
  /// `SHA256:` fingerprint; GPG keys are hex ids.
  bool get isSsh =>
      key.startsWith('SHA256:') || fingerprint.startsWith('SHA256:');

  bool get isSigned => state != SignatureState.none;
}

SignatureState signatureStateOf(String code) => switch (code.trim()) {
  '' || 'N' => SignatureState.none,
  'G' => SignatureState.good,
  'U' => SignatureState.untrusted,
  'X' => SignatureState.expired,
  'Y' => SignatureState.expiredKey,
  'R' => SignatureState.revoked,
  'B' => SignatureState.bad,
  // 'E' and anything a future git invents: never assume it checked out.
  _ => SignatureState.unverifiable,
};

SignatureTone signatureTone(SignatureState state) => switch (state) {
  SignatureState.good => SignatureTone.verified,
  SignatureState.bad || SignatureState.revoked => SignatureTone.danger,
  SignatureState.none => SignatureTone.neutral,
  _ => SignatureTone.caution,
};

/// Parses one [kSignatureFormat] or [kSignatureDetailFormat] record. A bare
/// status letter (the older `%G?`-only format) parses too.
SignatureVerdict parseSignatureVerdict(String record) {
  final f = record.trimRight().split('\x1f');
  String at(int i) => i < f.length ? f[i].trim() : '';
  final state = signatureStateOf(at(0));
  return SignatureVerdict(
    state: state,
    signer: at(1),
    key: at(2),
    fingerprint: at(3),
    primaryFingerprint: at(4),
    // git prints "undefined" trust even for an unsigned commit; it says
    // nothing there.
    trust: state == SignatureState.none ? '' : at(5),
    detail: f.length > _verdictFields
        ? f.sublist(_verdictFields).join('\x1f').trim()
        : '',
  );
}

final _missingVerifier = RegExp(r"cannot (?:exec '([^']+)'|run ([^:\n]+):)");

/// The gpg or ssh-keygen program git failed to start, named in its [stderr],
/// or null when it started.
String? missingVerifier(String stderr) {
  final m = _missingVerifier.firstMatch(stderr);
  return m == null ? null : (m.group(1) ?? m.group(2))!.trim();
}

/// Whether git refused to verify an SSH signature because
/// `gpg.ssh.allowedSignersFile` is not configured. That is git's default, and
/// git then prints `N` as if the commit carried no signature at all.
bool sshSignersUnconfigured(String stderr) =>
    stderr.contains('gpg.ssh.allowedSignersFile needs to be configured');

/// Whether git's [stderr] says its `%G?` letter is not a verdict on the
/// signature: the verifier could not start, or SSH verification was refused.
bool verifierFailed(String stderr) =>
    missingVerifier(stderr) != null || sshSignersUnconfigured(stderr);

/// [verdict] corrected by git's [stderr]. When verification never ran git
/// still prints a letter — `B` for a missing ssh-keygen, `N` for a missing
/// gpg or an SSH signature with no allowed signers file — that says nothing
/// about the signature itself.
SignatureVerdict withVerifierErrors(SignatureVerdict verdict, String stderr) {
  if (!verifierFailed(stderr)) return verdict;
  return SignatureVerdict(
    state: SignatureState.unverifiable,
    detail: stderr.trim(),
  );
}

final _unreadableSigners = RegExp(
  r'Unable to open allowed keys file "([^"]*)"',
);

/// The allowed signers path ssh-keygen failed to open, named in [detail];
/// empty when none was configured, null when there was no such failure.
String? allowedSignersPathIn(String detail) =>
    _unreadableSigners.firstMatch(detail)?.group(1);

final _sshGood = RegExp(
  r'^Good "git" signature(?: for (.+))? with \S+ key (\S+)',
  multiLine: true,
);

/// Parses the stderr of `git verify-tag --raw`: GPG status lines, or the
/// ssh-keygen text git passes through for an SSH-signed tag. Output that
/// matches neither is [SignatureState.unverifiable], never good.
SignatureVerdict parseTagVerification(String stderr) {
  final v = _parseTagVerification(stderr);
  return SignatureVerdict(
    state: v.state,
    signer: v.signer,
    key: v.key,
    fingerprint: v.fingerprint,
    primaryFingerprint: v.primaryFingerprint,
    trust: v.trust,
    detail: stderr,
  );
}

SignatureVerdict _parseTagVerification(String stderr) {
  if (verifierFailed(stderr)) {
    return const SignatureVerdict(state: SignatureState.unverifiable);
  }
  if (stderr.contains('[GNUPG:]')) return _parseGpgStatus(stderr);

  // Failure wording is checked first: ssh-keygen can print a "Good" line for
  // the key and still reject the signature against its principal.
  if (stderr.contains('Signature verification failed')) {
    return const SignatureVerdict(state: SignatureState.bad);
  }
  final good = _sshGood.firstMatch(stderr);
  if (good != null) {
    final principal = good.group(1) ?? '';
    return SignatureVerdict(
      state: principal.isEmpty ? SignatureState.untrusted : SignatureState.good,
      signer: principal,
      key: good.group(2)!,
      fingerprint: good.group(2)!,
    );
  }
  if (stderr.contains('no signature found') ||
      stderr.contains('cannot verify a non-tag object')) {
    return SignatureVerdict.unsigned;
  }
  return const SignatureVerdict(state: SignatureState.unverifiable);
}

/// GPG `--status-fd` lines, mapped the way git maps them for `%G?`.
SignatureVerdict _parseGpgStatus(String raw) {
  const verdicts = {
    'GOODSIG': SignatureState.good,
    'BADSIG': SignatureState.bad,
    'ERRSIG': SignatureState.unverifiable,
    'EXPSIG': SignatureState.expired,
    'EXPKEYSIG': SignatureState.expiredKey,
    'REVKEYSIG': SignatureState.revoked,
  };
  List<String>? verdict;
  List<String>? valid;
  var trust = '';
  for (final l in raw.split('\n')) {
    if (!l.startsWith('[GNUPG:] ')) continue;
    final parts = l.substring(9).trim().split(' ');
    if (verdicts.containsKey(parts.first)) {
      // More than one verdict means more than one signature. git refuses to
      // pick one, and so does this.
      if (verdict != null) {
        return const SignatureVerdict(state: SignatureState.unverifiable);
      }
      verdict = parts;
    } else if (parts.first == 'VALIDSIG') {
      valid = parts;
    } else if (parts.first.startsWith('TRUST_')) {
      trust = parts.first.substring(6).toLowerCase();
    }
  }
  if (verdict == null) {
    return const SignatureVerdict(state: SignatureState.unverifiable);
  }
  final state = verdicts[verdict.first]!;
  return SignatureVerdict(
    // git reads a good signature from a key trusted less than marginally (or
    // with no trust line at all) as untrusted.
    state:
        state == SignatureState.good &&
            !const {'marginal', 'fully', 'ultimate'}.contains(trust)
        ? SignatureState.untrusted
        : state,
    key: verdict.length > 1 ? verdict[1] : '',
    // ERRSIG carries algorithm codes, not a user id, after the key.
    signer: state == SignatureState.unverifiable || verdict.length < 3
        ? ''
        : verdict.sublist(2).join(' '),
    fingerprint: valid != null && valid.length > 1 ? valid[1] : '',
    primaryFingerprint: valid != null && valid.length > 10 ? valid[10] : '',
    trust: trust,
  );
}

/// The local-setup reason behind [verdict], given the repository's
/// configured `gpg.ssh.allowedSignersFile` (null when unset).
SignatureHint signatureHint(
  SignatureVerdict verdict, {
  required String? allowedSignersFile,
}) {
  if (missingVerifier(verdict.detail) != null) {
    return SignatureHint.verifierMissing;
  }
  if (sshSignersUnconfigured(verdict.detail)) {
    return SignatureHint.sshNoAllowedSigners;
  }
  if (verdict.state == SignatureState.unverifiable) {
    return SignatureHint.missingKey;
  }
  if (verdict.state == SignatureState.untrusted &&
      verdict.isSsh &&
      verdict.signer.isEmpty) {
    // ssh-keygen's own complaint is more exact than the config: it names the
    // file it tried, empty when none is set.
    final tried = allowedSignersPathIn(verdict.detail);
    if (tried != null) {
      return tried.isEmpty
          ? SignatureHint.sshNoAllowedSigners
          : SignatureHint.sshAllowedSignersUnreadable;
    }
    return allowedSignersFile == null || allowedSignersFile.isEmpty
        ? SignatureHint.sshNoAllowedSigners
        : SignatureHint.sshKeyNotAllowed;
  }
  return SignatureHint.none;
}

/// A commit in an audited range whose signature is not [SignatureState.good].
class UnverifiedCommit {
  final String sha;
  final String author;
  final String subject;
  final SignatureVerdict verdict;
  const UnverifiedCommit({
    required this.sha,
    required this.author,
    required this.subject,
    required this.verdict,
  });

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;
}

/// Result of checking every commit in a range.
class SignatureAudit {
  /// Commits whose signature was checked.
  final int checked;

  /// True when the range holds more commits than were checked.
  final bool truncated;
  final List<UnverifiedCommit> unverified;
  const SignatureAudit({
    required this.checked,
    required this.truncated,
    required this.unverified,
  });
}

/// The pretty format one audit record is read from (records NUL-separated
/// with `-z`).
const kSignatureAuditFormat = '%H%x1f$kSignatureFormat%x1f%an%x1f%s';

/// Parses a `git log -z --format=`[kSignatureAuditFormat] run that asked for
/// one record more than [limit], so an extra record marks [truncated].
SignatureAudit parseSignatureAudit(String out, {required int limit}) {
  final records = [
    for (final r in out.split('\x00'))
      if (r.trim().isNotEmpty) r.trimLeft(),
  ];
  final kept = records.take(limit).toList();
  final unverified = <UnverifiedCommit>[];
  var checked = 0;
  for (final r in kept) {
    final f = r.split('\x1f');
    // A record without every field was not checked as far as anyone can tell.
    if (f.length < _verdictFields + 3) continue;
    checked++;
    final verdict = parseSignatureVerdict(
      f.sublist(1, 1 + _verdictFields).join('\x1f'),
    );
    if (verdict.state == SignatureState.good) continue;
    unverified.add(
      UnverifiedCommit(
        sha: f[0],
        verdict: verdict,
        author: f[1 + _verdictFields],
        // A subject may itself contain the separator; it is the last field.
        subject: f.sublist(2 + _verdictFields).join('\x1f').trimRight(),
      ),
    );
  }
  return SignatureAudit(
    checked: checked,
    truncated: records.length > limit,
    unverified: unverified,
  );
}
