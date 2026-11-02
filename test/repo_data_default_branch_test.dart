import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';

/// Answers the default-branch lookup; every other call succeeds empty.
class _FakeGit implements GitService {
  /// Null: no `origin/HEAD` recorded.
  final String? originHead;

  /// The branch listing's tab-separated lines: name, HEAD mark, track, sha,
  /// upstream.
  final String heads;
  _FakeGit(this.originHead, this.heads);

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (a.first == 'symbolic-ref') {
      final h = originHead;
      return h == null ? const GitResult(1, '', '') : GitResult(0, '$h\n', '');
    }
    if (a.first == 'for-each-ref' && a.contains('refs/heads')) {
      return GitResult(0, heads, '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  Future<String?> load(_FakeGit git) async {
    final c = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        gitServiceProvider.overrideWithValue(git),
      ],
    );
    addTearDown(c.dispose);
    c.listen(repoDataProvider('/r'), (_, _) {});
    return (await c.read(repoDataProvider('/r').future)).defaultBranch;
  }

  const mainAndDevelop = 'main\t*\t\taaa\t\ndevelop\t \t\tbbb\t\n';

  test("a load carries the remote's default branch", () async {
    expect(await load(_FakeGit('origin/develop', mainAndDevelop)), 'develop');
  });

  test('without a remote default it falls back to main', () async {
    expect(await load(_FakeGit(null, mainAndDevelop)), 'main');
  });

  test('a remote default with no local branch falls back too', () async {
    expect(await load(_FakeGit('origin/release', mainAndDevelop)), 'main');
  });

  test('none at all is null, not the checked-out branch', () async {
    expect(
      await load(_FakeGit(null, 'trunk\t*\t\taaa\t\nfeat\t \t\tbbb\t\n')),
      isNull,
    );
  });
}
