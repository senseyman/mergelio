import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/concurrency.dart';
import 'package:mergelio/domain/git/git_service.dart';

/// Guards the two ways `SystemGitService` used to leak file descriptors on a
/// large repository: unbounded parallel subprocesses, and a child left waiting
/// on a stdin pipe that nobody closes.
void main() {
  test('serialises subprocesses beyond the concurrency limit', () async {
    final git = SystemGitService(
      gitBinary: '/bin/sleep',
      gate: ConcurrencyGate(1),
    );
    final started = DateTime.now();

    await Future.wait([
      git.run(['0.2']),
      git.run(['0.2']),
    ]);

    final elapsed = DateTime.now().difference(started);
    expect(elapsed, greaterThan(const Duration(milliseconds: 350)));
  });

  test('runs them together when the limit allows', () async {
    final git = SystemGitService(
      gitBinary: '/bin/sleep',
      gate: ConcurrencyGate(4),
    );
    final started = DateTime.now();

    await Future.wait([
      git.run(['0.2']),
      git.run(['0.2']),
    ]);

    final elapsed = DateTime.now().difference(started);
    expect(elapsed, lessThan(const Duration(milliseconds: 350)));
  });

  test('closes stdin so a child reading it can finish', () async {
    final git = SystemGitService(
      gitBinary: '/bin/cat',
      defaultTimeout: const Duration(seconds: 3),
    );

    final result = await git.run(const []);

    expect(result.exitCode, 0);
  });
}
