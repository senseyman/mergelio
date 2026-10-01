import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
import 'package:mergelio/state/diff_document.dart';
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

  testWidgets('index and disk sides are read again for a new version; '
      'revisions are not', (tester) async {
    final asked = <BlobRequest>[];
    Widget at(Object v) => ProviderScope(
      overrides: [
        blobProvider.overrideWith((ref, req) async {
          asked.add(req);
          return _load(_png);
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: BinaryCompare(
            repoPath: '/r',
            sides: (before: _before, after: const IndexBlob('a.png')),
            version: v,
          ),
        ),
      ),
    );
    final v1 = Object(), v2 = Object();
    await tester.pumpWidget(at(v1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(at(v2));
    await tester.pumpAndSettle();
    expect(asked.where((r) => r.ref == _before).map((r) => r.version), [null]);
    expect(asked.where((r) => r.ref is IndexBlob).map((r) => r.version), [
      same(v1),
      same(v2),
    ]);
  });

  testWidgets('the sheet reads the side the document shows, and reads the '
      'disk again when the diff reloads', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final asked = <BlobRef>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(_BinaryDiffGit(staged: false)),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          lfsPathsProvider.overrideWith((ref, q) async => const <String>{}),
          blobProvider.overrideWith((ref, req) async {
            asked.add(req.ref);
            return _load(_png);
          }),
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
    // Asks for the staged side, but nothing is staged: the sheet falls back to
    // the unstaged change, and the preview must follow it.
    const target = DiffTarget(repoPath: '/r', path: 'a.png', staged: true);
    c.read(diffTargetProvider.notifier).state = target;
    await tester.pumpAndSettle();
    expect(
      asked,
      unorderedEquals(const [IndexBlob('a.png'), WorktreeBlob('a.png')]),
    );

    asked.clear();
    c.invalidate(diffDocumentProvider(target));
    await tester.pumpAndSettle();
    expect(
      asked,
      unorderedEquals(const [IndexBlob('a.png'), WorktreeBlob('a.png')]),
    );
  });

  testWidgets('a sheet dragged short does not overflow in any mode', (
    tester,
  ) async {
    for (final height in [60.0, 110.0]) {
      for (final blobs in [
        {_before: _load(_png), _after: _load(_png)},
        {
          _before: _load(List.generate(300, (i) => i % 256)),
          _after: _load(List.generate(200, (i) => i % 256)),
        },
      ]) {
        await tester.pumpWidget(
          _app(
            SizedBox(height: height, child: _compare()),
            blobs: blobs,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'height $height');
        for (final mode in ['Swipe', 'Onion skin', 'Difference']) {
          final f = find.text(mode);
          if (f.evaluate().isEmpty) continue;
          await tester.tap(f, warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$mode at $height');
        }
      }
    }
  });

  testWidgets('bytes that look like an image but do not decode fall back to '
      'hex', (tester) async {
    final broken = [..._png.sublist(0, 24), ...List.filled(40, 7)];
    await tester.pumpWidget(
      _app(_compare(), blobs: {_before: _load(broken), _after: _load(broken)}),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('First 64 bytes'), findsOneWidget);
  });

  group('ImageOverlayPainter', () {
    Future<ui.Image> solid(Color c) async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = c);
      return rec.endRecording().toImage(2, 2);
    }

    Future<List<int>> paintPixels(ImageOverlayPainter painter) async {
      final rec = ui.PictureRecorder();
      painter.paint(Canvas(rec), const Size(2, 2));
      final img = await rec.endRecording().toImage(2, 2);
      final data = await img.toByteData();
      return data!.buffer.asUint8List().toList();
    }

    const red = Color(0xFFFF0000), blue = Color(0xFF0000FF);
    List<int> px(Color c) => [
      for (var i = 0; i < 4; i++) ...[
        (c.r * 255).round(),
        (c.g * 255).round(),
        (c.b * 255).round(),
        255,
      ],
    ];

    ImageOverlayPainter make(
      ui.Image a,
      ui.Image b,
      ImageCompareMode mode,
      double mix,
    ) => ImageOverlayPainter(
      before: a,
      after: b,
      scale: 1,
      mode: mode,
      mix: mix,
      divider: const Color(0x00000000),
      quality: FilterQuality.none,
    );

    testWidgets('difference cancels identical pixels to black', (t) async {
      await t.runAsync(() async {
        final a = await solid(red), b = await solid(red);
        expect(
          await paintPixels(make(a, b, ImageCompareMode.difference, 0)),
          px(const Color(0xFF000000)),
        );
      });
    });

    testWidgets('swipe and onion skin move between the two sides', (t) async {
      await t.runAsync(() async {
        final a = await solid(red), b = await solid(blue);
        expect(
          await paintPixels(make(a, b, ImageCompareMode.swipe, 1)),
          px(red),
        );
        expect(
          await paintPixels(make(a, b, ImageCompareMode.swipe, 0)),
          px(blue),
        );
        expect(
          await paintPixels(make(a, b, ImageCompareMode.onionSkin, 0)),
          px(red),
        );
        expect(
          await paintPixels(make(a, b, ImageCompareMode.onionSkin, 1)),
          px(blue),
        );
      });
    });
  });
}

/// Answers diffs with one changed binary file; with [staged] false the
/// index side (`--cached`) has nothing.
class _BinaryDiffGit implements GitService {
  final bool staged;
  _BinaryDiffGit({this.staged = true});

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (!staged && args.contains('--cached')) return const GitResult(0, '', '');
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
