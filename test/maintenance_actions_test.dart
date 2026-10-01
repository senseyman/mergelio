import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/maintenance.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

/// Scripts git by exact argument list and records each call with the busy
/// lanes held while it ran.
class _FakeGit implements GitService {
  final calls = <List<String>>[];
  final responses = <String, GitResult>{};
  final timeouts = <String, Duration?>{};
  final lanesAtCall = <String, ({bool repo, bool fetch, bool touchesTree})>{};
  late ProviderContainer container;

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
    calls.add(args);
    timeouts[key] = timeout;
    final busy = container.read(busyProvider);
    lanesAtCall[key] = (
      repo: busy != null,
      fetch: container.read(fetchBusyProvider) != null,
      touchesTree: busy?.touchesWorkingTree ?? false,
    );
    return responses[key] ?? const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;

  List<String> get ran => [for (final c in calls) c.join(' ')];
}

const _headsKey = 'for-each-ref --format=%(refname)%09%(objectname) refs/heads';

HygieneBranch _branch(String name, {bool merged = true}) => HygieneBranch(
  name: name,
  lastCommit: DateTime.utc(2026),
  merged: merged,
  gone: false,
);

void main() {
  late _FakeGit git;
  late ProviderContainer container;
  late RepoActions actions;

  setUp(() {
    git = _FakeGit();
    container = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      ],
    );
    git.container = container;
    actions = container.read(repoActionsProvider('/r'));
    addTearDown(container.dispose);
  });

  List<String> toasts() => [
    for (final t in container.read(toastProvider)) t.title,
  ];

  group('deleteBranches', () {
    setUp(() {
      git.responses[_headsKey] = const GitResult(
        0,
        'refs/heads/a\tsha-a\nrefs/heads/b\tsha-b\nrefs/heads/main\tsha-m\n',
        '',
      );
    });

    test('merged ones are checked against the trunk, not HEAD', () async {
      // `branch -d` measures against HEAD or the upstream, so a branch merged
      // into the trunk is refused whenever something else is checked out.
      // The trunk check is made here instead, on the tip about to go.
      await actions.deleteBranches([
        _branch('a'),
        _branch('b', merged: false),
      ], trunk: 'main');
      expect(
        git.ran,
        containsAllInOrder([
          'merge-base --is-ancestor sha-a refs/heads/main',
          'branch -D a',
          'branch -D b',
        ]),
      );
      expect(git.ran, isNot(contains('branch -d a')));
      expect(
        git.ran.where((c) => c.contains('is-ancestor sha-b')),
        isEmpty,
        reason: 'an unmerged branch was confirmed as a force delete',
      );
      expect(git.lanesAtCall['branch -D a']!.repo, isTrue);
    });

    test('a merged branch that moved off the trunk is kept', () async {
      git.responses['merge-base --is-ancestor sha-a refs/heads/main'] =
          const GitResult(1, '', '');
      await actions.deleteBranches([
        _branch('a'),
        _branch('b', merged: false),
      ], trunk: 'main');
      expect(git.ran, isNot(contains('branch -D a')));
      expect(git.ran, contains('branch -D b'));
      expect(toasts(), contains('Some branches were not deleted'));
    });

    test('one undo entry puts every branch back at its old tip', () async {
      await actions.deleteBranches([
        _branch('a'),
        _branch('b', merged: false),
      ], trunk: 'main');
      final undo = container.read(undoProvider('/r').notifier);
      expect(container.read(undoProvider('/r')).past, hasLength(1));
      git.calls.clear();
      await undo.undo();
      expect(git.ran, containsAll(['branch a sha-a', 'branch b sha-b']));
    });

    test('a branch git refuses is reported; the rest still go', () async {
      git.responses['branch -D a'] = const GitResult(
        1,
        '',
        "error: branch 'a' not found",
      );
      await actions.deleteBranches([
        _branch('a'),
        _branch('b', merged: false),
      ], trunk: 'main');
      expect(git.ran, contains('branch -D b'));
      expect(toasts(), contains('Some branches were not deleted'));
      // Undo only restores what was actually deleted.
      git.calls.clear();
      await container.read(undoProvider('/r').notifier).undo();
      expect(git.ran, ['branch b sha-b']);
    });

    test(
      'a branch gone since the list was read does not stop the rest',
      () async {
        await actions.deleteBranches([
          _branch('vanished'),
          _branch('a'),
          _branch('b', merged: false),
        ], trunk: 'main');
        expect(git.ran, containsAll(['branch -D a', 'branch -D b']));
        expect(git.ran.where((c) => c.contains('vanished')), isEmpty);
        final warning = container
            .read(toastProvider)
            .firstWhere((t) => t.title == 'Some branches were not deleted');
        expect(warning.description, contains('vanished'));
        git.calls.clear();
        await container.read(undoProvider('/r').notifier).undo();
        expect(git.ran, containsAll(['branch a sha-a', 'branch b sha-b']));
        expect(git.ran, hasLength(2));
      },
    );

    test(
      'when none of them exist any more, nothing runs and it says so',
      () async {
        await actions.deleteBranches([
          _branch('x'),
          _branch('y'),
        ], trunk: 'main');
        expect(git.ran.where((c) => c.startsWith('branch')), isEmpty);
        expect(toasts(), contains('Delete 2 branches failed'));
        expect(container.read(undoProvider('/r')).past, isEmpty);
      },
    );

    test('nothing to delete runs nothing', () async {
      await actions.deleteBranches(const [], trunk: 'main');
      expect(git.calls, isEmpty);
    });
  });

  group('housekeeping', () {
    test('gc runs on the repo lane without blocking file saves', () async {
      git.responses['gc'] = const GitResult(0, '', 'Counting objects: 9\n');
      final out = await actions.runGc();
      expect(out, 'Counting objects: 9\n');
      final lanes = git.lanesAtCall['gc']!;
      expect(lanes.repo, isTrue);
      expect(lanes.touchesTree, isFalse);
      expect(git.timeouts['gc'], GitWriter.housekeepingTimeout);
    });

    test('maintenance run returns its output', () async {
      git.responses['maintenance run'] = const GitResult(0, 'ok\n', 'x\n');
      expect(await actions.runMaintenance(), 'ok\nx\n');
    });

    test('refuses while a fetch holds the fetch lane', () async {
      container.read(fetchBusyProvider.notifier).state = BusyState.network(
        'Fetch',
      );
      expect(await actions.runGc(), isNull);
      expect(git.ran, isNot(contains('gc')));
      expect(toasts(), contains('An operation is already running'));
    });

    test('a failed gc returns null and toasts', () async {
      git.responses['gc'] = const GitResult(128, '', 'fatal: gc is locked');
      expect(await actions.runGc(), isNull);
      expect(toasts(), contains('Run gc failed'));
    });
  });
}
