import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/ui/workspace/lfs_banner.dart';

Widget _app({required bool repo, required String? tool}) => ProviderScope(
  overrides: [
    lfsRepoProvider.overrideWith((ref, s) async => repo),
    lfsToolProvider.overrideWith((ref) async => tool),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: const Scaffold(
      body: LfsBanner(repoPath: '/r', working: []),
    ),
  ),
);

void main() {
  testWidgets('shown for an LFS repo without git-lfs, with the OS hint', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(_app(repo: true, tool: null));
    await tester.pumpAndSettle();
    expect(find.textContaining('stores files with Git LFS'), findsOneWidget);
    expect(find.textContaining('Git for Windows includes it'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dismiss hides it for this repo', (tester) async {
    await tester.pumpWidget(_app(repo: true, tool: null));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stores files with Git LFS'), findsNothing);
    final c = ProviderScope.containerOf(tester.element(find.byType(LfsBanner)));
    expect(c.read(lfsBannerDismissedProvider), {'/r'});
  });

  testWidgets('absent when git-lfs is installed', (tester) async {
    await tester.pumpWidget(_app(repo: true, tool: '3.5.1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stores files with Git LFS'), findsNothing);
  });

  testWidgets('absent when the repo does not use LFS', (tester) async {
    await tester.pumpWidget(_app(repo: false, tool: null));
    await tester.pumpAndSettle();
    expect(find.textContaining('stores files with Git LFS'), findsNothing);
  });

  testWidgets('absent while still loading', (tester) async {
    await tester.pumpWidget(_app(repo: true, tool: null));
    // no settle: providers have not resolved yet
    expect(find.textContaining('stores files with Git LFS'), findsNothing);
    await tester.pumpAndSettle();
  });
}
