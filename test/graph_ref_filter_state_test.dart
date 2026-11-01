import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/graph_ref_filter.dart';
import 'package:mergelio/state/graph_ref_filter.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';

/// Records every git call; answers the soloed-ref lookup, nothing else.
class _FakeGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(a);
    if (a.first == 'for-each-ref' && a.contains('--format=%(refname)')) {
      return const GitResult(0, 'refs/heads/feat\n', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// A store whose writes all fail, as a full disk or locked database would.
class _FailingStore extends InMemoryKeyValueStore {
  @override
  Future<void> put(String key, String value) async =>
      throw StateError('disk full');
}

void main() {
  const repo = '/r';

  ProviderContainer container(KeyValueStore kv, {GitService? git}) {
    final c = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(kv),
        if (git != null) gitServiceProvider.overrideWithValue(git),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('the filter is kept per repository across restarts', () async {
    final kv = InMemoryKeyValueStore();
    final first = container(kv);
    await first.read(graphRefFilterProvider(repo).future);
    await first
        .read(graphRefFilterProvider(repo).notifier)
        .toggleHidden('refs/heads/feat');
    await first
        .read(graphRefFilterProvider(repo).notifier)
        .toggleSolo('refs/heads/main');

    final again = container(kv);
    expect(
      await again.read(graphRefFilterProvider(repo).future),
      const GraphRefFilter(
        hidden: {'refs/heads/feat'},
        solo: {'refs/heads/main'},
      ),
    );
    expect(
      await again.read(graphRefFilterProvider('/other').future),
      GraphRefFilter.none,
    );
  });

  test('clear drops both hidden and soloed refs', () async {
    final c = container(InMemoryKeyValueStore());
    final ctl = c.read(graphRefFilterProvider(repo).notifier);
    await c.read(graphRefFilterProvider(repo).future);
    await ctl.toggleHidden('refs/heads/a');
    await ctl.toggleSolo('refs/heads/b');
    await ctl.clear();
    expect(
      await c.read(graphRefFilterProvider(repo).future),
      GraphRefFilter.none,
    );
  });

  test('the graph walk follows the filter', () async {
    final git = _FakeGit();
    final c = container(InMemoryKeyValueStore(), git: git);
    // Kept alive the way the open graph keeps it.
    c.listen(repoDataProvider(repo), (_, _) {});

    List<String> lastLog() =>
        git.calls.lastWhere((a) => a.first == 'log' && a.contains('-z'));

    await c.read(repoDataProvider(repo).future);
    expect(lastLog(), contains('--all'));

    await c
        .read(graphRefFilterProvider(repo).notifier)
        .toggleSolo('refs/heads/feat');
    await c.read(repoDataProvider(repo).future);

    expect(lastLog(), contains('refs/heads/feat'));
    expect(lastLog(), isNot(contains('--all')));
  });

  test('updates issued together all apply, in order', () async {
    final kv = InMemoryKeyValueStore();
    final c = container(kv);
    final ctl = c.read(graphRefFilterProvider(repo).notifier);
    // Not awaited one by one, as menu taps are not.
    await Future.wait([
      ctl.toggleHidden('refs/heads/a'),
      ctl.toggleHidden('refs/heads/b'),
      ctl.toggleSolo('refs/heads/c'),
    ]);
    const want = GraphRefFilter(
      hidden: {'refs/heads/a', 'refs/heads/b'},
      solo: {'refs/heads/c'},
    );
    expect(await c.read(graphRefFilterProvider(repo).future), want);
    // What is stored matches what is shown.
    expect(await container(kv).read(graphRefFilterProvider(repo).future), want);
  });

  test(
    'a store that cannot save neither throws nor loses the change',
    () async {
      final c = container(_FailingStore());
      final ctl = c.read(graphRefFilterProvider(repo).notifier);
      await ctl.toggleHidden('refs/heads/a');
      expect(
        await c.read(graphRefFilterProvider(repo).future),
        const GraphRefFilter(hidden: {'refs/heads/a'}),
      );
    },
  );
}
