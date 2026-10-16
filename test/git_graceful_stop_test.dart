import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';

/// A git stopped mid-write must leave the repository usable. SIGKILL gives git
/// no chance to drop its `index.lock`, and every later write then fails until
/// the user deletes the lock by hand; SIGTERM lets git clean up first.
void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  File lock() => File('${dir.path}/.git/index.lock');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_gracefulstop_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['config', 'commit.gpgsign', 'false']);
    // A filter of its own name, so the host's git-lfs setup cannot step in.
    await File('${dir.path}/.gitattributes')
        .writeAsString('*.bin filter=slow -text\n');
    await File('${dir.path}/f.txt').writeAsString('main\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    await g(['checkout', '-q', '-b', 'topic']);
    await File('${dir.path}/a.bin').writeAsString('blob\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'topic']);
    await g(['checkout', '-q', 'main']);
    await g(['config', 'filter.slow.clean', 'cat']);
    await g(['config', 'filter.slow.smudge', 'sleep 20; cat']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a cancelled checkout leaves no index.lock behind', () async {
    final cancel = GitCancel();
    final run = svc.run(
      ['checkout', 'topic'],
      repoPath: dir.path,
      cancel: cancel,
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    cancel.cancel();
    await expectLater(run, throwsA(isA<GitCancelledException>()));

    expect(lock().existsSync(), isFalse);
    await g(['config', 'filter.slow.smudge', 'cat']);
    await g(['checkout', '-q', 'topic']);
  });

  test('a timed-out checkout leaves no index.lock behind', () async {
    await expectLater(
      svc.run(
        ['checkout', 'topic'],
        repoPath: dir.path,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<GitException>()),
    );

    expect(lock().existsSync(), isFalse);
  });

  test('a child that ignores SIGTERM is still stopped', () async {
    final cancel = GitCancel();
    final p = await Process.start('sh', ['-c', 'trap "" TERM; sleep 30']);
    cancel.attach(p);
    // Let the shell install its trap before it is signalled.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    cancel.cancel();
    expect(await p.exitCode.timeout(const Duration(seconds: 10)), isNot(0));
  });
}
