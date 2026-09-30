import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

const _verify =
    '{"ours":[{"id":"1","path":"a.psd","owner":{"name":"me"}}],'
    '"theirs":[{"id":"2","path":"b.psd","owner":{"name":"you"}}]}';

/// Scripts git by argv; every `lfs locks` call is recorded.
class _Git implements GitService {
  final calls = <List<String>>[];
  GitResult locks = const GitResult(0, _verify, '');
  Object? throwOnLocks;

  int get lockQueries => calls
      .where((c) => c.length > 1 && c[0] == 'lfs' && c[1] == 'locks')
      .length;

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
    if (args.first == 'config') return const GitResult(1, '', '');
    if (args.length > 1 && args[0] == 'lfs' && args[1] == 'locks') {
      if (throwOnLocks != null) throw throwOnLocks!;
      return locks;
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

class _Harness {
  final git = _Git();
  final data = StateProvider<RepoData>(
    (ref) => const RepoData(remotes: ['origin']),
  );
  bool lfsRepo = true;
  String? tool = 'git-lfs/3.8.0';
  late final ProviderContainer c;

  _Harness() {
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(updateConsent: 'off'),
          ),
        ),
        repoDataProvider.overrideWith((ref, repo) => ref.watch(data)),
        lfsRepoProvider.overrideWith((ref, src) async => lfsRepo),
        lfsToolProvider.overrideWith((ref) async => tool),
      ],
    );
    addTearDown(c.dispose);
  }

  Future<LfsLockState> read() async {
    await c.read(repoDataProvider('/r').future);
    return c.read(lfsLocksProvider('/r').future);
  }

  void bump() => c.read(lfsGenerationProvider('/r').notifier).state++;
}

void main() {
  test('no LFS in the repo: no query, none', () async {
    final h = _Harness()..lfsRepo = false;
    expect(await h.read(), LfsLockState.none);
    expect(h.git.lockQueries, 0);
  });

  test('no git-lfs: no query', () async {
    final h = _Harness()..tool = null;
    expect(await h.read(), LfsLockState.none);
    expect(h.git.lockQueries, 0);
  });

  test('no remote: no query', () async {
    final h = _Harness();
    h.c.read(h.data.notifier).state = const RepoData();
    expect(await h.read(), LfsLockState.none);
    expect(h.git.lockQueries, 0);
  });

  test('ready: splits ours and theirs and is available', () async {
    final h = _Harness();
    final s = await h.read();
    expect(s.available, isTrue);
    expect(s.stale, isFalse);
    expect(s.ours.map((l) => l.path), ['a.psd']);
    expect(s.theirs.map((l) => l.path), ['b.psd']);
    expect(s.refreshedAt, isNotNull);
    expect(h.git.calls.any((c) => c.contains('--verify')), isTrue);
  });

  test(
    'lockFor finds a path among ours then theirs, exact match only',
    () async {
      final h = _Harness();
      final s = await h.read();
      expect(s.lockFor('a.psd')?.owner, 'me');
      expect(s.lockFor('b.psd')?.owner, 'you');
      expect(s.lockFor('a.ps'), isNull);
      expect(s.lockFor('dir/a.psd'), isNull);
      expect(LfsLockState.none.lockFor('a.psd'), isNull);
    },
  );

  test('reading twice runs one query', () async {
    final h = _Harness();
    await h.read();
    await h.read();
    expect(h.git.lockQueries, 1);
  });

  test('a generation bump runs a second query', () async {
    final h = _Harness();
    await h.read();
    h.bump();
    await h.read();
    expect(h.git.lockQueries, 2);
  });

  test('repo data changing without touching the stamp or remotes '
      'does not query again', () async {
    final h = _Harness();
    await h.read();
    h.c.read(h.data.notifier).state = const RepoData(
      remotes: ['origin'],
      working: [WorkingFile(path: 'src/a.dart', worktree: GitChange.modified)],
    );
    await h.read();
    expect(h.git.lockQueries, 1);
  });

  test('unsupported server: none, flag set, no query afterwards', () async {
    final h = _Harness();
    h.git.locks = const GitResult(
      1,
      '',
      'Error: Server error: missing protocol: "file:///x"',
    );
    expect(await h.read(), LfsLockState.none);
    await Future<void>.delayed(Duration.zero);
    expect(h.c.read(lfsLocksUnsupportedProvider('/r')), isTrue);
    h.bump();
    expect(await h.read(), LfsLockState.none);
    expect(h.git.lockQueries, 1);
  });

  test(
    'network error after a success keeps the previous locks, stale',
    () async {
      final h = _Harness();
      final first = await h.read();
      h.git.locks = const GitResult(1, '', 'dial tcp: lookup h: no such host');
      h.bump();
      final s = await h.read();
      expect(s.stale, isTrue);
      expect(s.available, isTrue);
      expect(s.ours, first.ours);
      expect(s.theirs, first.theirs);
      expect(s.refreshedAt, first.refreshedAt);
      expect(h.c.read(lfsLocksUnsupportedProvider('/r')), isFalse);
    },
  );

  test('unparseable output on exit 0 counts as a failure', () async {
    final h = _Harness();
    final first = await h.read();
    h.git.locks = const GitResult(0, 'not json', '');
    h.bump();
    final s = await h.read();
    expect(s.stale, isTrue);
    expect(s.ours, first.ours);
  });

  test('a thrown error counts as a failure', () async {
    final h = _Harness();
    await h.read();
    h.git.throwOnLocks = StateError('boom');
    h.bump();
    expect((await h.read()).stale, isTrue);
  });

  test(
    'failure with no previous state is empty, available and stale',
    () async {
      final h = _Harness();
      h.git.locks = const GitResult(1, '', 'connection refused');
      final s = await h.read();
      expect(s.ours, isEmpty);
      expect(s.theirs, isEmpty);
      expect(s.available, isTrue);
      expect(s.stale, isTrue);
    },
  );

  group('RepoActions', () {
    int gen(_Harness h) => h.c.read(lfsGenerationProvider('/r'));

    test('a user fetch bumps the generation', () async {
      final h = _Harness();
      await h.c.read(repoActionsProvider('/r')).fetch();
      expect(gen(h), 1);
    });

    test('a silent auto-fetch does not', () async {
      final h = _Harness();
      await h.c.read(repoActionsProvider('/r')).fetch(silent: true);
      expect(gen(h), 0);
    });

    test('a pull bumps the generation', () async {
      final h = _Harness();
      await h.c.read(repoActionsProvider('/r')).pull();
      expect(gen(h), 1);
    });
  });
}
