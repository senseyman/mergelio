import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// End-to-end network ops against a local bare "remote".
void main() {
  late Directory bare;
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

    local = await Directory.systemTemp.createTemp('mergelio_local_');
    await run(local, ['init', '-q', '-b', 'main']);
    await configure(local);
    await writeCommit(local, 'a.txt', 'first');
    await run(local, ['remote', 'add', 'origin', bare.path]);
    await run(local, ['push', '-q', '-u', 'origin', 'main']);

    // A second clone used to advance the remote for fetch/pull tests.
    other = await Directory.systemTemp.createTemp('mergelio_other_');
    await run(other, ['clone', '-q', bare.path, '.']);
    await configure(other);
  });

  tearDown(() async {
    for (final d in [bare, local, other]) {
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
}
