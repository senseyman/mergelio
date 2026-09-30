import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lfs.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Scripts git by exact argument list and records the busy lanes held while
/// each call ran.
class _FakeGit implements GitService {
  final calls = <List<String>>[];
  final lanesAtCall = <String, ({bool repo, bool fetch})>{};
  final responses = <String, GitResult>{};
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
    calls.add(args);
    final key = args.join(' ');
    lanesAtCall[key] = (
      repo: container.read(busyProvider) != null,
      fetch: container.read(fetchBusyProvider) != null,
    );
    if (args.first == 'config') return const GitResult(1, '', '');
    return responses[key] ?? const GitResult(0, '[]', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;

  Iterable<List<String>> get lfsCalls => calls.where((c) => c.first == 'lfs');
}

void main() {
  late _FakeGit git;
  late InMemoryKeyValueStore kv;
  late ProviderContainer container;
  late RepoActions actions;

  const lock = LfsLock(id: '7', path: 'art/a.psd', owner: 'Bo');

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
    actions = container.read(repoActionsProvider('/r'));
    addTearDown(container.dispose);
  });

  int gen() => container.read(lfsGenerationProvider('/r'));
  List<List<String>> ran() => git.lfsCalls.toList();
  Toast lastToast() => container.read(toastProvider).last;

  Future<List<String>> journalLabels() async {
    final j = OperationJournal(kv, '/r');
    await j.load();
    return j.records.map((r) => r.label).toList();
  }

  group('argv', () {
    test('lfsLock locks the path', () async {
      expect(await actions.lfsLock('art/a.psd'), isTrue);
      expect(ran(), [
        ['lfs', 'lock', '--json', '--', 'art/a.psd'],
      ]);
    });

    test('lfsUnlock unlocks by id without force', () async {
      expect(await actions.lfsUnlock(lock), isTrue);
      expect(ran(), [
        ['lfs', 'unlock', '--json', '--id', '7'],
      ]);
    });

    test('lfsForceUnlock passes --force', () async {
      expect(await actions.lfsForceUnlock(lock), isTrue);
      expect(ran(), [
        ['lfs', 'unlock', '--json', '--force', '--id', '7'],
      ]);
    });

    test('unlock uses the id, never a dash-leading path', () async {
      const odd = LfsLock(id: '7', path: '-x.psd', owner: 'Bo');
      await actions.lfsUnlock(odd);
      expect(ran().single, containsAllInOrder(['--id', '7']));
      expect(ran().single, isNot(contains('-x.psd')));
    });
  });

  group('lanes', () {
    test('each action holds the fetch lane, not the repo lane', () async {
      await actions.lfsLock('a.psd');
      await actions.lfsUnlock(lock);
      await actions.lfsForceUnlock(lock);
      for (final key in [
        'lfs lock --json -- a.psd',
        'lfs unlock --json --id 7',
        'lfs unlock --json --force --id 7',
      ]) {
        final lanes = git.lanesAtCall[key]!;
        expect(lanes.fetch, isTrue, reason: key);
        expect(lanes.repo, isFalse, reason: key);
      }
      expect(container.read(fetchBusyProvider), isNull);
    });

    test('a busy fetch lane refuses without running git or bumping', () async {
      container.read(fetchBusyProvider.notifier).state = const BusyState(
        'Fetch',
      );
      expect(await actions.lfsLock('a.psd'), isFalse);
      expect(await actions.lfsUnlock(lock), isFalse);
      expect(await actions.lfsForceUnlock(lock), isFalse);
      expect(git.lfsCalls, isEmpty);
      expect(gen(), 0);
      final t = lastToast();
      expect(t.kind, ToastKind.warning);
      expect(t.title, 'An operation is already running');
    });

    test('a busy repo lane does not stop a lock', () async {
      container.read(busyProvider.notifier).state = const BusyState('Other');
      expect(await actions.lfsLock('a.psd'), isTrue);
    });
  });

  group('generation', () {
    test('bumped on success', () async {
      await actions.lfsLock('a.psd');
      await actions.lfsUnlock(lock);
      await actions.lfsForceUnlock(lock);
      expect(gen(), 3);
    });

    test('bumped on failure', () async {
      git.responses['lfs lock --json -- a.psd'] = const GitResult(2, '', 'no');
      git.responses['lfs unlock --json --id 7'] = const GitResult(2, '', 'no');
      git.responses['lfs unlock --json --force --id 7'] = const GitResult(
        2,
        '',
        'no',
      );
      expect(await actions.lfsLock('a.psd'), isFalse);
      expect(await actions.lfsUnlock(lock), isFalse);
      expect(await actions.lfsForceUnlock(lock), isFalse);
      expect(gen(), 3);
    });
  });

  group('failure reasons', () {
    test('unlock toast carries the JSON reason', () async {
      git.responses['lfs unlock --json --id 7'] = const GitResult(
        2,
        '[{"id":"7","unlocked":false,"reason":"lock is owned by Bo"}]',
        '',
      );
      expect(await actions.lfsUnlock(lock), isFalse);
      final t = lastToast();
      expect(t.kind, ToastKind.error);
      expect(t.description, 'lock is owned by Bo');
    });

    test('force unlock toast carries the JSON reason', () async {
      git.responses['lfs unlock --json --force --id 7'] = const GitResult(
        2,
        '[{"id":"7","unlocked":false,"reason":"not allowed"}]',
        '',
      );
      expect(await actions.lfsForceUnlock(lock), isFalse);
      expect(lastToast().description, 'not allowed');
    });

    test('unlock with non-JSON stdout falls back to stderr', () async {
      git.responses['lfs unlock --json --id 7'] = const GitResult(
        2,
        'oops',
        'server said no',
      );
      await actions.lfsUnlock(lock);
      expect(lastToast().description, 'server said no');
    });

    test('unlock refusal reported with exit 0 still fails', () async {
      git.responses['lfs unlock --json --id 7'] = const GitResult(
        0,
        '[{"id":"7","unlocked":false,"reason":"lock is owned by Bo"}]',
        '',
      );
      expect(await actions.lfsUnlock(lock), isFalse);
      expect(lastToast().description, 'lock is owned by Bo');
    });

    test('lock refusal with stderr shows that stderr', () async {
      git.responses['lfs lock --json -- a.psd'] = const GitResult(
        2,
        '{"message":"json message"}',
        'already locked by Bo',
      );
      expect(await actions.lfsLock('a.psd'), isFalse);
      expect(lastToast().description, 'already locked by Bo');
    });

    test('lock refusal with only a JSON message shows it', () async {
      git.responses['lfs lock --json -- a.psd'] = const GitResult(
        2,
        '{"message":"already locked by Bo"}',
        '',
      );
      await actions.lfsLock('a.psd');
      expect(lastToast().description, 'already locked by Bo');
    });
  });

  test('each action is journaled', () async {
    await actions.lfsLock('a.psd');
    await actions.lfsUnlock(lock);
    await actions.lfsForceUnlock(lock);
    expect(await journalLabels(), [
      'Lock a.psd',
      'Unlock art/a.psd',
      'Force unlock art/a.psd',
    ]);
  });
}
