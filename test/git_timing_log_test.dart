import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/concurrency.dart';
import 'package:mergelio/core/logging.dart';
import 'package:mergelio/domain/git/git_service.dart';

/// A command that times out tells you nothing about *why*: a repository can be
/// genuinely slow to walk, or a command can be starved by the eleven siblings
/// running beside it. Recording the duration and the number of git processes in
/// flight at spawn time separates the two without asking the user to reproduce
/// anything by hand.
void main() {
  late _RecordingSink sink;
  late AppLogger logger;

  setUp(() {
    sink = _RecordingSink();
    logger = AppLogger(sink: sink, level: LogLevel.debug);
  });

  test('warns with the duration when a command runs long', () async {
    final git = SystemGitService(
      gitBinary: '/bin/sleep',
      logger: logger,
      slowAfter: const Duration(milliseconds: 50),
    );

    await git.run(['0.2']);

    final line = sink.lines.single;
    expect(line, contains('WARN'));
    expect(line, contains('sleep 0.2'));
    expect(line, matches(RegExp(r'\d+ms')));
  });

  test('stays at debug for a command that returns promptly', () async {
    final git = SystemGitService(
      gitBinary: '/bin/echo',
      logger: logger,
      slowAfter: const Duration(seconds: 5),
    );

    await git.run(['hi']);

    expect(sink.lines.single, contains('DEBUG'));
  });

  test('records how many git processes were in flight', () async {
    final git = SystemGitService(
      gitBinary: '/bin/sleep',
      logger: logger,
      slowAfter: const Duration(milliseconds: 50),
      gate: ConcurrencyGate(4),
    );

    await Future.wait([
      git.run(['0.2']),
      git.run(['0.2']),
    ]);

    expect(sink.lines.any((l) => l.contains('2 in flight')), isTrue);
  });

  test(
    'logs the working directory so the slow repository is identifiable',
    () async {
      final git = SystemGitService(
        gitBinary: '/bin/echo',
        logger: logger,
        slowAfter: const Duration(seconds: 5),
      );

      final repo = Directory.systemTemp.createTempSync('mergelio_git_log');
      addTearDown(() => repo.deleteSync(recursive: true));

      await git.run(['hi'], repoPath: repo.path);

      expect(sink.lines.single, contains(repo.path));
    },
  );
}

class _RecordingSink implements LogSink {
  final List<String> lines = [];

  @override
  void write(String line) => lines.add(line);
}
