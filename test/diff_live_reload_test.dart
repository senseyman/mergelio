// The open diff of the working tree follows the file as it changes, whoever
// changes it — another editor, a terminal — without reopening the sheet.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/diff.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/repo_watcher.dart';
import 'package:mergelio/state/workspace.dart';

import 'support/hermetic_git.dart';
import 'support/refresh_counter.dart';

/// Every added line of [doc], across its hunks.
List<String> _added(DiffDoc doc) => [
  for (final f in doc.files)
    for (final h in f.hunks)
      for (final l in h.lines)
        if (l.type == DiffLineType.add) l.text,
];

/// Serves a diff of the working tree whose content a test can change, and
/// counts how often each kind of diff was read.
class _ChangingGit extends SilentGit {
  var worktreeText = 'one';
  var worktreeReads = 0;
  var commitReads = 0;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'show' ||
        (args.first == 'diff' && args.any((a) => a.contains('^')))) {
      commitReads++;
    } else if (args.first == 'diff') {
      worktreeReads++;
      return GitResult(0, '''
diff --git a/f.txt b/f.txt
--- a/f.txt
+++ b/f.txt
@@ -1 +1 @@
-zero
+$worktreeText
''', '');
    }
    return const GitResult(0, '', '');
  }
}

void main() {
  group('a reload of the repository', () {
    late _ChangingGit git;
    late ProviderContainer c;

    setUp(() {
      git = _ChangingGit();
      c = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
    });
    tearDown(() => c.dispose());

    Future<void> reload(String repo) async {
      c.read(repoActionsProvider(repo)).refresh();
      // Past the reload's settle window.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    test('re-reads the open working-tree diff', () async {
      const target = DiffTarget(repoPath: '/r', path: 'f.txt');
      c.read(diffTargetProvider.notifier).state = target;
      c.listen(diffDocumentProvider(target), (_, _) {});
      expect(_added(await c.read(diffDocumentProvider(target).future)), [
        'one',
      ]);

      git.worktreeText = 'two';
      await reload('/r');

      expect(_added(await c.read(diffDocumentProvider(target).future)), [
        'two',
      ]);
    });

    test('re-reads the staged side too: the index changes under it', () async {
      const target = DiffTarget(repoPath: '/r', path: 'f.txt', staged: true);
      c.read(diffTargetProvider.notifier).state = target;
      c.listen(diffDocumentProvider(target), (_, _) {});
      await c.read(diffDocumentProvider(target).future);
      final before = git.worktreeReads;

      await reload('/r');
      await c.read(diffDocumentProvider(target).future);

      expect(git.worktreeReads, greaterThan(before));
    });

    test('leaves a commit\'s diff alone: it cannot change', () async {
      const target = DiffTarget(repoPath: '/r', path: 'f.txt', commitSha: 'c1');
      c.read(diffTargetProvider.notifier).state = target;
      c.listen(diffDocumentProvider(target), (_, _) {});
      await c.read(diffDocumentProvider(target).future);
      final before = (git.commitReads, git.worktreeReads);

      await reload('/r');

      expect((git.commitReads, git.worktreeReads), before);
    });

    test('leaves another repository\'s diff alone', () async {
      const target = DiffTarget(repoPath: '/other', path: 'f.txt');
      c.read(diffTargetProvider.notifier).state = target;
      c.listen(diffDocumentProvider(target), (_, _) {});
      await c.read(diffDocumentProvider(target).future);
      final before = git.worktreeReads;

      await reload('/r');

      expect(git.worktreeReads, before);
    });

    test('with no diff open, reads no diff', () async {
      await reload('/r');

      expect(git.worktreeReads, 0);
    });
  });

  group('diffShowsSameLines', () {
    DiffDoc doc(List<String> added, {String path = 'f.txt', int start = 1}) =>
        DiffDoc(
          files: [
            FileDiff(
              path: path,
              status: GitChange.modified,
              hunks: [
                DiffHunk(
                  header: '@@ -$start +$start @@',
                  oldStart: start,
                  newStart: start,
                  lines: [
                    for (final (i, t) in added.indexed)
                      DiffLine(
                        type: DiffLineType.add,
                        newNo: start + i,
                        text: t,
                      ),
                  ],
                ),
              ],
            ),
          ],
          editable: true,
          staged: false,
        );

    test('the same lines read again are the same', () {
      expect(diffShowsSameLines(doc(['a', 'b']), doc(['a', 'b'])), isTrue);
    });

    test('a changed, added or moved line is not', () {
      final a = doc(['a', 'b']);
      expect(diffShowsSameLines(a, doc(['a', 'c'])), isFalse);
      expect(diffShowsSameLines(a, doc(['a', 'b', 'c'])), isFalse);
      expect(diffShowsSameLines(a, doc(['a', 'b'], start: 5)), isFalse);
      expect(diffShowsSameLines(a, doc(['a', 'b'], path: 'g.txt')), isFalse);
    });
  });

  group('a file edited outside the app', () {
    late Directory dir;
    const git = HermeticGit();

    Future<void> g(List<String> args) async {
      final r = await git.run(args, repoPath: dir.path);
      if (!r.ok) throw StateError('git ${args.join(' ')}: ${r.err}');
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mergelio_live_diff_');
      await g(['init', '-q', '-b', 'main']);
      await g(['config', 'user.email', 't@e.com']);
      await g(['config', 'user.name', 'T']);
      await File('${dir.path}/base.txt').writeAsString('base\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'init']);
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    /// Opens [path]'s working-tree diff the way the app does, with the
    /// repository active and watched, and returns how to read it.
    Future<Future<List<String>> Function()> open(String path) async {
      final c = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );
      addTearDown(c.dispose);
      c.read(workspaceProvider.notifier).openRepo(dir.path);
      c.listen(repoDataProvider(dir.path), (_, _) {});
      c.read(repoWatcherProvider);
      await c.read(repoDataProvider(dir.path).future);
      final target = DiffTarget(repoPath: dir.path, path: path);
      c.read(diffTargetProvider.notifier).state = target;
      c.listen(diffDocumentProvider(target), (_, _) {});
      return () async =>
          _added(await c.read(diffDocumentProvider(target).future));
    }

    /// Polls [read] until it returns [want], or gives up after a while — the
    /// watcher reacts to disk events after its own settle delay.
    Future<List<String>> waitFor(
      Future<List<String>> Function() read,
      List<String> want,
    ) async {
      var got = await read();
      for (var i = 0; i < 60 && !_same(got, want); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        got = await read();
      }
      return got;
    }

    test('a new file shows the line added to it', () async {
      final file = File('${dir.path}/1.txt');
      await file.writeAsString('123\n');
      final read = await open('1.txt');
      expect(await read(), ['123']);

      await file.writeAsString('123\nabs\n');

      expect(await waitFor(read, ['123', 'abs']), ['123', 'abs']);
    });

    test('a tracked file shows the line added to it', () async {
      final file = File('${dir.path}/base.txt');
      await file.writeAsString('base\nmore\n');
      final read = await open('base.txt');
      expect(await read(), ['more']);

      await file.writeAsString('base\nmore\nabs\n');

      expect(await waitFor(read, ['more', 'abs']), ['more', 'abs']);
    });
  });
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
