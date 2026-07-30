import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/logging.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';

/// Every repo action leaves a paper trail: one line when it starts and one
/// when it ends carrying the elapsed time, so a slow or failing fetch can be
/// diagnosed from the log alone.
void main() {
  group('AppLogger.timed', () {
    late _RecordingSink sink;

    setUp(() => sink = _RecordingSink());

    test('logs start and completion with the elapsed time', () async {
      var clock = DateTime.utc(2026, 1, 1);
      final log = AppLogger(sink: sink, now: () => clock);

      final result = await log.timed('Fetch', () async {
        clock = clock.add(const Duration(milliseconds: 1234));
        return 42;
      }, scope: '/repo');

      expect(result, 42);
      expect(sink.lines, hasLength(2));
      expect(sink.lines.first, contains('[/repo] Fetch started'));
      expect(sink.lines.last, contains('[/repo] Fetch completed in 1234ms'));
    });

    test('logs a failure with its cause and duration, then rethrows', () async {
      var clock = DateTime.utc(2026, 1, 1);
      final log = AppLogger(sink: sink, now: () => clock);

      await expectLater(
        log.timed('Pull', () async {
          clock = clock.add(const Duration(milliseconds: 50));
          throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(sink.lines.last, contains('ERROR'));
      expect(sink.lines.last, contains('Pull failed after 50ms'));
      expect(sink.lines.last, contains('boom'));
    });
  });

  group('RepoActions', () {
    late Directory repo;
    late _RecordingSink sink;
    late AppLogger previous;

    Future<void> g(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: repo.path);
      if (r.exitCode != 0) {
        throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
      }
    }

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('mergelio_action_log_');
      await g(['init', '-q', '-b', 'main']);
      await g(['config', 'user.email', 't@e.com']);
      await g(['config', 'user.name', 'T']);
      await g(['config', 'commit.gpgsign', 'false']);
      await File('${repo.path}/base.txt').writeAsString('base\n');
      await g(['add', '.']);
      await g(['commit', '-q', '-m', 'base']);

      sink = _RecordingSink();
      previous = appLog;
      appLog = AppLogger(sink: sink);
    });

    tearDown(() async {
      appLog = previous;
      if (await repo.exists()) await repo.delete(recursive: true);
    });

    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('staging a file logs start and timed completion', () async {
      await File('${repo.path}/a.txt').writeAsString('hi\n');

      await container().read(repoActionsProvider(repo.path)).stageFile('a.txt');

      expect(
        sink.lines,
        containsAllInOrder([
          contains('[${repo.path}] Stage a.txt started'),
          matches(RegExp(r'Stage a\.txt completed in \d+ms')),
        ]),
      );
    });

    test('a branch action logs under its action label', () async {
      await container()
          .read(repoActionsProvider(repo.path))
          .createBranch('feature');

      expect(
        sink.lines,
        containsAllInOrder([
          contains('[${repo.path}] Create branch feature started'),
          matches(RegExp(r'Create branch feature completed in \d+ms')),
        ]),
      );
    });

    test('opening a repo logs the load with its duration', () async {
      await container().read(repoDataProvider(repo.path).future);

      expect(
        sink.lines,
        containsAllInOrder([
          contains('[${repo.path}] Load repo started'),
          matches(RegExp(r'Load repo completed in \d+ms')),
        ]),
      );
    });

    test('a failing fetch logs the failure with its duration', () async {
      // The remote does not exist, so the fetch must fail.
      await g(['remote', 'add', 'origin', '${repo.path}/does-not-exist']);

      await container()
          .read(repoActionsProvider(repo.path))
          .fetch(silent: true);

      expect(
        sink.lines,
        containsAllInOrder([
          contains('[${repo.path}] Fetch started'),
          matches(RegExp(r'Fetch failed after \d+ms')),
        ]),
      );
    });
  });
}

class _RecordingSink implements LogSink {
  final lines = <String>[];

  @override
  void write(String line) => lines.add(line);
}
