import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/in_flight_git.dart';

class _GatedGit implements GitService {
  final gates = <Completer<GitResult>>[];
  final seen = <(List<String>, String?, Duration?, String?)>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) {
    seen.add((args, repoPath, timeout, stdin));
    final gate = Completer<GitResult>();
    gates.add(gate);
    return gate.future;
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => path == '/r';
}

/// Telling "an action is between two git commands" from "an action is done"
/// needs a count of the commands it has running.
void main() {
  test('counts commands from start to finish', () async {
    final inner = _GatedGit();
    final git = InFlightGit(inner);
    expect(git.inFlight, 0);

    final a = git.run(['status']);
    final b = git.run(['log']);
    expect(git.inFlight, 2);

    inner.gates[0].complete(const GitResult(0, '', ''));
    await a;
    expect(git.inFlight, 1);
    inner.gates[1].complete(const GitResult(0, '', ''));
    await b;
    expect(git.inFlight, 0);
  });

  test('a command that throws still stops counting', () async {
    final inner = _GatedGit();
    final git = InFlightGit(inner);
    final run = git.run(['fetch']);
    inner.gates.single.completeError(GitException('boom'));
    await expectLater(run, throwsA(isA<GitException>()));
    expect(git.inFlight, 0);
  });

  test('passes every argument through untouched', () async {
    final inner = _GatedGit();
    final git = InFlightGit(inner);
    final run = git.run(
      ['commit', '-F', '-'],
      repoPath: '/r',
      timeout: const Duration(seconds: 7),
      stdin: 'msg',
    );
    inner.gates.single.complete(const GitResult(0, 'out', 'err'));
    final r = await run;
    expect(r.stdout, 'out');
    final (args, repoPath, timeout, stdin) = inner.seen.single;
    expect(args, ['commit', '-F', '-']);
    expect(repoPath, '/r');
    expect(timeout, const Duration(seconds: 7));
    expect(stdin, 'msg');
    expect(await git.isRepository('/r'), isTrue);
    expect(await git.version(), 'git version 2');
  });

  test(
    'commands started inside uncounted are not counted, even nested',
    () async {
      final inner = _GatedGit();
      final git = InFlightGit(inner);
      final run = InFlightGit.uncounted(() async {
        final first = git.run(['fetch']);
        // Still inside after an await.
        await Future<void>.delayed(Duration.zero);
        final second = git.run(['fetch', 'origin']);
        return Future.wait([first, second]);
      });
      await Future<void>.delayed(Duration.zero);
      expect(inner.gates, hasLength(2));
      expect(git.inFlight, 0);

      // A command outside, started meanwhile, is still counted.
      final outside = git.run(['status']);
      expect(git.inFlight, 1);

      for (final g in inner.gates) {
        g.complete(const GitResult(0, '', ''));
      }
      await run;
      await outside;
      expect(git.inFlight, 0);
    },
  );
}
