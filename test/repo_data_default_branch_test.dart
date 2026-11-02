import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_data.dart';

/// Answers the default-branch lookup; every other call succeeds empty.
class _FakeGit implements GitService {
  final String originHead;
  _FakeGit(this.originHead);

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (a.first == 'symbolic-ref') return GitResult(0, '$originHead\n', '');
    if (a.first == 'for-each-ref' && a.contains('--format=%(refname:short)')) {
      return const GitResult(0, 'main\ndevelop\n', '');
    }
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  test('a load carries the default branch it found', () async {
    final c = ProviderContainer(
      overrides: [
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        gitServiceProvider.overrideWithValue(_FakeGit('origin/develop')),
      ],
    );
    addTearDown(c.dispose);
    c.listen(repoDataProvider('/r'), (_, _) {});

    final data = await c.read(repoDataProvider('/r').future);

    expect(data.defaultBranch, 'develop');
  });
}
