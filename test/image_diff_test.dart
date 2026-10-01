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
import 'package:mergelio/domain/git/lfs.dart' show formatLfsSize;
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/binary_diff.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/diff/diff_sheet.dart';
import 'package:mergelio/ui/diff/image_diff.dart';

/// A real 1×1 PNG, so decoding can run too.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

BlobLoad _load(List<int> bytes) =>
    BlobLoad(size: bytes.length, bytes: Uint8List.fromList(bytes));

const _before = RevisionBlob('abc^', 'a.png');
const _after = RevisionBlob('abc', 'a.png');

Widget _app(
  Widget child, {
  required Map<BlobRef, BlobLoad?> blobs,
  bool fail = false,
}) => ProviderScope(
  overrides: [
    blobProvider.overrideWith((ref, req) async {
      if (fail) throw UnsupportedError('no bytes');
      return blobs[req.ref];
    }),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [AppTokens.dark()]),
    home: Scaffold(body: child),
  ),
);

Widget _compare({BlobRef? before = _before, BlobRef? after = _after}) =>
    BinaryCompare(repoPath: '/r', sides: (before: before, after: after));

void main() {
  testWidgets('two images offer every compare mode and their sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_compare(), blobs: {_before: _load(_png), _after: _load(_png)}),
    );
    await tester.pumpAndSettle();
    for (final mode in ['Side by side', 'Swipe', 'Onion skin', 'Difference']) {
      expect(find.text(mode), findsOneWidget);
    }
    expect(find.textContaining('1×1'), findsOneWidget);
    expect(find.textContaining('(±0 B)'), findsOneWidget);
    // Side by side labels each half.
    expect(find.text('Before'), findsOneWidget);
    expect(find.text('After'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('swipe and onion skin each bring a slider; difference does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_compare(), blobs: {_before: _load(_png), _after: _load(_png)}),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Swipe'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.text('Onion skin'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.text('Difference'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('every mode paints once both images are decoded', (tester) async {
    await tester.pumpWidget(
      _app(_compare(), blobs: {_before: _load(_png), _after: _load(_png)}),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('image-compare-ready')), findsOneWidget);
    for (final mode in ['Swipe', 'Onion skin', 'Difference', 'Side by side']) {
      await tester.tap(find.text(mode));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('an added image shows the one side, with no modes to choose', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_compare(before: null), blobs: {_after: _load(_png)}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Swipe'), findsNothing);
    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
    expect(find.textContaining('1×1'), findsOneWidget);
  });

  testWidgets('other binaries show a hex preview with the size delta', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _compare(),
        blobs: {
          _before: _load([0x00, 0x41, 0x42]),
          _after: _load([0x00, 0x41, 0x43, 0xff]),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Swipe'), findsNothing);
    expect(find.textContaining('First 4 bytes'), findsOneWidget);
    expect(find.textContaining('(+1 B)'), findsOneWidget);
    expect(find.textContaining('00000000'), findsNWidgets(2));
    expect(find.textContaining('.AC.'), findsOneWidget);
  });

  testWidgets('a side over the cap is not previewed, but its size is shown', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _compare(),
        blobs: {
          _before: _load(_png),
          _after: const BlobLoad(size: 1 << 30),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Too large to preview'), findsOneWidget);
    expect(find.textContaining(formatLfsSize(1 << 30)), findsOneWidget);
  });

  testWidgets('an engine without byte reads says the preview is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_compare(), blobs: const {}, fail: true));
    await tester.pumpAndSettle();
    expect(find.text('Preview unavailable'), findsOneWidget);
  });

  testWidgets('no wider than the smallest graph column without overflowing', (
    tester,
  ) async {
    for (final width in [336.0, 500.0, 900.0]) {
      tester.view.physicalSize = Size(width, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      for (final blobs in [
        {_before: _load(_png), _after: _load(_png)},
        {
          _before: _load(List.generate(300, (i) => i % 256)),
          _after: _load(List.generate(200, (i) => i % 256)),
        },
      ]) {
        await tester.pumpWidget(_app(_compare(), blobs: blobs));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'width $width');
      }
    }
  });

  testWidgets('the diff sheet shows a binary file as a binary compare', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_BinaryDiffGit()),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          lfsPathsProvider.overrideWith((ref, q) async => const <String>{}),
          blobProvider.overrideWith(
            (ref, req) async => {
              const RevisionBlob('abc^', 'a.png'): _load(_png),
              const RevisionBlob('abc', 'a.png'): _load(_png),
            }[req.ref],
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: const Scaffold(
            body: SizedBox(height: 400, child: DiffSheet(availableHeight: 400)),
          ),
        ),
      ),
    );
    final c = ProviderScope.containerOf(tester.element(find.byType(DiffSheet)));
    c.read(diffTargetProvider.notifier).state = const DiffTarget(
      repoPath: '/r',
      path: 'a.png',
      commitSha: 'abc',
    );
    await tester.pumpAndSettle();
    expect(find.byType(BinaryCompare), findsOneWidget);
    expect(find.text('Binary file — diff not shown'), findsNothing);
    expect(find.text('Swipe'), findsOneWidget);
  });
}

/// Answers every diff with one changed binary file.
class _BinaryDiffGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'show' || args.first == 'diff') {
      return const GitResult(0, '''
diff --git a/a.png b/a.png
index 1111111..2222222 100644
Binary files a/a.png and b/a.png differ
''', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}
