import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/release_notes.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/release_notes/release_notes_view.dart';
import 'package:pub_semver/pub_semver.dart';

final v19 = Version.parse('1.9.0');
final v110 = Version.parse('1.10.0');

void main() {
  final launched = <Uri>[];

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required List<Version> versions,
    Map<Version, Set<String>>? assets,
    Map<String, String> texts = const {},
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    launched.clear();
    final c = ProviderContainer(
      overrides: [
        releaseNotesAssetsProvider.overrideWith(
          (ref) async =>
              assets ??
              {
                v19: {'en', 'uk'},
                v110: {'en'},
              },
        ),
        releaseNotesTextProvider.overrideWith(
          (ref, key) async => texts[key] ?? 'body of $key',
        ),
        releaseNotesLaunchUrlProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return true;
        }),
      ],
    );
    addTearDown(c.dispose);
    c.read(workspaceProvider.notifier).openReleaseNotes(versions);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          locale: locale,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ReleaseNotesView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('shows each version newest first with its notes', (t) async {
    await pump(t, versions: [v110, v19]);
    final newer = t.getTopLeft(find.text('Mergelio 1.10.0'));
    final older = t.getTopLeft(find.text('Mergelio 1.9.0'));
    expect(newer.dy, lessThan(older.dy));
    expect(find.text('body of release_notes/1.10.0.en.md'), findsOneWidget);
    expect(find.text('body of release_notes/1.9.0.en.md'), findsOneWidget);
  });

  testWidgets('Ukrainian uses uk files and falls back to en', (t) async {
    await pump(t, versions: [v110, v19], locale: const Locale('uk'));
    expect(find.text('body of release_notes/1.9.0.uk.md'), findsOneWidget);
    expect(find.text('body of release_notes/1.10.0.en.md'), findsOneWidget);
  });

  testWidgets('a version without notes shows the empty state', (t) async {
    await pump(t, versions: [Version.parse('1.9.1')]);
    expect(find.text('No release notes for this version.'), findsOneWidget);
  });

  testWidgets('opens web links, ignores other schemes', (t) async {
    await pump(
      t,
      versions: [v110, v19],
      texts: {
        'release_notes/1.10.0.en.md': '[site](https://example.com/x)',
        'release_notes/1.9.0.en.md': '[file](file:///etc/passwd)',
      },
    );
    await t.tap(find.text('site', findRichText: true));
    await t.tap(find.text('file', findRichText: true));
    expect(launched, [Uri.parse('https://example.com/x')]);
  });
}
