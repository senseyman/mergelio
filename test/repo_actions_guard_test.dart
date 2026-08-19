import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/undo_stack.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _FakeGit git;
  late ProviderContainer container;
  late RepoActions actions;

  setUp(() {
    git = _FakeGit();
    container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(container.dispose);
    actions = container.read(repoActionsProvider('/r'));
  });

  // Fetching runs in its own lane and is guarded in fetch_lane_test.dart;
  // everything else still shares the one repository slot.
  test('a network op is refused and warns while another op runs', () async {
    container.read(busyProvider.notifier).state = const BusyState('Merge');

    await actions.pull();

    expect(git.calls.any((c) => c.first == 'pull'), isFalse);
    expect(
      container.read(toastProvider).any((t) => t.kind == ToastKind.warning),
      isTrue,
    );
    // The refused op must not clear the busy state the running op owns.
    expect(container.read(busyProvider)?.label, 'Merge');
  });

  test('saveFileText refuses a path that escapes the repository', () async {
    final saved = await actions.saveFileText('../outside.txt', 'boom');
    expect(saved, isFalse);
  });

  test('undo surfaces a filesystem error as a toast, not a crash', () async {
    container
        .read(undoProvider('/r').notifier)
        .record(
          UndoEntry(
            'Edit a.txt',
            undo: () async =>
                throw const FileSystemException('write failed', '/r/a.txt'),
            redo: () async {},
          ),
        );

    await actions.undo();

    expect(
      container.read(toastProvider).any((t) => t.kind == ToastKind.error),
      isTrue,
    );
    expect(container.read(busyProvider), isNull);
  });

  test('redo surfaces a filesystem error as a toast, not a crash', () async {
    final undoCtl = container.read(undoProvider('/r').notifier);
    undoCtl.record(
      UndoEntry(
        'Edit a.txt',
        undo: () async {},
        redo: () async =>
            throw const FileSystemException('write failed', '/r/a.txt'),
      ),
    );
    await actions.undo();

    await actions.redo();

    expect(
      container.read(toastProvider).any((t) => t.kind == ToastKind.error),
      isTrue,
    );
    expect(container.read(busyProvider), isNull);
  });
}
