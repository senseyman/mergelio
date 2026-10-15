// Which commits the author and date filters select, read from git over the
// whole history rather than from the loaded page.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/history_filter.dart';
import 'package:mergelio/state/repo_data.dart';

/// Answers the history walk with [result] and the stash lookups with
/// [stashes]; records only the walk.
class _FakeGit implements GitService {
  final GitResult result;
  final Object? throws;
  final String stashes;
  final String stashParents;
  final calls = <List<String>>[];
  final timeouts = <Duration?>[];
  final environments = <Map<String, String>?>[];
  final cancels = <GitCancel?>[];

  /// When set, the walk waits on this instead of answering at once.
  Completer<void>? hang;
  _FakeGit(
    this.result, {
    this.throws,
    this.stashes = '',
    this.stashParents = '',
  });

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (a.first == 'stash') return GitResult(0, stashes, '');
    if (a.first == 'rev-list') return GitResult(0, stashParents, '');
    calls.add(a);
    timeouts.add(timeout);
    environments.add(environment);
    cancels.add(cancel);
    if (hang != null) await hang!.future;
    if (throws != null) throw throws!;
    return result;
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

int _epoch(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

void main() {
  ProviderContainer container(GitService git) {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the shas git reports for the author are returned', () async {
    final t = _epoch(DateTime(2026, 3, 1));
    final git = _FakeGit(GitResult(0, 'aaa\x00$t\nbbb\x00$t\n', ''));
    final c = container(git);

    final shas = await c.read(
      historyFilterProvider(const HistoryFilterKey('/r', 'ada')).future,
    );

    expect(shas, {'aaa', 'bbb'});
    expect(git.calls.single, contains('--author=ada'));
  });

  test('the date range is applied to the author time git printed', () async {
    final out = [
      'early\x00${_epoch(DateTime(2026, 3, 9, 23))}',
      'first\x00${_epoch(DateTime(2026, 3, 10))}',
      'last\x00${_epoch(DateTime(2026, 3, 12, 23, 59))}',
      'late\x00${_epoch(DateTime(2026, 3, 13))}',
    ].join('\n');
    final c = container(_FakeGit(GitResult(0, out, '')));

    final shas = await c.read(
      historyFilterProvider(
        HistoryFilterKey(
          '/r',
          '',
          since: DateTime(2026, 3, 10),
          until: DateTime(2026, 3, 12),
        ),
      ).future,
    );

    expect(shas, {'first', 'last'});
  });

  test('a walk over the whole history gets more than the default', () async {
    final git = _FakeGit(const GitResult(0, '', ''));
    final c = container(git);

    await c.read(
      historyFilterProvider(const HistoryFilterKey('/r', 'ada')).future,
    );

    expect(git.timeouts.single, const Duration(minutes: 2));
  });

  test('every stash is walked and its internal snapshots dropped', () async {
    final t = _epoch(DateTime(2026, 3, 1));
    final git = _FakeGit(
      GitResult(0, 's0\x00$t\ns1\x00$t\nidx\x00$t\nbase\x00$t\n', ''),
      stashes: 's0\ns1\n',
      stashParents: 's0 base idx\ns1 base idx1 untracked1\n',
    );
    final c = container(git);

    final shas = await c.read(
      historyFilterProvider(const HistoryFilterKey('/r', 'ada')).future,
    );

    expect(git.calls.single, containsAll(['s0', 's1']));
    expect(shas, {'s0', 's1', 'base'});
  });

  test('no author and no dates never reaches git', () async {
    final git = _FakeGit(const GitResult(0, 'aaa\x001\n', ''));
    final c = container(git);

    expect(
      await c.read(
        historyFilterProvider(const HistoryFilterKey('/r', ' ')).future,
      ),
      isEmpty,
    );
    expect(git.calls, isEmpty);
  });

  test('a failed read reports nothing rather than throwing', () async {
    final c = container(_FakeGit(const GitResult(128, '', 'fatal')));

    expect(
      await c.read(
        historyFilterProvider(const HistoryFilterKey('/r', 'a')).future,
      ),
      isEmpty,
    );
  });

  test('a hung or killed git reports nothing rather than throwing', () async {
    final c = container(
      _FakeGit(const GitResult(0, '', ''), throws: GitException('timed out')),
    );

    expect(
      await c.read(
        historyFilterProvider(const HistoryFilterKey('/r', 'a')).future,
      ),
      isEmpty,
    );
  });

  test('a malformed line is skipped', () async {
    final c = container(
      _FakeGit(GitResult(0, 'junk\nok\x00${_epoch(DateTime(2026))}\n', '')),
    );

    expect(
      await c.read(
        historyFilterProvider(const HistoryFilterKey('/r', 'a')).future,
      ),
      {'ok'},
    );
  });

  // Case folding of a non-ASCII name follows git's locale, and an app started
  // from the Dock or Finder may have none at all.
  test('the walk runs in a UTF-8 locale whatever the app inherited', () async {
    final git = _FakeGit(const GitResult(0, '', ''));
    final c = container(git);

    await c.read(
      historyFilterProvider(const HistoryFilterKey('/r', 'олег')).future,
    );

    expect(git.environments.single, containsPair('LC_ALL', 'C.UTF-8'));
  });

  test('hiding merges is passed to the walk', () async {
    final git = _FakeGit(const GitResult(0, '', ''));
    final c = container(git);

    await c.read(
      historyFilterProvider(const HistoryFilterKey('/r', 'a', noMerges: true))
          .future,
    );

    expect(git.calls.single, contains('--no-merges'));
  });

  test('a filter nobody watches any more kills its walk', () async {
    final git = _FakeGit(const GitResult(0, '', ''))..hang = Completer();
    addTearDown(() => git.hang!.complete());
    final c = container(git);

    final sub = c.listen(
      historyFilterProvider(const HistoryFilterKey('/r', 'al')),
      (_, _) {},
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(git.cancels.single, isNotNull);
    expect(git.cancels.single!.isCancelled, isFalse);

    sub.close();
    await Future<void>.delayed(Duration.zero);

    expect(git.cancels.single!.isCancelled, isTrue);
  });

  group('historyStamp', () {
    const base = RepoData(
      branches: [Branch(name: 'main', tip: 'a1')],
      remoteBranches: [RemoteBranch(remote: 'o', branch: 'main', tip: 'r1')],
      stashes: [Stash(ref: 'stash@{0}', sha: 's1', message: 'm')],
    );

    test('moves when a branch, remote branch or stash moves', () {
      final stamp = historyStamp(base);
      expect(
        historyStamp(
          base.copyWith(
            branches: const [Branch(name: 'main', tip: 'a2')],
          ),
        ),
        isNot(stamp),
      );
      expect(
        historyStamp(
          base.copyWith(
            remoteBranches: const [
              RemoteBranch(remote: 'o', branch: 'main', tip: 'r2'),
            ],
          ),
        ),
        isNot(stamp),
      );
      expect(historyStamp(base.copyWith(stashes: const [])), isNot(stamp));
      expect(historyStamp(base.copyWith(tags: const ['v1'])), isNot(stamp));
    });

    test('holds while only the loaded page or working tree changes', () {
      expect(
        historyStamp(base.copyWith(hasMoreCommits: true, working: const [])),
        historyStamp(base),
      );
    });
  });

  test('keys differing in merges or history state are different filters', () {
    const a = HistoryFilterKey('/r', 'a', stamp: 'x');
    expect(a, const HistoryFilterKey('/r', 'a', stamp: 'x'));
    expect(a == const HistoryFilterKey('/r', 'a', stamp: 'y'), isFalse);
    expect(
      a == const HistoryFilterKey('/r', 'a', stamp: 'x', noMerges: true),
      isFalse,
    );
  });

  test('keys differing only in a date are different filters', () {
    final a = HistoryFilterKey('/r', 'a', since: DateTime(2026));
    final b = HistoryFilterKey('/r', 'a', since: DateTime(2026, 2));

    expect(a, HistoryFilterKey('/r', 'a', since: DateTime(2026)));
    expect(
      a.hashCode,
      HistoryFilterKey('/r', 'a', since: DateTime(2026)).hashCode,
    );
    expect(a == b, isFalse);
    expect(a == HistoryFilterKey('/r', 'a', until: DateTime(2026)), isFalse);
  });

  group('a real repo', () {
    late Directory repo;
    const svc = SystemGitService();

    Future<void> g(List<String> args, {Map<String, String>? env}) async {
      final r = await svc.run(args, repoPath: repo.path, environment: env);
      if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }

    Future<void> commit(
      String msg, {
      required String name,
      required String email,
      required String authored,
      String? committed,
    }) => g(
      ['commit', '-q', '--allow-empty', '-m', msg],
      env: {
        'GIT_AUTHOR_NAME': name,
        'GIT_AUTHOR_EMAIL': email,
        'GIT_AUTHOR_DATE': authored,
        'GIT_COMMITTER_DATE': committed ?? authored,
      },
    );

    Future<String> sha(String rev) async =>
        (await svc.run(['rev-parse', rev], repoPath: repo.path)).stdout.trim();

    // Listened to, as the graph does: an unwatched filter is disposed, and
    // its walk killed, before git can answer.
    Future<Set<String>> read(HistoryFilterKey key, {GitService? git}) {
      final c = ProviderContainer(
        overrides: [if (git != null) gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(c.dispose);
      c.listen(historyFilterProvider(key), (_, _) {});
      return c.read(historyFilterProvider(key).future);
    }

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('mergelio_history_');
      await g(['init', '-q', '-b', 'main']);
      await g(['config', 'user.email', 't@e.com']);
      await g(['config', 'user.name', 'T']);
      await g(['config', 'commit.gpgsign', 'false']);
      // Rebased: authored in January, committed in March.
      await commit(
        'one',
        name: 'Ann Lee',
        email: 'ann@corp.io',
        authored: '2026-01-05T10:00:00',
        committed: '2026-03-01T10:00:00',
      );
      await commit(
        'two',
        name: 'Bob (dev)',
        email: 'bob@corp.io',
        authored: '2026-02-05T10:00:00',
      );
      await commit(
        'three',
        name: 'Old Name',
        email: 'old@x.io',
        authored: '2026-02-06T10:00:00',
      );
      // Maps "Old Name" away; the graph still shows the recorded name.
      await File('${repo.path}/.mailmap')
          .writeAsString('New Name <new@x.io> Old Name <old@x.io>\n');
    });

    tearDown(() async {
      if (await repo.exists()) await repo.delete(recursive: true);
    });

    test('the email matches, case-insensitively', () async {
      final shas = await read(HistoryFilterKey(repo.path, 'CORP.IO'));
      expect(shas, {await sha('HEAD~2'), await sha('HEAD~1')});
    });

    test('an author with pattern characters is matched literally', () async {
      expect(await read(HistoryFilterKey(repo.path, '(dev)')), {
        await sha('HEAD~1'),
      });
      expect(await read(HistoryFilterKey(repo.path, 'b.b')), isEmpty);
    });

    test('the name recorded in the commit matches despite a mailmap', () async {
      expect(await read(HistoryFilterKey(repo.path, 'old name')), {
        await sha('HEAD'),
      });
    });

    test('dates are the author date the graph shows', () async {
      final shas = await read(
        HistoryFilterKey(repo.path, '', since: DateTime(2026, 2, 1)),
      );
      // "one" was committed in March but authored in January.
      expect(shas, {await sha('HEAD~1'), await sha('HEAD')});

      final january = await read(
        HistoryFilterKey(repo.path, '', until: DateTime(2026, 1, 31)),
      );
      expect(january, {await sha('HEAD~2')});
    });

    test('stashes match the way the graph shows them', () async {
      await File('${repo.path}/f.txt').writeAsString('1\n');
      await g(['add', '.']);
      await commit(
        'base',
        name: 'Ann Lee',
        email: 'ann@corp.io',
        authored: '2026-04-01T10:00:00',
      );
      Future<void> stash(String text) async {
        await File('${repo.path}/f.txt').writeAsString(text);
        await g(
          ['stash', 'push', '-q'],
          env: {
            'GIT_AUTHOR_NAME': 'Ann Lee',
            'GIT_AUTHOR_EMAIL': 'ann@corp.io',
          },
        );
      }

      await stash('2\n');
      await stash('3\n');
      final newer = await sha('stash@{0}');
      final older = await sha('stash@{1}');
      // The snapshot of the index the newest stash keeps as its second parent:
      // reachable from refs/stash, never drawn by the graph.
      final index = await sha('stash@{0}^2');

      final shas = await read(HistoryFilterKey(repo.path, 'ann'));

      expect(shas, containsAll([newer, older]));
      expect(shas, isNot(contains(index)));
    });

    test('a non-ASCII name matches whatever the case, in any locale', () async {
      await commit(
        'cyr',
        name: 'Олег Петренко',
        email: 'oleg@x.io',
        authored: '2026-04-01T10:00:00',
      );
      // What a Finder launch hands git: no usable locale.
      final shas = await read(
        HistoryFilterKey(repo.path, 'олег'),
        git: const _BareLocaleGit(),
      );

      expect(shas, {await sha('HEAD')});
    });

    test('a start date before the early seventies keeps its commits', () async {
      await commit(
        'old',
        name: 'Ann Lee',
        email: 'ann@corp.io',
        authored: '1971-07-01T10:00:00',
        committed: '1971-07-01T10:00:00',
      );
      final old = await sha('HEAD');

      final shas = await read(
        HistoryFilterKey(repo.path, '', since: DateTime(1971, 6, 1)),
      );

      expect(shas, contains(old));
    });

    test('a commit on a branch that is not checked out is found', () async {
      await g(['switch', '-q', '-c', 'side']);
      await commit(
        'side',
        name: 'Zed',
        email: 'zed@x.io',
        authored: '2026-04-01T10:00:00',
      );
      final side = await sha('HEAD');
      await g(['switch', '-q', 'main']);

      expect(await read(HistoryFilterKey(repo.path, 'zed')), {side});
    });
  });
}

/// Real git, run as an app launched without a locale would run it: the C
/// locale, unless the caller asks for another.
class _BareLocaleGit implements GitService {
  const _BareLocaleGit();
  static const _real = SystemGitService();

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => _real.run(
    a,
    repoPath: repoPath,
    timeout: timeout,
    environment: {'LANG': 'C', 'LC_ALL': 'C', ...?environment},
    cancel: cancel,
    stdin: stdin,
  );

  @override
  Future<String> version() => _real.version();
  @override
  Future<bool> isRepository(String path) => _real.isRepository(path);
}
