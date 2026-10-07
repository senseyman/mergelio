import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/dashboard.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/dashboard.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/workspace.dart';

/// Porcelain v2 status for a branch with the given ahead/behind counts.
String _status({
  int ahead = 0,
  int behind = 0,
  bool dirty = false,
  bool upstream = true,
}) => [
  '# branch.oid 1234567890abcdef1234567890abcdef12345678',
  '# branch.head main',
  if (upstream) '# branch.upstream origin/main',
  if (upstream) '# branch.ab +$ahead -$behind',
  if (dirty) '1 .M N... 100644 100644 100644 aaa bbb a.txt',
  '',
].join('\x00');

/// Answers per repository. Fetches and pulls can be held open on a completer
/// to observe how many run at once, and give way to a cancel the way the real
/// service does: by throwing [GitCancelledException].
class _FakeGit implements GitService {
  final status = <String, String>{};
  final remotes = <String, String>{};
  final failing = <String>{};
  final calls = <(String, String)>[];
  late ProviderContainer container;
  Completer<void>? hold;
  int running = 0;
  int maxRunning = 0;
  final lanes = <(bool repo, bool fetch)>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    final repo = repoPath ?? '';
    calls.add((repo, args.join(' ')));
    switch (args.first) {
      case 'config':
        return const GitResult(1, '', '');
      case 'status':
        final s = status[repo];
        return s == null
            ? const GitResult(128, '', 'fatal: not a git repository')
            : GitResult(0, s, '');
      case 'rev-parse':
        return const GitResult(0, '', '');
      case 'remote':
        return GitResult(0, remotes[repo] ?? 'origin\n', '');
      case 'fetch' || 'pull':
        lanes.add((
          container.read(busyProvider) != null,
          container.read(fetchBusyProvider) != null,
        ));
        running++;
        if (running > maxRunning) maxRunning = running;
        try {
          while (hold != null && !hold!.isCompleted) {
            if (cancel?.isCancelled ?? false) {
              throw GitCancelledException('cancelled');
            }
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        } finally {
          running--;
        }
        if (failing.contains(repo)) {
          return const GitResult(1, '', 'fatal: could not read from remote');
        }
        return const GitResult(0, '', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.50.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _FakeGit git;
  late ProviderContainer container;
  late InMemoryKeyValueStore kv;
  late DashboardBatchController batch;

  setUp(() {
    git = _FakeGit();
    kv = InMemoryKeyValueStore();
    container = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(kv),
      ],
    );
    git.container = container;
    batch = container.read(dashboardBatchProvider.notifier);
    addTearDown(container.dispose);
  });

  List<String> repos(int n) => [for (var i = 0; i < n; i++) '/r/$i'];

  group('snapshot provider', () {
    test('reads one repository', () async {
      git.status['/r/a'] = _status(behind: 2);
      final s = await container.read(repoSnapshotProvider('/r/a').future);
      expect(s.summary.behind, 2);
    });

    test('a bumped generation re-reads the row', () async {
      git.status['/r/a'] = _status(behind: 2);
      final sub = container.listen(repoSnapshotProvider('/r/a'), (_, _) {});
      addTearDown(sub.close);
      await container.read(repoSnapshotProvider('/r/a').future);
      git.status['/r/a'] = _status(behind: 0);
      container.read(dashboardRowGenerationProvider('/r/a').notifier).state++;
      final s = await container.read(repoSnapshotProvider('/r/a').future);
      expect(s.summary.behind, 0);
    });
  });

  group('fetch all', () {
    test('fetches every repository on the fetch lane only', () async {
      for (final r in repos(3)) {
        git.status[r] = _status();
      }
      final out = await batch.fetchAll(repos(3), label: 'Fetch all');
      expect(out, isNotNull);
      expect(out!.kind, DashboardBatchKind.fetch);
      expect([
        for (final r in repos(3)) out.rows[r]!.state,
      ], everyElement(RowRunState.done));
      expect(git.lanes, everyElement((false, true)));
      // The lane is released once the batch is over.
      expect(container.read(fetchBusyProvider), isNull);
    });

    test('a repository with no remote is skipped, not fetched', () async {
      git.remotes['/r/0'] = '';
      final out = await batch.fetchAll(repos(2), label: 'Fetch all');
      expect(out!.rows['/r/0']!.state, RowRunState.skipped);
      expect(out.rows['/r/0']!.noRemote, isTrue);
      expect(out.rows['/r/1']!.state, RowRunState.done);
      expect(git.calls.where((c) => c.$2.startsWith('fetch')).length, 1);
    });

    test('one failure does not stop the rest and keeps its stderr', () async {
      git.failing.add('/r/1');
      final out = await batch.fetchAll(repos(3), label: 'Fetch all');
      expect(out!.rows['/r/1']!.state, RowRunState.failed);
      expect(out.rows['/r/1']!.message, contains('could not read'));
      expect(out.rows['/r/0']!.state, RowRunState.done);
      expect(out.rows['/r/2']!.state, RowRunState.done);
    });

    test('runs at most four at a time', () async {
      git.hold = Completer<void>();
      final run = batch.fetchAll(repos(10), label: 'Fetch all');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(git.running, kDashboardParallelism);
      git.hold!.complete();
      await run;
      expect(git.maxRunning, kDashboardParallelism);
    });

    test('refuses while the fetch lane is held', () async {
      container.read(fetchBusyProvider.notifier).state =
          const BusyState.network('Fetch');
      final out = await batch.fetchAll(repos(2), label: 'Fetch all');
      expect(out, isNull);
      expect(git.calls.where((c) => c.$2.startsWith('fetch')), isEmpty);
      expect(container.read(toastProvider), hasLength(1));
    });

    test('the lane busy state carries progress and a cancel', () async {
      git.hold = Completer<void>();
      final run = batch.fetchAll(repos(2), label: 'Fetch all');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final busy = container.read(fetchBusyProvider)!;
      expect(busy.label, 'Fetch all');
      expect(busy.onCancel, isNotNull);
      expect(busy.progress, 0);
      expect(busy.touchesWorkingTree, isFalse);
      git.hold!.complete();
      await run;
    });

    test('cancel stops running and queued rows alike', () async {
      git.hold = Completer<void>();
      final run = batch.fetchAll(repos(6), label: 'Fetch all');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.read(fetchBusyProvider)!.onCancel!();
      final out = await run;
      expect([
        for (final r in repos(6)) out!.rows[r]!.state,
      ], everyElement(RowRunState.cancelled));
      // Queued rows never reached git.
      expect(
        git.calls.where((c) => c.$2.startsWith('fetch')).length,
        kDashboardParallelism,
      );
      expect(container.read(fetchBusyProvider), isNull);
    });

    test('each fetched repository gets a journal record', () async {
      git.failing.add('/r/1');
      await batch.fetchAll(repos(2), label: 'Fetch all');
      final ok = container.read(operationJournalProvider('/r/0'));
      final bad = container.read(operationJournalProvider('/r/1'));
      expect(ok.records.single.label, 'Fetch');
      expect(ok.records.single.status, OpStatus.done);
      expect(bad.records.single.status, OpStatus.failed);
    });

    test('never loads the graph of a repository nobody has open', () async {
      await batch.fetchAll(repos(2), label: 'Fetch all');
      // Past the refresh coalescer's settle window.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(container.exists(repoDataProvider('/r/0')), isFalse);
      expect(git.calls.where((c) => c.$2.startsWith('log')), isEmpty);
    });

    test('reloads the graph of a repository already loaded', () async {
      final sub = container.listen(repoDataProvider('/r/0'), (_, _) {});
      addTearDown(sub.close);
      await container
          .read(repoDataProvider('/r/0').future)
          .then((_) {}, onError: (_) {});
      // The graph load's own status call; the dashboard's asks for --branch.
      const loadStatus = 'status --porcelain=v2 -z --untracked-files=all';
      int loads() => git.calls.where((c) => c.$2 == loadStatus).length;
      final before = loads();
      await batch.fetchAll(repos(1), label: 'Fetch all');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(loads(), before + 1);
    });

    test('finished rows have their generation bumped', () async {
      final sub = container.listen(
        dashboardRowGenerationProvider('/r/0'),
        (_, _) {},
      );
      addTearDown(sub.close);
      await batch.fetchAll(repos(1), label: 'Fetch all');
      expect(sub.read(), 1);
    });

    test('a row generation is dropped once no row shows it', () async {
      final sub = container.listen(
        dashboardRowGenerationProvider('/r/0'),
        (_, _) {},
      );
      container.read(dashboardRowGenerationProvider('/r/0').notifier).state++;
      sub.close();
      await Future<void>.delayed(Duration.zero);
      expect(container.exists(dashboardRowGenerationProvider('/r/0')), isFalse);
    });

    test('a second batch cannot start while one runs', () async {
      git.hold = Completer<void>();
      final run = batch.fetchAll(repos(1), label: 'Fetch all');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(await batch.pullAll(repos(1), label: 'Pull'), isNull);
      git.hold!.complete();
      await run;
    });
  });

  group('pull fast-forwardable', () {
    test(
      'pulls only eligible repositories, listing why others were skipped',
      () async {
        git.status['/r/0'] = _status(behind: 1);
        git.status['/r/1'] = _status(behind: 1, dirty: true);
        git.status['/r/2'] = _status(ahead: 1, behind: 1);
        git.status['/r/3'] = _status();
        git.status['/r/4'] = _status(upstream: false);
        // /r/5 has no status answer: unreadable.
        final out = await batch.pullAll(repos(6), label: 'Pull');
        expect(out!.kind, DashboardBatchKind.pull);
        expect(out.rows['/r/0']!.state, RowRunState.done);
        expect(out.rows['/r/1']!.pullSkip, PullSkip.dirty);
        expect(out.rows['/r/2']!.pullSkip, PullSkip.diverged);
        expect(out.rows['/r/3']!.pullSkip, PullSkip.upToDate);
        expect(out.rows['/r/4']!.pullSkip, PullSkip.noUpstream);
        expect(out.rows['/r/5']!.pullSkip, PullSkip.unreadable);
        for (final r in ['/r/1', '/r/2', '/r/3', '/r/4', '/r/5']) {
          expect(out.rows[r]!.state, RowRunState.skipped);
        }
        final pulls = git.calls.where((c) => c.$2.startsWith('pull')).toList();
        expect(pulls, [('/r/0', 'pull --ff-only --no-rebase')]);
      },
    );

    test('a pulled repository refreshes its LFS state', () async {
      git.status['/r/0'] = _status(behind: 1);
      git.status['/r/1'] = _status();
      await batch.pullAll(repos(2), label: 'Pull');
      expect(container.read(lfsGenerationProvider('/r/0')), 1);
      expect(container.read(lfsGenerationProvider('/r/1')), 0);
    });

    test('holds the repository lane, not the fetch lane', () async {
      git.status['/r/0'] = _status(behind: 1);
      await batch.pullAll(repos(1), label: 'Pull');
      expect(git.lanes, [(true, false)]);
      expect(container.read(busyProvider), isNull);
    });

    test('refuses while another repository operation runs', () async {
      git.status['/r/0'] = _status(behind: 1);
      container.read(busyProvider.notifier).state = const BusyState('Commit');
      expect(await batch.pullAll(repos(1), label: 'Pull'), isNull);
      expect(git.calls.where((c) => c.$2.startsWith('pull')), isEmpty);
    });

    test('a pull failure is reported with git stderr', () async {
      git.status['/r/0'] = _status(behind: 1);
      git.failing.add('/r/0');
      final out = await batch.pullAll(repos(1), label: 'Pull');
      expect(out!.rows['/r/0']!.state, RowRunState.failed);
      expect(out.rows['/r/0']!.message, contains('could not read'));
    });
  });

  test('switching group clears a finished batch', () async {
    final ws = container.read(workspaceProvider.notifier);
    ws.openRepo('/r/0');
    await batch.fetchAll(repos(1), label: 'Fetch all');
    ws.setActiveGroup(ws.createGroup('Other').id);
    expect(container.read(dashboardBatchProvider), isNull);
  });

  test('switching group leaves a running batch alone', () async {
    final ws = container.read(workspaceProvider.notifier);
    ws.openRepo('/r/0');
    git.hold = Completer<void>();
    final run = batch.fetchAll(repos(1), label: 'Fetch all');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ws.setActiveGroup(ws.createGroup('Other').id);
    expect(container.read(dashboardBatchProvider), isNotNull);
    git.hold!.complete();
    expect(await run, isNotNull);
  });

  test('dismiss clears a finished batch', () async {
    await batch.fetchAll(repos(1), label: 'Fetch all');
    expect(container.read(dashboardBatchProvider), isNotNull);
    batch.dismiss();
    expect(container.read(dashboardBatchProvider), isNull);
  });
}
