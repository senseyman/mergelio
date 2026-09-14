import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// End-to-end network ops against a local bare "remote".
void main() {
  late Directory bare;
  late Directory mirror;
  late Directory local;
  late Directory other;
  const svc = SystemGitService();

  Future<void> run(Directory d, List<String> args) async {
    final r = await svc.run(args, repoPath: d.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<void> configure(Directory d) async {
    await run(d, ['config', 'user.email', 't@example.com']);
    await run(d, ['config', 'user.name', 'Tester']);
    await run(d, ['config', 'commit.gpgsign', 'false']);
  }

  Future<void> writeCommit(Directory d, String file, String msg) async {
    await File('${d.path}/$file').writeAsString('$msg\n');
    await run(d, ['add', '.']);
    await run(d, ['commit', '-q', '-m', msg]);
  }

  setUp(() async {
    bare = await Directory.systemTemp.createTemp('mergelio_bare_');
    await run(bare, ['init', '--bare', '-q', '-b', 'main']);

    // A second remote, so "push to the remote I picked" is distinguishable
    // from "push to the upstream".
    mirror = await Directory.systemTemp.createTemp('mergelio_mirror_');
    await run(mirror, ['init', '--bare', '-q', '-b', 'main']);

    local = await Directory.systemTemp.createTemp('mergelio_local_');
    await run(local, ['init', '-q', '-b', 'main']);
    await configure(local);
    await writeCommit(local, 'a.txt', 'first');
    await run(local, ['remote', 'add', 'origin', bare.path]);
    await run(local, ['remote', 'add', 'mirror', mirror.path]);
    await run(local, ['push', '-q', '-u', 'origin', 'main']);

    // A second clone used to advance the remote for fetch/pull tests.
    other = await Directory.systemTemp.createTemp('mergelio_other_');
    await run(other, ['clone', '-q', bare.path, '.']);
    await configure(other);
  });

  tearDown(() async {
    for (final d in [bare, mirror, local, other]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  GitReader reader() => GitReader(svc, local.path);
  GitWriter writer() => GitWriter(svc, local.path);

  test('push sends local commits and clears ahead', () async {
    await writeCommit(local, 'b.txt', 'second');
    expect(reader().branches().then((b) => b.single.ahead), completion(1));

    await writer().push();
    final branch = (await reader().branches()).single;
    expect(branch.ahead, 0);

    // The bare remote now has the second commit.
    final remoteLog = (await svc.run([
      'log',
      '--oneline',
    ], repoPath: bare.path)).stdout;
    expect(remoteLog, contains('second'));
  });

  test('push publishes a new branch that has no upstream', () async {
    await run(local, ['checkout', '-q', '-b', 'feature']);
    await writeCommit(local, 'f.txt', 'feature work');

    // No upstream yet — push must set one instead of failing.
    await writer().push();

    final upstream = await svc.run([
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{u}',
    ], repoPath: local.path);
    expect(upstream.out, 'origin/feature');
    final remoteBranches = (await svc.run([
      'branch',
    ], repoPath: bare.path)).stdout;
    expect(remoteBranches, contains('feature'));
  });

  test('reads a remote URL and prunes without error', () async {
    final r = GitReader(svc, local.path);
    expect(await r.remoteUrl('origin'), bare.path);
    // Prune is a no-op here but must succeed.
    await writer().pruneRemote('origin');
  });

  test('fetch updates behind when the remote advanced', () async {
    await writeCommit(other, 'c.txt', 'remote work');
    await run(other, ['push', '-q', 'origin', 'main']);

    await writer().fetch(remote: 'origin');
    final branch = (await reader().branches()).single;
    expect(branch.behind, 1);
    expect(branch.ahead, 0);
  });

  test('pull brings the remote commit into the working tree', () async {
    await writeCommit(other, 'c.txt', 'remote work');
    await run(other, ['push', '-q', 'origin', 'main']);

    await writer().pull();
    expect(File('${local.path}/c.txt').existsSync(), isTrue);
    final branch = (await reader().branches()).single;
    expect(branch.behind, 0);
  });

  test('push to a chosen remote leaves the upstream alone', () async {
    await writeCommit(local, 'b.txt', 'second');

    await writer().push(remote: 'mirror');

    expect(
      (await svc.run(['log', '--oneline'], repoPath: mirror.path)).stdout,
      contains('second'),
    );
    // Picking a remote for one push must not publish to, or re-point at, the
    // upstream.
    expect(
      (await svc.run(['log', '--oneline'], repoPath: bare.path)).stdout,
      isNot(contains('second')),
    );
    final upstream = await svc.run([
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      '@{u}',
    ], repoPath: local.path);
    expect(upstream.out, 'origin/main');
  });

  test('force-pushing to a chosen remote that has no tracking ref', () async {
    await writeCommit(local, 'b.txt', 'second');

    // The dialog offers force and a remote together, so the combination has to
    // work on a remote this branch has never been pushed to. Creating the ref
    // breaks no lease, so it goes through.
    await writer().push(force: true, remote: 'mirror');

    expect(
      (await svc.run(['log', '--oneline'], repoPath: mirror.path)).stdout,
      contains('second'),
    );
  });

  test(
    'force-push is refused when the chosen remote holds unseen work',
    () async {
      // Someone else advanced the mirror, and this clone has never fetched it,
      // so there is no tracking ref to lease against. --force-with-lease must
      // refuse rather than discard work it cannot account for.
      final third = await Directory.systemTemp.createTemp('mergelio_third_');
      addTearDown(() async {
        if (await third.exists()) await third.delete(recursive: true);
      });
      await run(third, ['clone', '-q', mirror.path, '.']);
      await configure(third);
      await writeCommit(third, 'theirs.txt', 'their work');
      await run(third, ['push', '-q', 'origin', 'main']);

      await writeCommit(local, 'mine.txt', 'my work');

      expect(
        writer().push(force: true, remote: 'mirror'),
        throwsA(isA<GitException>()),
      );
    },
  );

  test('push --tags publishes tags to the remote', () async {
    await run(local, ['tag', 'v1.0']);

    await writer().push(tags: true);

    expect(
      (await svc.run(['tag'], repoPath: bare.path)).stdout,
      contains('v1.0'),
    );
  });

  test('push to a chosen remote refuses a detached HEAD', () async {
    final sha = (await svc.run([
      'rev-parse',
      'HEAD',
    ], repoPath: local.path)).out;
    await run(local, ['checkout', '-q', sha]);

    expect(writer().push(remote: 'mirror'), throwsA(isA<GitException>()));
  });

  test(
    'deleting a remote tag spares the local tag and a same-named branch',
    () async {
      await run(local, ['branch', 'v9']);
      await run(local, ['tag', 'v9']);
      await run(local, ['push', '-q', 'origin', 'refs/heads/v9:refs/heads/v9']);
      await run(local, ['push', '-q', 'origin', 'refs/tags/v9:refs/tags/v9']);

      await writer().deleteRemoteTag('v9');

      // The fully-qualified refspec is what keeps the branch out of it.
      final remoteRefs = (await svc.run([
        'for-each-ref',
        '--format=%(refname)',
      ], repoPath: bare.path)).stdout;
      expect(remoteRefs, isNot(contains('refs/tags/v9')));
      expect(remoteRefs, contains('refs/heads/v9'));
      expect(await reader().tags(), contains('v9'));
    },
  );
}
