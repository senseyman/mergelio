import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/blob.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/binary_diff.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/ui/diff/image_diff.dart';
import 'package:mergelio/ui/merge/merge_tool.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakeGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  Future<List<BlobRef>> pump(WidgetTester tester, ConflictFile file) async {
    tester.view.physicalSize = const Size(1400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final asked = <BlobRef>[];
    final container = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(_FakeGit()),
        blobProvider.overrideWith((ref, req) async {
          asked.add(req.ref);
          return BlobLoad(size: _png.length, bytes: Uint8List.fromList(_png));
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(mergeSessionProvider('/r').notifier).state = MergeSession(
      branch: 'feature',
      files: [file],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(body: MergeTool(repoPath: '/r')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return asked;
  }

  testWidgets('a binary conflict previews mine against theirs', (tester) async {
    final asked = await pump(
      tester,
      const ConflictFile(path: 'logo.png', parts: [], binary: true),
    );
    expect(find.byType(BinaryCompare), findsOneWidget);
    expect(find.text('Swipe'), findsOneWidget);
    expect(
      asked,
      unorderedEquals(const [
        IndexBlob('logo.png', stage: 2),
        IndexBlob('logo.png', stage: 3),
      ]),
    );
    // The choice is still there under the preview.
    expect(find.text('Keep mine'), findsOneWidget);
  });

  testWidgets('a binary conflict with one side deleted shows the side left', (
    tester,
  ) async {
    final asked = await pump(
      tester,
      const ConflictFile(
        path: 'logo.png',
        parts: [],
        binary: true,
        kind: ConflictKind.deletedByThem,
      ),
    );
    expect(find.byType(BinaryCompare), findsOneWidget);
    expect(asked, const [IndexBlob('logo.png', stage: 2)]);
  });

  testWidgets('a text delete/modify conflict has no binary preview', (
    tester,
  ) async {
    await pump(
      tester,
      const ConflictFile(
        path: 'doc.txt',
        parts: [],
        kind: ConflictKind.deletedByThem,
      ),
    );
    expect(find.byType(BinaryCompare), findsNothing);
  });
}
