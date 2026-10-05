import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/signature.dart';
import '../../l10n/gen/app_localizations.dart';

/// Text naming [state]. Every state reads differently, so the verdict never
/// depends on telling colours apart.
String signatureLabel(AppLocalizations l, SignatureState state) =>
    switch (state) {
      SignatureState.good => l.sigGood,
      SignatureState.untrusted => l.sigUntrusted,
      SignatureState.expired => l.sigExpired,
      SignatureState.expiredKey => l.sigExpiredKey,
      SignatureState.revoked => l.sigRevoked,
      SignatureState.bad => l.sigBad,
      SignatureState.unverifiable => l.sigUnverifiable,
      SignatureState.none => l.sigNone,
    };

IconData signatureIcon(SignatureState state) => switch (state) {
  SignatureState.good => Icons.verified_user_outlined,
  SignatureState.untrusted => Icons.gpp_maybe_outlined,
  SignatureState.expired || SignatureState.expiredKey => Icons.history_outlined,
  SignatureState.unverifiable => Icons.help_outline,
  SignatureState.bad || SignatureState.revoked => Icons.gpp_bad_outlined,
  SignatureState.none => Icons.lock_open_outlined,
};

Color signatureColor(AppTokens t, SignatureState state) =>
    switch (signatureTone(state)) {
      SignatureTone.verified => t.success,
      SignatureTone.caution => t.warning,
      SignatureTone.danger => t.danger,
      SignatureTone.neutral => t.textMuted,
    };

/// A signature verdict as icon and text. Tapping a signed one reveals who
/// signed it, with which key, and — when the cause is local setup — why it
/// stops short of verified.
class SignatureBadge extends StatefulWidget {
  final SignatureVerdict verdict;

  /// The repository's `gpg.ssh.allowedSignersFile`, null when unset. Only
  /// read to explain an SSH signature git could not attribute.
  final String? allowedSignersFile;

  /// Whether tapping reveals the details. Off where the badge only labels a
  /// row and the details belong to another view.
  final bool details;

  const SignatureBadge({
    super.key,
    required this.verdict,
    this.allowedSignersFile,
    this.details = true,
  });

  @override
  State<SignatureBadge> createState() => _SignatureBadgeState();
}

class _SignatureBadgeState extends State<SignatureBadge> {
  bool _open = false;

  @override
  void didUpdateWidget(SignatureBadge old) {
    super.didUpdateWidget(old);
    // The same slot now shows another commit's or tag's signature; details
    // opened for the previous one say nothing about this one.
    if (!_sameSignature(old.verdict, widget.verdict)) _open = false;
  }

  static bool _sameSignature(SignatureVerdict a, SignatureVerdict b) =>
      a.state == b.state &&
      a.signer == b.signer &&
      a.key == b.key &&
      a.fingerprint == b.fingerprint &&
      a.detail == b.detail;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final v = widget.verdict;
    final color = signatureColor(t, v.state);
    final expandable = widget.details && v.isSigned;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(signatureIcon(v.state), size: 13, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            signatureLabel(l, v.state),
            style: TextStyle(color: color, fontSize: 12),
          ),
        ),
        if (expandable) ...[
          const SizedBox(width: 2),
          Icon(
            _open ? Icons.expand_less : Icons.expand_more,
            size: 13,
            color: t.textFaint,
          ),
        ],
      ],
    );
    if (!expandable) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: _open ? l.sigHideDetails : l.sigShowDetails,
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _open = !_open),
            child: row,
          ),
        ),
        if (_open)
          _Details(verdict: v, allowedSignersFile: widget.allowedSignersFile),
      ],
    );
  }
}

class _Details extends StatelessWidget {
  final SignatureVerdict verdict;
  final String? allowedSignersFile;
  const _Details({required this.verdict, required this.allowedSignersFile});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final v = verdict;
    final hint = switch (signatureHint(
      v,
      allowedSignersFile: allowedSignersFile,
    )) {
      SignatureHint.none => null,
      // Refused outright (git's default) checks nothing; an empty setting
      // still checks the key, just cannot name its owner.
      SignatureHint.sshNoAllowedSigners =>
        sshSignersUnconfigured(v.detail)
            ? l.sigHintSshUnconfigured
            : l.sigHintNoAllowedSigners,
      SignatureHint.sshKeyNotAllowed => l.sigHintKeyNotAllowed(
        allowedSignersFile ?? '',
      ),
      SignatureHint.sshAllowedSignersUnreadable => l.sigHintSignersUnreadable(
        allowedSignersPathIn(v.detail) ?? allowedSignersFile ?? '',
      ),
      SignatureHint.missingKey => l.sigHintMissingKey,
      SignatureHint.verifierMissing => l.sigHintVerifierMissing(
        missingVerifier(v.detail) ?? '',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 19, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            label: l.sigSigner,
            value: v.signer.isEmpty ? l.sigUnknownSigner : v.signer,
          ),
          if (v.key.isNotEmpty)
            _Field(label: l.sigKey, value: v.key, mono: true),
          if (v.fingerprint.isNotEmpty && v.fingerprint != v.key)
            _Field(label: l.sigFingerprint, value: v.fingerprint, mono: true),
          if (v.primaryFingerprint.isNotEmpty &&
              v.primaryFingerprint != v.fingerprint)
            _Field(
              label: l.sigPrimaryKey,
              value: v.primaryFingerprint,
              mono: true,
            ),
          if (v.trust.isNotEmpty) _Field(label: l.sigTrust, value: v.trust),
          // The signing tool's name, not prose; left untranslated.
          if (v.key.isNotEmpty || v.fingerprint.isNotEmpty)
            _Field(label: l.sigFormat, value: v.isSsh ? 'SSH' : 'OpenPGP'),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint,
                style: TextStyle(color: t.textMuted, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _Field({required this.label, required this.value, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(color: t.textFaint, fontSize: 11.5),
            ),
          ),
          // Selectable: keys and fingerprints are what gets pasted into a
          // bug report or an allowed signers line.
          Expanded(
            child: SelectableText(
              value,
              style: mono
                  ? AppFonts.mns(size: 11.5, color: t.textMuted)
                  : TextStyle(color: t.textMuted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
