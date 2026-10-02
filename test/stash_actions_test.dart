import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/stash.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

/// Scripts git by exact argument list and records every call.
class _FakeGit implements GitService {
  final calls = <List<String>>[];
  final responses = <String, GitResult>{};

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
    return responses[args.join(' ')] ?? const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;

  List<String> get ran => [for (final c in calls) c.join(' ')];

  /// `git apply` runs carry a temp-file path; this keeps only the flags.
  List<String> get applies => [
    for (final c in calls)
      if (c.first == 'apply') c.sublist(0, c.length - 1).join(' '),
  ];
}

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
    actions = container.read(repoActionsProvider('/r'));
    addTearDown(container.dispose);
  });

  List<String> toasts() => [
    for (final t in container.read(toastProvider)) t.title,
  ];

  const contents = StashContents(baseSha: 'base', untrackedSha: 'untr');

  test('stashPush passes every option through', () async {
    await actions.stashPush(
      const StashPushOptions(
        message: 'm',
        keepIndex: true,
        includeUntracked: true,
        paths: ['a'],
      ),
    );
    expect(
      git.ran,
      contains(
        'stash push --keep-index --include-untracked -m m -- :(literal)a',
      ),
    );
  });

  test('stashBranch runs git stash branch', () async {
    await actions.stashBranch('topic', 'stash@{2}');
    expect(git.ran, contains('stash branch topic stash@{2}'));
  });

  test('stashBranch failure is toasted', () async {
    git.responses['stash branch topic stash@{0}'] = const GitResult(
      128,
      '',
      'fatal: a branch named topic already exists',
    );
    await actions.stashBranch('topic', 'stash@{0}');
    expect(toasts(), contains('Branch from stash failed'));
  });

  test('stashRename stores under the new message then drops the old', () async {
    git.responses['rev-parse --verify -q stash@{1}'] = const GitResult(
      0,
      'abc\n',
      '',
    );
    git.responses['rev-parse --verify -q stash@{2}'] = const GitResult(
      0,
      'abc\n',
      '',
    );
    await actions.stashRename('stash@{1}', 'better');
    final store = git.ran.indexOf('stash store -m better abc');
    final drop = git.ran.indexOf('stash drop -q stash@{2}');
    expect(store, isNonNegative);
    expect(drop, greaterThan(store));
  });

  test('stashRename never drops when the list shifted under it', () async {
    git.responses['rev-parse --verify -q stash@{0}'] = const GitResult(
      0,
      'abc\n',
      '',
    );
    git.responses['rev-parse --verify -q stash@{1}'] = const GitResult(
      0,
      'other\n',
      '',
    );
    await actions.stashRename('stash@{0}', 'better');
    expect(git.ran.where((c) => c.startsWith('stash drop')), isEmpty);
    expect(toasts(), contains('Rename stash failed'));
  });

  test('applyStashFile applies the file patch, undoably', () async {
    git.responses['diff --no-color --binary --find-renames base sha -- a.txt'] =
        const GitResult(0, 'diff --git a/a.txt b/a.txt\n', '');

    await actions.applyStashFile('sha', contents, path: 'a.txt');
    expect(git.applies, ['apply']);

    final undo = container.read(undoProvider('/r').notifier);
    await undo.undo();
    expect(git.applies, ['apply', 'apply --reverse']);
  });

  test(
    'applyStashFile reads an untracked file from the third parent',
    () async {
      git.responses['show --no-color --binary --format= untr -- n.txt'] =
          const GitResult(0, 'diff --git a/n.txt b/n.txt\n', '');

      await actions.applyStashFile(
        'sha',
        contents,
        path: 'n.txt',
        untracked: true,
      );
      expect(git.applies, ['apply']);
    },
  );

  test('applyStashFile toasts when the patch does not apply', () async {
    git.responses['diff --no-color --binary --find-renames base sha -- a.txt'] =
        const GitResult(0, 'diff --git a/a.txt b/a.txt\n', '');
    final failing = _FailingApplyGit(git);
    container.dispose();
    container = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(failing),
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      ],
    );
    actions = container.read(repoActionsProvider('/r'));

    await actions.applyStashFile('sha', contents, path: 'a.txt');
    expect([
      for (final t in container.read(toastProvider)) t.title,
    ], contains('Apply a.txt from stash failed'));
    expect(container.read(undoProvider('/r')).canUndo, isFalse);
  });

  test('applyStashPatch applies a hunk to the worktree, undoably', () async {
    await actions.applyStashPatch('diff --git a/a b/a\n');
    expect(git.applies, ['apply']);
    await container.read(undoProvider('/r').notifier).undo();
    expect(git.applies, ['apply', 'apply --reverse']);
  });
}

/// Delegates to [inner] but fails every `git apply`.
class _FailingApplyGit implements GitService {
  final _FakeGit inner;
  _FailingApplyGit(this.inner);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'apply') {
      return const GitResult(1, '', 'error: patch does not apply');
    }
    return inner.run(args, repoPath: repoPath);
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}
