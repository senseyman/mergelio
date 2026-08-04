// Saving an edited file while something else is running. A fetch or a push
// never touches the working tree, so an editor save must not be turned away
// for the minutes one of them can take; an operation that does rewrite files
// still holds the save back.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_actions.dart';

void main() {
  late Directory repo;

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_save_busy_');
    await File('${repo.path}/notes.txt').writeAsString('before\n');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  Future<String> onDisk() => File('${repo.path}/notes.txt').readAsString();

  test('a save goes through while a fetch is running', () async {
    final c = container();
    c.read(busyProvider.notifier).state = const BusyState.network('Fetch');

    final saved = await c
        .read(repoActionsProvider(repo.path))
        .saveFileText('notes.txt', 'after\n');

    expect(saved, isTrue);
    expect(await onDisk(), 'after\n');
  });

  test('a save leaves the running operation as the busy one', () async {
    final c = container();
    c.read(busyProvider.notifier).state = const BusyState.network('Fetch');

    await c.read(repoActionsProvider(repo.path)).saveFileText('notes.txt', 'x');

    expect(c.read(busyProvider)?.label, 'Fetch');
  });

  test(
    'a save waits for an operation that rewrites the working tree',
    () async {
      final c = container();
      c.read(busyProvider.notifier).state = const BusyState('Pull');

      final saved = await c
          .read(repoActionsProvider(repo.path))
          .saveFileText('notes.txt', 'after\n');

      expect(saved, isFalse);
      expect(await onDisk(), 'before\n');
      expect(
        c.read(toastProvider).single.title,
        'An operation is already running',
      );
    },
  );

  test('an idle save claims nothing for itself', () async {
    final c = container();

    final saved = await c
        .read(repoActionsProvider(repo.path))
        .saveFileText('notes.txt', 'after\n');

    expect(saved, isTrue);
    expect(c.read(busyProvider), isNull);
  });
}
