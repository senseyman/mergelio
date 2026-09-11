// Both sides of a comparison can be ref names, and refs move. The file list
// has to follow them — and only them: a two-dot comparison reads committed
// trees, so the working-tree churn that dominates a refresh means nothing to
// it, and a comparison of two object names cannot go stale at all.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/compare_target.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/repo_data.dart';

class _FakeGit implements GitService {
  var nameStatusCalls = 0;
  var fileDiffCalls = 0;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    if (args.contains('--name-status')) nameStatusCalls++;
    // A per-file comparison diff: `diff <from> <to> -- <path>`.
    if (args.first == 'diff' && args.contains('--')) fileDiffCalls++;
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _shaA = '1111111111111111111111111111111111111111';
const _shaB = '2222222222222222222222222222222222222222';

void main() {
  late _FakeGit git;
  late ProviderContainer c;
  var tip = 'a';
  var dirty = false;

  setUp(() {
    git = _FakeGit();
    tip = 'a';
    dirty = false;
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        repoDataProvider.overrideWith(
          (ref, path) async => RepoData(
            branches: [Branch(name: 'main', current: true, tip: tip)],
            working: dirty
                ? const [
                    WorkingFile(path: 'x.txt', worktree: GitChange.modified),
                  ]
                : const [],
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
  });

  Future<void> refresh() async {
    c.invalidate(repoDataProvider('/r'));
    await c.read(repoDataProvider('/r').future);
  }

  /// Reads the list the way the open panel does — subscribed, so the
  /// autoDispose provider stays alive across refreshes.
  Future<void> open(CompareTarget target) async {
    final sub = c.listen(compareFilesProvider(target), (_, _) {});
    addTearDown(sub.close);
    await c.read(compareFilesProvider(target).future);
  }

  test('a moved branch re-reads the list', () async {
    const target = CompareTarget(repoPath: '/r', from: 'main', to: 'feature');
    await open(target);
    expect(git.nameStatusCalls, 1);

    tip = 'b';
    await refresh();
    await c.read(compareFilesProvider(target).future);

    expect(git.nameStatusCalls, 2);
  });

  test('a working-tree edit does not', () async {
    const target = CompareTarget(repoPath: '/r', from: 'main', to: 'feature');
    await open(target);

    dirty = true;
    await refresh();
    await c.read(compareFilesProvider(target).future);

    expect(git.nameStatusCalls, 1);
  });

  test('an open diff of a compared file follows the refs as well', () async {
    const target = CompareTarget(repoPath: '/r', from: 'main', to: 'feature');
    final doc = diffDocumentProvider(target.fileTarget('x.txt'));
    final sub = c.listen(doc, (_, _) {});
    addTearDown(sub.close);
    await c.read(doc.future);
    expect(git.fileDiffCalls, 1);

    tip = 'b';
    await refresh();
    await c.read(doc.future);

    expect(git.fileDiffCalls, 2);
  });

  test('two object names never go stale, so nothing re-reads', () async {
    const target = CompareTarget(repoPath: '/r', from: _shaA, to: _shaB);
    await open(target);

    tip = 'b';
    await refresh();
    await c.read(compareFilesProvider(target).future);

    expect(git.nameStatusCalls, 1);
  });
}
