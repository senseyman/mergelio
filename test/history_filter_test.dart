// Which commits the author and date filters select, read from git over the
// whole history rather than from the loaded page.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/history_filter.dart';

/// Answers the history walk with [result] and the stash lookups with
/// [stashes]; records only the walk.
class _FakeGit implements GitService {
  final GitResult result;
  final Object? throws;
  final String stashes;
  final String stashParents;
  final calls = <List<String>>[];
  final timeouts = <Duration?>[];
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

    Future<Set<String>> read(HistoryFilterKey key) {
      final c = ProviderContainer();
      addTearDown(c.dispose);
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
