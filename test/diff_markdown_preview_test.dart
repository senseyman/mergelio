// A Markdown file's diff can be flipped to a rendered view and back: split
// shows the old and new versions rendered side by side, inline shows only the
// new one. Each file remembers its own choice; anything that is not Markdown
// offers no rendered view.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/blob.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/binary_diff.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/diff_view_options.dart';
import 'package:mergelio/state/file_editor.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/common/markdown_view.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';

String _modified(String path) =>
    '''
diff --git a/$path b/$path
--- a/$path
+++ b/$path
@@ -1 +1 @@
-# Old title
+# New title
''';

const _added = '''
diff --git a/fresh.md b/fresh.md
new file mode 100644
--- /dev/null
+++ b/fresh.md
@@ -0,0 +1 @@
+# Fresh title
''';

/// Serves a canned working-tree diff for whichever path is asked for.
class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'diff' && !args.contains('--cached')) {
      for (final path in ['README.md', 'notes.md', 'pic.md', 'a.txt']) {
        if (args.contains(path)) return GitResult(0, _modified(path), '');
      }
      if (args.contains('fresh.md')) return const GitResult(0, _added, '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

BlobLoad _text(String s) {
  final bytes = Uint8List.fromList(utf8.encode(s));
  return BlobLoad(size: bytes.length, bytes: bytes);
}

final _blobs = <BlobRef, BlobLoad>{
  for (final path in ['README.md', 'notes.md']) ...{
    IndexBlob(path): _text('# Old title\n'),
    WorktreeBlob(path): _text('# New title\n'),
  },
  const WorktreeBlob('fresh.md'): _text('# Fresh title\n'),
  const IndexBlob('pic.md'): _text('![old shot](shot.png)\n'),
  const WorktreeBlob('pic.md'): _text('![new shot](shot.png)\n'),
};

Future<ProviderContainer> _open(
  WidgetTester tester,
  String path, {
  bool split = true,
  double width = 1000,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            AppSettings(diffSplit: split),
          ),
        ),
        blobProvider.overrideWith((ref, req) async => _blobs[req.ref]),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(
          body: SizedBox(height: 600, child: DiffSheet(availableHeight: 600)),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DiffSheet)),
  );
  container.read(diffTargetProvider.notifier).state = DiffTarget(
    repoPath: '/r',
    path: path,
  );
  await tester.pumpAndSettle();
  return container;
}

final _source = find.byKey(const ValueKey('md:source'));
final _rendered = find.byKey(const ValueKey('md:rendered'));

Finder _rich(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('a Markdown diff opens on its source', (tester) async {
    await _open(tester, 'README.md');

    expect(_source, findsOneWidget);
    expect(_rendered, findsOneWidget);
    expect(find.textContaining('@@'), findsOneWidget);
    expect(find.byType(MarkdownView), findsNothing);
  });

  testWidgets('any other file offers no rendered view', (tester) async {
    await _open(tester, 'a.txt');

    expect(_source, findsNothing);
    expect(_rendered, findsNothing);
  });

  testWidgets('split renders the old and the new version side by side', (
    tester,
  ) async {
    await _open(tester, 'README.md');

    await tester.tap(_rendered);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownView), findsNWidgets(2));
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(_rich('Old title'), findsOneWidget);
    expect(_rich('New title'), findsOneWidget);
    expect(find.textContaining('@@'), findsNothing);
  });

  testWidgets('inline renders only the new version', (tester) async {
    await _open(tester, 'README.md', split: false);

    await tester.tap(_rendered);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownView), findsOneWidget);
    expect(_rich('New title'), findsOneWidget);
    expect(_rich('Old title'), findsNothing);
  });

  testWidgets('Source brings the diff back', (tester) async {
    await _open(tester, 'README.md');

    await tester.tap(_rendered);
    await tester.pumpAndSettle();
    await tester.tap(_source);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownView), findsNothing);
    expect(find.textContaining('@@'), findsOneWidget);
  });

  testWidgets('a file with no old version says so on that side', (
    tester,
  ) async {
    await _open(tester, 'fresh.md');

    await tester.tap(_rendered);
    await tester.pumpAndSettle();

    expect(find.text('The file does not exist on this side'), findsOneWidget);
    expect(_rich('Fresh title'), findsOneWidget);
  });

  testWidgets('only the working-tree side reads images from disk', (
    tester,
  ) async {
    await _open(tester, 'pic.md');

    await tester.tap(_rendered);
    await tester.pumpAndSettle();

    // The index copy may differ from what is on disk, so its image is not
    // shown from there.
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, '/r/shot.png');
    expect(find.text('old shot'), findsOneWidget);
  });

  testWidgets('each file keeps its own view', (tester) async {
    final container = await _open(tester, 'README.md');

    await tester.tap(_rendered);
    await tester.pumpAndSettle();
    expect(container.read(diffRenderedFilesProvider), {
      const FileRef('/r', 'README.md'),
    });

    container.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: 'notes.md',
    );
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownView), findsNothing);
    expect(find.textContaining('@@'), findsOneWidget);

    container.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: 'README.md',
    );
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownView), findsNWidgets(2));
  });

  testWidgets('a narrow sheet offers the choice in its menu', (tester) async {
    await _open(tester, 'README.md', width: 336);

    // The full row is still laid out to measure it, just never hit-tested.
    expect(_rendered.hitTestable(), findsNothing);
    // The sheet header comes before any hunk header with the same menu.
    await tester.tap(find.byTooltip('More actions').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<VoidCallback>, 'Preview'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownView), findsNWidgets(2));
  });
}
