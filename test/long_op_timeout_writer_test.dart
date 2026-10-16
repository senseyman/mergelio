import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/stash.dart';

/// Records the timeout and cancel handle each command was given, so the limit
/// a long operation gets can be checked without one slow enough to hit it.
class _RecordingGit implements GitService {
  final calls = <({List<String> args, Duration? timeout, GitCancel? cancel})>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add((args: args, timeout: timeout, cancel: cancel));
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late _RecordingGit git;
  late GitWriter w;

  setUp(() {
    git = _RecordingGit();
    w = GitWriter(git, '/r');
  });

  ({List<String> args, Duration? timeout, GitCancel? cancel}) only(
    String sub,
  ) => git.calls.singleWhere((c) => c.args.contains(sub));

  group('skips resume the rest of the sequence', () {
    final skips =
        <String, (Future<void> Function(GitWriter, GitCancel?), Duration)>{
          'rebase --skip': (
            (w, c) => w.rebaseSkip(cancel: c),
            GitWriter.rebaseSequenceTimeout,
          ),
          'cherry-pick --skip': (
            (w, c) => w.cherryPickSkip(cancel: c),
            GitWriter.pickSequenceTimeout,
          ),
          'revert --skip': (
            (w, c) => w.revertSkip(cancel: c),
            GitWriter.pickSequenceTimeout,
          ),
        };
    for (final MapEntry(key: name, value: (op, ceiling)) in skips.entries) {
      test('$name runs under the sequence ceiling and takes Cancel', () async {
        final cancel = GitCancel();
        await op(w, cancel);
        expect(git.calls.single.timeout, ceiling);
        expect(git.calls.single.cancel, same(cancel));
      });
    }
  });

  group('rebaseOnto', () {
    test('a signed one runs under the sequence ceiling', () async {
      final cancel = GitCancel();
      await w.rebaseOnto('main', sign: true, cancel: cancel);
      expect(only('rebase').timeout, GitWriter.rebaseSequenceTimeout);
      expect(only('rebase').cancel, same(cancel));
    });

    test('an unsigned one keeps the ordinary default', () async {
      await w.rebaseOnto('main');
      expect(only('rebase').timeout, isNull);
    });
  });

  test('a signed interactive rebase runs under the sequence ceiling', () async {
    await w.rebase('main', 'pick abc\n', sign: true);
    expect(only('rebase').timeout, GitWriter.rebaseSequenceTimeout);
  });

  group('checkout-like writes take the timeout their caller picks', () {
    const t = GitWriter.lfsTransferTimeout;

    test('checkout', () async {
      final cancel = GitCancel();
      await w.checkout('topic', timeout: t, cancel: cancel);
      expect(only('checkout').timeout, t);
      expect(only('checkout').cancel, same(cancel));
    });

    test('checkoutTracking', () async {
      final cancel = GitCancel();
      await w.checkoutTracking('origin', 'topic', timeout: t, cancel: cancel);
      expect(only('switch').timeout, t);
      expect(only('switch').cancel, same(cancel));
    });

    test('stashPush', () async {
      await w.stashPush(const StashPushOptions(), t);
      expect(only('stash').timeout, t);
    });

    test('and default to the ordinary one', () async {
      await w.checkout('topic');
      await w.checkoutTracking('origin', 'topic');
      await w.stashPush();
      expect(git.calls.map((c) => c.timeout), everyElement(isNull));
    });
  });
}
