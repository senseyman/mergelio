import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/maintenance.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/maintenance.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/maintenance_panel.dart';

final _now = DateTime.utc(2026, 9, 30, 12);
int _secsAgo(int days) =>
    _now.subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000;

const _refs = 'a refs/heads/main\n';
final _bigSha = 'b' * 40;

/// Scripts every git read the panel makes. Nothing here spawns git.
class _FakeGit implements GitService {
  final calls = <String>[];
  final responses = <String, GitResult>{
    'for-each-ref --format=%(objectname) %(refname)': const GitResult(
      0,
      _refs,
      '',
    ),
    'for-each-ref --format=$branchInfoFormat refs/heads': GitResult(
      0,
      'main\t${_secsAgo(1)}\t\n'
          'done\t${_secsAgo(3)}\t\n'
          'held\t${_secsAgo(3)}\t\n'
          'old-work\t${_secsAgo(200)}\t\n'
          'fresh\t${_secsAgo(3)}\t\n',
      '',
    ),
    'symbolic-ref --quiet --short refs/remotes/origin/HEAD': const GitResult(
      0,
      'origin/main\n',
      '',
    ),
    'branch --show-current': const GitResult(0, 'main\n', ''),
    'for-each-ref --merged=main --format=%(refname:short) refs/heads':
        const GitResult(0, 'main\ndone\nheld\n', ''),
    'worktree list --porcelain': const GitResult(
      0,
      'worktree /r\nHEAD 1111\nbranch refs/heads/main\n\n'
          'worktree /wt/held\nHEAD 2222\nbranch refs/heads/held\n\n'
          'worktree /wt/gone\nHEAD 3333\nbranch refs/heads/fresh\nprunable gitdir '
          'file points to non-existent location\n\n',
      '',
    ),
    'reflog expire --all --dry-run --verbose': const GitResult(
      0,
      'would prune a\nwould prune b\nwould prune c\n',
      '',
    ),
    'for-each-ref --format=%(refname)%09%(objectname) refs/heads':
        const GitResult(
          0,
          'refs/heads/done\tsha-done\nrefs/heads/old-work\tsha-old\n',
          '',
        ),
    'cat-file --batch-all-objects --batch-check=$allObjectsFormat': GitResult(
      0,
      'blob $_bigSha 5242880\n',
      '',
    ),
    'log --all --reverse --format=$blobOriginFormat --name-only '
        '--find-object=$_bigSha': const GitResult(
      0,
      'c1\x1fc1abc\x1f2026-01-01T00:00:00Z\x1fadd the demo video\n'
          '\nassets/video.mp4\n',
      '',
    ),
  };

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    final key = args.join(' ');
    calls.add(key);
    // The network environment probes config; nothing is configured.
    if (args.first == 'config') return const GitResult(1, '', '');
    return responses[key] ?? const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _size = MaintenanceSize(
  gitDir: '/r/.git',
  disk: GitDirSize(
    packBytes: 3 * 1024 * 1024,
    looseBytes: 2048,
    lfsBytes: 0,
    otherBytes: 1024,
  ),
  counts: CountObjects(looseCount: 7, packCount: 2),
);

Future<void> _pump(
  WidgetTester tester,
  _FakeGit git, {
  KeyValueStore? kv,
  double width = 900,
  List<Override> extra = const [],
  MaintenanceSize Function()? size,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(kv ?? InMemoryKeyValueStore()),
        maintenanceClockProvider.overrideWithValue(() => _now),
        // The real one walks the git directory on disk.
        maintenanceSizeProvider.overrideWith(
          (ref, path) async => size?.call() ?? _size,
        ),
        ...extra,
        settingsProvider.overrideWith(
          (_) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(dateFormat: 'iso'),
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(
          body: SingleChildScrollView(child: MaintenancePanel(repoPath: '/r')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows storage split and counts', (tester) async {
    await _pump(tester, _FakeGit());
    expect(find.textContaining('3.0 MB'), findsWidgets);
    expect(find.text('2 packs'), findsOneWidget);
    expect(find.text('7 objects'), findsOneWidget);
    expect(find.text('Git data: 3.0 MB'), findsOneWidget);
  });

  testWidgets('previews reflog expiry', (tester) async {
    await _pump(tester, _FakeGit());
    expect(
      find.text('The next gc would expire 3 reflog entries.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed read shows what git said, not an exception dump', (
    tester,
  ) async {
    final git = _FakeGit();
    git.responses['reflog expire --all --dry-run --verbose'] = const GitResult(
      128,
      '',
      'fatal: bad reflog',
    );
    await _pump(tester, git);
    expect(find.text('Could not read this: fatal: bad reflog'), findsOneWidget);
    expect(find.textContaining('GitException'), findsNothing);
  });

  testWidgets('lists prunable worktrees', (tester) async {
    await _pump(tester, _FakeGit());
    expect(
      find.text('1 worktree points at a missing directory'),
      findsOneWidget,
    );
  });

  testWidgets('never scans on open; Scan lists the largest files', (
    tester,
  ) async {
    final git = _FakeGit();
    await _pump(tester, git);
    expect(git.calls.where((c) => c.startsWith('cat-file')), isEmpty);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('assets/video.mp4'), findsOneWidget);
    expect(find.text('5.0 MB'), findsOneWidget);
    expect(find.textContaining('add the demo video'), findsOneWidget);
    expect(find.text('Rescan'), findsOneWidget);
  });

  testWidgets('a cached scan from other refs says it is out of date', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    await kv.put(
      'maintenance:blobs:/r',
      jsonEncode(
        const BlobScan(
          scannedAt: '2026-09-01T00:00:00.000Z',
          fingerprint: 'older',
          blobs: [
            BigBlob(BlobEntry(sha: 's', size: 10, path: 'old.bin'), null),
          ],
        ).toJson(),
      ),
    );
    await _pump(tester, _FakeGit(), kv: kv);
    expect(find.text('old.bin'), findsOneWidget);
    expect(
      find.text('Out of date: branches or tags have moved since this scan'),
      findsOneWidget,
    );
  });

  testWidgets('a scan goes out of date while the panel is open', (
    tester,
  ) async {
    final kv = InMemoryKeyValueStore();
    await kv.put(
      'maintenance:blobs:/r',
      jsonEncode(
        BlobScan(
          scannedAt: '2026-09-01T00:00:00.000Z',
          fingerprint: refsFingerprint(_refs),
          blobs: const [],
        ).toJson(),
      ),
    );
    final branches = StateProvider<List<Branch>>(
      (ref) => const [Branch(name: 'main', tip: '1')],
    );
    final git = _FakeGit();
    await _pump(
      tester,
      git,
      kv: kv,
      extra: [
        repoDataProvider.overrideWith(
          (ref, path) async => RepoData(branches: ref.watch(branches)),
        ),
      ],
    );
    const stale = 'Out of date: branches or tags have moved since this scan';
    expect(find.text(stale), findsNothing);

    // A commit lands while the panel is open.
    git.responses['for-each-ref --format=%(objectname) %(refname)'] =
        const GitResult(0, 'b refs/heads/main\n', '');
    ProviderScope.containerOf(tester.element(find.byType(MaintenancePanel)))
        .read(branches.notifier)
        .state = const [
      Branch(name: 'main', tip: '2'),
    ];
    await tester.pumpAndSettle();
    expect(find.text(stale), findsOneWidget);
  });

  group('branches', () {
    testWidgets('lists merged and stale; a held branch cannot be picked', (
      tester,
    ) async {
      await _pump(tester, _FakeGit());
      expect(find.text('done'), findsOneWidget);
      expect(find.text('old-work'), findsOneWidget);
      expect(find.text('held'), findsOneWidget);
      expect(find.text('fresh'), findsNothing);
      expect(find.text('checked out in /wt/held'), findsOneWidget);
      final held = tester.widget<Checkbox>(
        find.byKey(const ValueKey('mt-branch-held')),
      );
      expect(held.onChanged, isNull);
    });

    testWidgets('delete confirms, names force-deleted ones, then deletes', (
      tester,
    ) async {
      final git = _FakeGit();
      await _pump(tester, git);
      await tester.tap(find.byKey(const ValueKey('mt-branch-done')));
      await tester.tap(find.byKey(const ValueKey('mt-branch-old-work')));
      await tester.pump();
      await tester.tap(find.text('Delete 2 branches'));
      await tester.pumpAndSettle();

      final body = find.textContaining('will be force-deleted');
      expect(body, findsOneWidget);
      final text = tester.widget<Text>(body).data!;
      expect(text, contains('old-work'));
      expect(text, isNot(contains('• done')));

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(
        git.calls,
        containsAllInOrder(['branch -D done', 'branch -D old-work']),
      );
    });

    testWidgets('cancelling the confirm deletes nothing', (tester) async {
      final git = _FakeGit();
      await _pump(tester, git);
      await tester.tap(find.byKey(const ValueKey('mt-branch-done')));
      await tester.pump();
      await tester.tap(find.text('Delete 1 branch'));
      await tester.pumpAndSettle();
      expect(find.textContaining('will be force-deleted'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        git.calls.where(
          (c) => c.startsWith('branch -d') || c.startsWith('branch -D'),
        ),
        isEmpty,
      );
    });
  });

  group('housekeeping', () {
    testWidgets('gc runs only after the confirm and shows what it freed', (
      tester,
    ) async {
      final git = _FakeGit();
      var reads = 0;
      await _pump(
        tester,
        git,
        size: () => reads++ == 0
            ? _size
            : const MaintenanceSize(
                gitDir: '/r/.git',
                disk: GitDirSize(packBytes: 1024 * 1024),
                counts: CountObjects(packCount: 1),
              ),
      );
      await tester.tap(find.text('Run gc'));
      await tester.pumpAndSettle();
      expect(git.calls, isNot(contains('gc')));
      expect(find.text('Run git gc?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Run'));
      await tester.pumpAndSettle();
      expect(git.calls, contains('gc'));
      expect(find.text('Git data: 3.0 MB → 1.0 MB'), findsOneWidget);
    });

    testWidgets('a run that freed nothing does not claim a change', (
      tester,
    ) async {
      await _pump(tester, _FakeGit());
      await tester.tap(find.text('Run gc'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Run'));
      await tester.pumpAndSettle();
      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('declining the confirm runs nothing', (tester) async {
      final git = _FakeGit();
      await _pump(tester, git);
      await tester.tap(find.text('Run maintenance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(git.calls, isNot(contains('maintenance run')));
    });
  });

  for (final width in [336.0, 480.0, 760.0]) {
    testWidgets('lays out without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      final git = _FakeGit();
      await _pump(tester, git, width: width);
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
