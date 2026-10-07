import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/dashboard.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

void main() {
  late Directory root;
  late String remote;
  late String clone;
  late String other;
  const svc = SystemGitService();

  Future<String> g(String repo, List<String> args) async {
    final r = await svc.run(args, repoPath: repo);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  Future<void> identity(String repo) async {
    await g(repo, ['config', 'user.email', 't@e.com']);
    await g(repo, ['config', 'user.name', 'T']);
    await g(repo, ['config', 'commit.gpgsign', 'false']);
  }

  Future<void> commit(String repo, String path, String body) async {
    await File('$repo/$path').writeAsString(body);
    await g(repo, ['add', '-A']);
    await g(repo, ['commit', '-q', '-m', 'c $path']);
  }

  // A bare remote, a clone tracking it, and a second clone used to move the
  // remote forward.
  setUp(() async {
    root = await Directory.systemTemp.createTemp('mergelio_dash_');
    remote = '${root.path}/remote.git';
    clone = '${root.path}/clone';
    other = '${root.path}/other';
    await Directory(remote).create();
    await g(remote, ['init', '-q', '--bare', '-b', 'main']);
    await g(root.path, ['clone', '-q', remote, clone]);
    await identity(clone);
    await g(clone, ['checkout', '-q', '-b', 'main']);
    await commit(clone, 'a.txt', 'one\n');
    await g(clone, ['push', '-q', '-u', 'origin', 'main']);
    await g(root.path, ['clone', '-q', remote, other]);
    await identity(other);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('a clean tracked clone reads up to date with no op', () async {
    final s = await GitReader(svc, clone).snapshot();
    expect(s.summary.branch, 'main');
    expect(s.summary.upstream, 'origin/main');
    expect(s.summary.upstreamGone, isFalse);
    expect(s.summary.ahead, 0);
    expect(s.summary.behind, 0);
    expect(s.stashCount, 0);
    expect(s.op, isNull);
    expect(pullSkipReason(s), PullSkip.upToDate);
  });

  test('counts behind after a fetch and the fetch time', () async {
    await commit(other, 'b.txt', 'bee\n');
    await g(other, ['push', '-q']);
    await g(clone, ['fetch', '-q']);
    final s = await GitReader(svc, clone).snapshot();
    expect(s.summary.behind, 1);
    expect(s.lastFetch, isNotNull);
    expect(DateTime.now().difference(s.lastFetch!).inMinutes, lessThan(5));
    expect(pullSkipReason(s), isNull);
  });

  test('reads dirty, untracked and stash counts', () async {
    await File('$clone/a.txt').writeAsString('changed\n');
    await g(clone, ['stash', '-q']);
    await File('$clone/a.txt').writeAsString('changed again\n');
    await g(clone, ['stash', '-q']);
    await File('$clone/a.txt').writeAsString('dirty\n');
    await File('$clone/new.txt').writeAsString('n\n');
    final s = await GitReader(svc, clone).snapshot();
    expect(s.stashCount, 2);
    expect(s.summary.changed, 1);
    expect(s.summary.untracked, 1);
  });

  test('an upstream deleted on the remote reads gone after a prune', () async {
    await g(clone, ['checkout', '-q', '-b', 'topic']);
    await g(clone, ['push', '-q', '-u', 'origin', 'topic']);
    await g(other, ['push', '-q', 'origin', '--delete', 'topic']);
    await g(clone, ['fetch', '-q', '--prune']);
    final s = await GitReader(svc, clone).snapshot();
    expect(s.summary.upstream, 'origin/topic');
    expect(s.summary.upstreamGone, isTrue);
    expect(pullSkipReason(s), PullSkip.upstreamGone);
  });

  test('a conflicted merge reads as a merge in progress', () async {
    await commit(other, 'a.txt', 'theirs\n');
    await g(other, ['push', '-q']);
    await commit(clone, 'a.txt', 'ours\n');
    await g(clone, ['fetch', '-q']);
    await svc.run(['merge', 'origin/main'], repoPath: clone);
    final s = await GitReader(svc, clone).snapshot();
    expect(s.op, RepoOp.merge);
    expect(s.summary.conflicted, 1);
    expect(pullSkipReason(s), PullSkip.operation);
  });

  test('state files resolve inside a linked worktree', () async {
    final wt = '${root.path}/wt';
    await g(clone, ['worktree', 'add', '-q', '-b', 'side', wt]);
    await File('$wt/a.txt').writeAsString('s\n');
    await g(wt, ['stash', '-q']);
    final s = await GitReader(svc, wt).snapshot();
    expect(s.summary.branch, 'side');
    // The stash reflog is shared with the main worktree.
    expect(s.stashCount, 1);
    expect(s.op, isNull);
  });

  test('a folder that is not a repository throws', () async {
    final plain = await Directory('${root.path}/plain').create();
    expect(
      () => GitReader(svc, plain.path).snapshot(),
      throwsA(isA<GitException>()),
    );
  });

  test('pullFastForward moves a behind branch and never merges', () async {
    await commit(other, 'b.txt', 'bee\n');
    await g(other, ['push', '-q']);
    // A rebase preference must not turn the pull into a rebase.
    await g(clone, ['config', 'pull.rebase', 'true']);
    await GitWriter(svc, clone).pullFastForward();
    expect(
      await g(clone, ['rev-parse', 'HEAD']),
      await g(other, ['rev-parse', 'HEAD']),
    );
  });

  test('pullFastForward refuses a diverged branch', () async {
    await commit(other, 'b.txt', 'bee\n');
    await g(other, ['push', '-q']);
    await commit(clone, 'c.txt', 'see\n');
    final before = await g(clone, ['rev-parse', 'HEAD']);
    await expectLater(
      GitWriter(svc, clone).pullFastForward(),
      throwsA(isA<GitException>()),
    );
    expect(await g(clone, ['rev-parse', 'HEAD']), before);
  });
}
