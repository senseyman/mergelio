// A Markdown file shown rendered: links leave for the web or open another
// repository file, and images come only from the repository — a remote one
// is never fetched.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/ui/common/markdown_view.dart';

Future<List<Uri>> _pump(
  WidgetTester tester,
  String text, {
  String path = 'docs/a.md',
  String? imageRoot,
  ValueChanged<String>? onOpenFile,
  Future<bool> Function(Uri)? launch,
}) async {
  final launched = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        markdownLaunchUrlProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return launch == null ? true : launch(uri);
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: MarkdownView(
            text: text,
            path: path,
            imageRoot: imageRoot,
            onOpenFile: onOpenFile,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return launched;
}

void main() {
  testWidgets('shows the text rendered, not its markup', (tester) async {
    await _pump(tester, '# Title\n\nSome **bold** words.');

    expect(find.textContaining('# Title'), findsNothing);
    expect(find.textContaining('Title', findRichText: true), findsOneWidget);
    expect(find.textContaining('**bold**', findRichText: true), findsNothing);
  });

  testWidgets('a web link opens in the browser', (tester) async {
    final launched = await _pump(tester, '[site](https://example.com/x)');

    await tester.tap(find.textContaining('site', findRichText: true));
    await tester.pumpAndSettle();

    expect(launched, [Uri.parse('https://example.com/x')]);
  });

  testWidgets('a relative link opens that repository file', (tester) async {
    final opened = <String>[];
    final launched = await _pump(
      tester,
      '[next](../guide/next.md#top)',
      onOpenFile: opened.add,
    );

    await tester.tap(find.textContaining('next', findRichText: true));
    await tester.pumpAndSettle();

    expect(opened, ['guide/next.md']);
    expect(launched, isEmpty);
  });

  testWidgets('a link the app does not follow does nothing', (tester) async {
    final opened = <String>[];
    final launched = await _pump(
      tester,
      '[mail](mailto:a@b.c) [out](../../x.md)',
      onOpenFile: opened.add,
    );

    await tester.tap(find.textContaining('mail', findRichText: true));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(launched, isEmpty);
  });

  testWidgets('a remote image is not loaded; its alt text stands in', (
    tester,
  ) async {
    await _pump(tester, '![build badge](https://img.example.com/b.svg)');

    expect(find.byType(Image), findsNothing);
    expect(find.text('build badge'), findsOneWidget);
    expect(find.byTooltip('Remote images are not loaded'), findsOneWidget);
  });

  testWidgets('a repository image loads from the folder it is given', (
    tester,
  ) async {
    await _pump(tester, '![shot](img/s.png)', imageRoot: '/r');

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, '/r/docs/img/s.png');
  });

  testWidgets('without a folder, a repository image shows its alt text', (
    tester,
  ) async {
    await _pump(tester, '![shot](img/s.png)');

    expect(find.byType(Image), findsNothing);
    expect(find.text('shot'), findsOneWidget);
  });

  for (final (name, launch) in <(String, Future<bool> Function(Uri))>[
    ('refuses', (_) async => false),
    ('throws', (_) async => throw Exception('no browser')),
  ]) {
    testWidgets('a browser that $name is reported', (tester) async {
      await _pump(tester, '[site](https://example.com/x)', launch: launch);

      await tester.tap(find.textContaining('site', findRichText: true));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MarkdownView)),
      );
      expect(container.read(toastProvider).map((t) => t.title), [
        'Could not open the link in your browser',
      ]);
    });
  }
}
