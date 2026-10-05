import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/signature.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/signatures.dart';
import 'package:mergelio/ui/workspace/signature_audit_panel.dart';

const _unsigned = UnverifiedCommit(
  sha: 'aaaaaaa1111',
  author: 'Ann',
  subject: 'quick fix',
  verdict: SignatureVerdict.unsigned,
);
const _bad = UnverifiedCommit(
  sha: 'bbbbbbb2222',
  author: 'Mal',
  subject: 'tampered',
  verdict: SignatureVerdict(state: SignatureState.bad),
);

void main() {
  late List<String> asked;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    String initialBase = 'origin/main',
    Future<SignatureAudit> Function(String base)? audit,
  }) async {
    asked = [];
    container = ProviderContainer(
      overrides: [
        signatureAuditProvider.overrideWith((ref, key) {
          asked.add(key.base);
          return (audit ??
              (_) async => const SignatureAudit(
                checked: 3,
                truncated: false,
                unverified: [_unsigned, _bad],
              ))(key.base);
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SignatureAuditPanel(repoPath: '/r', initialBase: initialBase),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('checks the default base on open and states the range', (
    tester,
  ) async {
    await pump(tester);
    expect(asked, ['origin/main']);
    expect(find.textContaining('origin/main..HEAD'), findsOneWidget);
  });

  testWidgets('lists every unverified commit with its verdict', (tester) async {
    await pump(tester);
    expect(
      find.text('2 commits of 3 lack a verified signature'),
      findsOneWidget,
    );
    expect(find.text('aaaaaaa'), findsOneWidget);
    expect(find.text('quick fix'), findsOneWidget);
    expect(find.text('Not signed'), findsOneWidget);
    expect(find.text('tampered'), findsOneWidget);
    expect(find.text('Bad signature'), findsOneWidget);
  });

  testWidgets('says so when every commit is verified', (tester) async {
    await pump(
      tester,
      audit: (_) async =>
          const SignatureAudit(checked: 4, truncated: false, unverified: []),
    );
    expect(
      find.text('All 4 commits have a verified signature'),
      findsOneWidget,
    );
  });

  testWidgets('an empty range says there is nothing to check', (tester) async {
    await pump(
      tester,
      audit: (_) async =>
          const SignatureAudit(checked: 0, truncated: false, unverified: []),
    );
    expect(find.text('No commits in this range'), findsOneWidget);
  });

  testWidgets('a truncated audit says only the latest were checked', (
    tester,
  ) async {
    await pump(
      tester,
      audit: (_) async => const SignatureAudit(
        checked: 500,
        truncated: true,
        unverified: [_unsigned],
      ),
    );
    expect(
      find.text('Only the latest 500 commits were checked.'),
      findsOneWidget,
    );
  });

  testWidgets('a failing audit shows git\'s error', (tester) async {
    await pump(
      tester,
      audit: (_) async => throw GitException(
        'git log signature audit failed',
        const GitResult(128, '', "fatal: bad revision 'nope..HEAD'"),
      ),
    );
    expect(find.text('Could not check signatures'), findsOneWidget);
    expect(find.textContaining('bad revision'), findsOneWidget);
  });

  testWidgets('no base means nothing runs until one is entered', (
    tester,
  ) async {
    await pump(tester, initialBase: '');
    expect(asked, isEmpty);

    await tester.enterText(find.byType(TextField), 'v1.0');
    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.pump();

    expect(asked, ['v1.0']);
    expect(find.textContaining('v1.0..HEAD'), findsOneWidget);
  });

  testWidgets('tapping a commit selects it in the graph', (tester) async {
    await pump(tester);
    await tester.tap(find.text('tampered'));
    await tester.pump();
    expect(container.read(selectedCommitProvider), 'bbbbbbb2222');
  });

  for (final width in [336.0, 480.0, 640.0]) {
    testWidgets('rows lay out without overflow at ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(
        tester,
        audit: (_) async => const SignatureAudit(
          checked: 2,
          truncated: false,
          unverified: [
            UnverifiedCommit(
              sha: 'ccccccc3333',
              author: 'A very long author name that keeps going',
              subject: 'A long subject line that will not fit in a row',
              verdict: SignatureVerdict(state: SignatureState.unverifiable),
            ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Cannot verify signature'), findsOneWidget);
    });
  }

  testWidgets('one unverified commit reads in the singular', (tester) async {
    await pump(
      tester,
      audit: (_) async => const SignatureAudit(
        checked: 3,
        truncated: false,
        unverified: [_unsigned],
      ),
    );
    expect(
      find.text('1 commit of 3 lacks a verified signature'),
      findsOneWidget,
    );
  });
}
