import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

const _hash =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

class _FakeGit implements GitService {
  final calls = <List<String>>[];
  String listed = '';
  String lfsFiles = '';
  String trackList = '';

  /// Command lines (args joined by a space) that fail with exit 2.
  final failing = <String>{};

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    if (failing.contains(args.join(' '))) return const GitResult(2, '', 'boom');
    if (args.first == 'ls-files') return GitResult(0, listed, '');
    if (args.first == 'check-attr') {
      final files = [
        for (final f in (stdin ?? '').split('\x00'))
          if (f.isNotEmpty) f,
      ];
      return GitResult(
        0,
        [for (final f in files) '$f\x00filter\x00lfs\x00'].join(),
        '',
      );
    }
    if (args.length >= 2 && args[0] == 'lfs' && args[1] == 'ls-files') {
      return GitResult(0, lfsFiles, '');
    }
    if (args.length == 2 && args[0] == 'lfs' && args[1] == 'track') {
      return GitResult(0, trackList, '');
    }
    return const GitResult(0, '', '');
  }

  bool ran(List<String> want) =>
      calls.any((c) => c.length == want.length && _same(c, want));

  static bool _same(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

class _H {
  _H(this.git, this.container);
  final _FakeGit git;
  final ProviderContainer container;
}

Future<_H> _pump(
  WidgetTester tester, {
  required WorkingFile file,
  bool isLfs = false,
  String? tool = '3.5.0',
  _FakeGit? git,
}) async {
  final g = git ?? _FakeGit();
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(g),
        lfsToolProvider.overrideWith((ref) async => tool),
        lfsPathsProvider.overrideWith(
          (ref, q) async => isLfs ? {file.path} : const <String>{},
        ),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(
          body: WorkingTreePanel(
            repoPath: '/r',
            data: RepoData(working: [file]),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _H(
    g,
    ProviderScope.containerOf(tester.element(find.byType(WorkingTreePanel))),
  );
}

Future<void> _openMenu(WidgetTester tester, String label) async {
  // The panel lists files as a tree, so a row shows its basename.
  await tester.tap(find.text(label.split('/').last), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

WorkingFile _wf(String p) => WorkingFile(path: p, worktree: GitChange.modified);

void main() {
  testWidgets('extension file offers both track items, no untrack', (t) async {
    await _pump(t, file: _wf('art/cover.psd'));
    await _openMenu(t, 'art/cover.psd');
    expect(find.text('Track *.psd with LFS'), findsOneWidget);
    expect(find.text('Track this file with LFS'), findsOneWidget);
    expect(find.text('Stop tracking with LFS…'), findsNothing);
  });

  testWidgets('file without an extension offers only the file item', (t) async {
    await _pump(t, file: _wf('Makefile'));
    await _openMenu(t, 'Makefile');
    expect(find.text('Track this file with LFS'), findsOneWidget);
    expect(find.textContaining('Track *.'), findsNothing);
  });

  testWidgets('an LFS row offers to stop tracking', (t) async {
    await _pump(t, file: _wf('art/cover.psd'), isLfs: true);
    await _openMenu(t, 'art/cover.psd');
    expect(find.text('Stop tracking with LFS…'), findsOneWidget);
  });

  testWidgets('git-lfs missing: no LFS items', (t) async {
    await _pump(t, file: _wf('art/cover.psd'), isLfs: true, tool: null);
    await _openMenu(t, 'art/cover.psd');
    expect(find.text('Blame'), findsOneWidget);
    expect(find.textContaining('with LFS'), findsNothing);
    expect(find.textContaining('Stop tracking'), findsNothing);
  });

  testWidgets('submodule and dash-leading paths get no LFS items', (t) async {
    await _pump(
      t,
      file: const WorkingFile(
        path: 'vendor',
        worktree: GitChange.modified,
        submodule: true,
      ),
    );
    await _openMenu(t, 'vendor');
    expect(find.textContaining('with LFS'), findsNothing);
  });

  testWidgets('dash-leading path gets no LFS items', (t) async {
    await _pump(t, file: _wf('-x.psd'));
    await _openMenu(t, '-x.psd');
    expect(find.textContaining('with LFS'), findsNothing);
  });

  testWidgets('track extension, then convert offer and staging', (t) async {
    final git = _FakeGit()
      ..listed = 'a.psd\x00b.psd\x00'
      ..lfsFiles = '$_hash * a.psd\n';
    final h = await _pump(t, file: _wf('art/cover.psd'), git: git);
    await _openMenu(t, 'art/cover.psd');
    await t.tap(find.text('Track *.psd with LFS'));
    await t.pumpAndSettle();
    expect(git.ran(['lfs', 'track', '*.psd']), isTrue);
    final toast = h.container
        .read(toastProvider)
        .firstWhere((x) => x.title.contains('not in LFS'));
    expect(toast.title, '1 committed file matches but is not in LFS');
    expect(toast.action!.label, 'Convert…');
    toast.action!.onPressed();
    await t.pumpAndSettle();
    expect(find.text('Convert files to LFS'), findsOneWidget);
    expect(find.text('b.psd'), findsOneWidget);
    expect(find.text('a.psd'), findsNothing);
    expect(find.textContaining('Nothing is committed'), findsOneWidget);
    await t.tap(find.text('Stage as LFS'));
    await t.pumpAndSettle();
    expect(git.ran(['add', '--renormalize', '--', 'b.psd']), isTrue);
    expect(git.calls.where((c) => c.first == 'commit'), isEmpty);
  });

  testWidgets('cancel in the convert dialog stages nothing', (t) async {
    final git = _FakeGit()..listed = 'b.psd\x00';
    final h = await _pump(t, file: _wf('art/cover.psd'), git: git);
    await _openMenu(t, 'art/cover.psd');
    await t.tap(find.text('Track *.psd with LFS'));
    await t.pumpAndSettle();
    h.container
        .read(toastProvider)
        .firstWhere((x) => x.action != null)
        .action!
        .onPressed();
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(git.calls.where((c) => c.first == 'add'), isEmpty);
  });

  testWidgets('no candidates: no convert toast', (t) async {
    final git = _FakeGit()..listed = 'a.psd\x00';
    final h = await _pump(t, file: _wf('art/cover.psd'), git: git);
    git.lfsFiles = '$_hash * a.psd\n';
    await _openMenu(t, 'art/cover.psd');
    await t.tap(find.text('Track *.psd with LFS'));
    await t.pumpAndSettle();
    expect(git.ran(['lfs', 'track', '*.psd']), isTrue);
    expect(
      h.container.read(toastProvider).any((x) => x.action != null),
      isFalse,
    );
  });

  testWidgets('track this file uses --filename', (t) async {
    final git = _FakeGit();
    await _pump(t, file: _wf('dir/x [1].psd'), git: git);
    await _openMenu(t, 'dir/x [1].psd');
    await t.tap(find.text('Track this file with LFS'));
    await t.pumpAndSettle();
    expect(git.ran(['lfs', 'track', '--filename', 'dir/x [1].psd']), isTrue);
  });

  testWidgets('untrack dialog lists patterns; picking one untracks it', (
    t,
  ) async {
    final git = _FakeGit()
      ..trackList =
          'Listing tracked patterns\n'
          '    *.psd (.gitattributes)\n'
          '    -weird (.gitattributes)\n'
          'Listing excluded patterns\n';
    await _pump(t, file: _wf('art/cover.psd'), isLfs: true, git: git);
    await _openMenu(t, 'art/cover.psd');
    await t.tap(find.text('Stop tracking with LFS…'));
    await t.pumpAndSettle();
    expect(find.text('*.psd (.gitattributes)'), findsOneWidget);
    expect(find.textContaining('-weird'), findsNothing);
    await t.tap(find.text('*.psd (.gitattributes)'));
    await t.pumpAndSettle();
    expect(git.ran(['lfs', 'untrack', '*.psd']), isTrue);
    expect(find.text('Stop tracking with LFS'), findsNothing);
  });

  testWidgets('convert dialog shows 20 paths and the remainder', (t) async {
    final git = _FakeGit()
      ..listed = [for (var i = 0; i < 25; i++) 'f$i.psd\x00'].join();
    final h = await _pump(t, file: _wf('art/cover.psd'), git: git);
    await _openMenu(t, 'art/cover.psd');
    await t.tap(find.text('Track *.psd with LFS'));
    await t.pumpAndSettle();
    h.container
        .read(toastProvider)
        .firstWhere((x) => x.action != null)
        .action!
        .onPressed();
    await t.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^f\d+\.psd$')), findsNWidgets(20));
    expect(find.text('and 5 more'), findsOneWidget);
  });

  testWidgets('untrack: failing pattern listing toasts, opens no dialog', (
    t,
  ) async {
    final git = _FakeGit()..failing.add('lfs track');
    final h = await _pump(t, file: _wf('art/cover.psd'), isLfs: true, git: git);
    await _openMenu(t, 'art/cover.psd');
    await t.tap(find.text('Stop tracking with LFS…'));
    await t.pumpAndSettle();
    final errors = h.container
        .read(toastProvider)
        .where((x) => x.kind == ToastKind.error);
    expect(errors, hasLength(1));
    expect(errors.single.description, contains('boom'));
    expect(find.text('Stop tracking with LFS'), findsNothing);
    expect(find.textContaining('(.gitattributes)'), findsNothing);
    expect(t.takeException(), isNull);
    expect(git.calls.where((c) => c.length > 1 && c[1] == 'untrack'), isEmpty);
  });

  testWidgets('track ok but ls-files fails: error toast, no offer', (t) async {
    final git = _FakeGit()..failing.add('ls-files -z');
    final h = await _pump(t, file: _wf('art/cover.psd'), git: git);
    await _openMenu(t, 'art/cover.psd');
    await t.tap(find.text('Track *.psd with LFS'));
    await t.pumpAndSettle();
    expect(git.ran(['lfs', 'track', '*.psd']), isTrue);
    final toasts = h.container.read(toastProvider);
    final errors = toasts.where((x) => x.kind == ToastKind.error);
    expect(errors, hasLength(1));
    expect(errors.single.description, contains('boom'));
    expect(toasts.any((x) => x.action != null), isFalse);
    expect(find.text('Convert files to LFS'), findsNothing);
    expect(t.takeException(), isNull);
    expect(git.calls.where((c) => c.first == 'add'), isEmpty);
  });
}
