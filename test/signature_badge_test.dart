import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/signature.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/common/signature_badge.dart';

const _fp = 'SHA256:2CJk8/KBP2pP8JLrvMz1AB0SBk6IPsTmfkaqQT/X8QI';

void main() {
  final tokens = AppTokens.dark();

  Future<void> pump(
    WidgetTester tester,
    SignatureVerdict verdict, {
    String? allowedSignersFile,
    bool details = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [tokens]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SignatureBadge(
            verdict: verdict,
            allowedSignersFile: allowedSignersFile,
            details: details,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Color labelColor(WidgetTester tester, String label) =>
      tester.widget<Text>(find.text(label)).style!.color!;

  const labels = {
    SignatureState.good: 'Verified signature',
    SignatureState.untrusted: 'Valid, untrusted key',
    SignatureState.expired: 'Expired signature',
    SignatureState.expiredKey: 'Expired key',
    SignatureState.revoked: 'Revoked key',
    SignatureState.bad: 'Bad signature',
    SignatureState.unverifiable: 'Cannot verify signature',
    SignatureState.none: 'Not signed',
  };

  for (final MapEntry(key: state, value: label) in labels.entries) {
    testWidgets('$state reads "$label"', (tester) async {
      await pump(tester, SignatureVerdict(state: state));
      expect(find.text(label), findsOneWidget);
      if (state != SignatureState.good) {
        expect(find.textContaining('Verified'), findsNothing);
      }
    });
  }

  testWidgets('every state has its own label', (tester) async {
    expect(labels.values.toSet().length, SignatureState.values.length);
  });

  testWidgets('bad and revoked never share the good colour or icon', (
    tester,
  ) async {
    await pump(tester, const SignatureVerdict(state: SignatureState.good));
    final goodColor = labelColor(tester, 'Verified signature');
    final goodIcon = tester.widget<Icon>(find.byType(Icon).first).icon;
    expect(goodColor, tokens.success);

    for (final (state, label) in [
      (SignatureState.bad, 'Bad signature'),
      (SignatureState.revoked, 'Revoked key'),
    ]) {
      await pump(tester, SignatureVerdict(state: state));
      expect(labelColor(tester, label), tokens.danger);
      expect(
        tester.widget<Icon>(find.byType(Icon).first).icon,
        isNot(goodIcon),
      );
    }
  });

  testWidgets('only a good signature uses the success colour', (tester) async {
    for (final MapEntry(key: state, value: label) in labels.entries) {
      if (state == SignatureState.good) continue;
      await pump(tester, SignatureVerdict(state: state));
      expect(
        labelColor(tester, label),
        isNot(tokens.success),
        reason: '$state',
      );
    }
  });

  testWidgets('tapping the badge reveals signer and key details', (
    tester,
  ) async {
    await pump(
      tester,
      const SignatureVerdict(
        state: SignatureState.good,
        signer: 'Jane <j@x.io>',
        key: '0123456789ABCDEF',
        fingerprint: 'FPR0',
        primaryFingerprint: 'PRIMARY0',
        trust: 'fully',
      ),
    );
    expect(find.text('Jane <j@x.io>'), findsNothing);

    await tester.tap(find.text('Verified signature'));
    await tester.pump();

    expect(find.text('Jane <j@x.io>'), findsOneWidget);
    expect(find.text('0123456789ABCDEF'), findsOneWidget);
    expect(find.text('FPR0'), findsOneWidget);
    expect(find.text('PRIMARY0'), findsOneWidget);
    expect(find.text('fully'), findsOneWidget);
    expect(find.text('OpenPGP'), findsOneWidget);

    await tester.tap(find.text('Verified signature'));
    await tester.pump();
    expect(find.text('Jane <j@x.io>'), findsNothing);
  });

  testWidgets('SSH key shown once when fingerprint equals key', (tester) async {
    await pump(
      tester,
      const SignatureVerdict(
        state: SignatureState.good,
        signer: 't@x.io',
        key: _fp,
        fingerprint: _fp,
      ),
    );
    await tester.tap(find.text('Verified signature'));
    await tester.pump();
    expect(find.text(_fp), findsOneWidget);
    expect(find.text('SSH'), findsOneWidget);
  });

  testWidgets('SSH untrusted without allowed signers explains why', (
    tester,
  ) async {
    await pump(
      tester,
      const SignatureVerdict(
        state: SignatureState.untrusted,
        key: _fp,
        fingerprint: _fp,
      ),
    );
    await tester.tap(find.text('Valid, untrusted key'));
    await tester.pump();
    expect(find.text('Unknown signer'), findsOneWidget);
    expect(find.textContaining('gpg.ssh.allowedSignersFile'), findsOneWidget);
  });

  testWidgets('SSH key missing from the allowed signers file names the file', (
    tester,
  ) async {
    await pump(
      tester,
      const SignatureVerdict(
        state: SignatureState.untrusted,
        key: _fp,
        fingerprint: _fp,
      ),
      allowedSignersFile: '/home/me/.ssh/allowed_signers',
    );
    await tester.tap(find.text('Valid, untrusted key'));
    await tester.pump();
    expect(
      find.textContaining('/home/me/.ssh/allowed_signers'),
      findsOneWidget,
    );
  });

  testWidgets('an unsigned badge has nothing to expand', (tester) async {
    await pump(tester, SignatureVerdict.unsigned);
    await tester.tap(find.text('Not signed'));
    await tester.pump();
    expect(find.text('Signer'), findsNothing);
  });

  testWidgets('a badge without details neither offers nor opens them', (
    tester,
  ) async {
    await pump(
      tester,
      const SignatureVerdict(state: SignatureState.good, signer: 'Jane'),
      details: false,
    );
    expect(find.byIcon(Icons.expand_more), findsNothing);
    await tester.tap(find.text('Verified signature'));
    await tester.pump();
    expect(find.text('Jane'), findsNothing);
  });
}
