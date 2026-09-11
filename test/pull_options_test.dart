import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/domain/git/git_writer.dart';

/// Records argument lists and reports success, so flag composition can be
/// asserted without touching a network.
class _CapturingGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}

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
    bare = await Directory.systemTemp.createTemp('mergelio_pullbare_');
    await run(bare, ['init', '--bare', '-q', '-b', 'main']);

    local = await Directory.systemTemp.createTemp('mergelio_pulllocal_');
    await run(local, ['init', '-q', '-b', 'main']);
    await configure(local);
    await File('${local.path}/a.txt').writeAsString('one\ntwo\nthree\n');
    await run(local, ['add', '.']);
    await run(local, ['commit', '-q', '-m', 'first']);
    await run(local, ['remote', 'add', 'origin', bare.path]);
    await run(local, ['push', '-q', '-u', 'origin', 'main']);

    // A second clone used to move the remote ahead.
    other = await Directory.systemTemp.createTemp('mergelio_pullother_');
    await run(other, ['clone', '-q', bare.path, '.']);
    await configure(other);
    await File('${other.path}/a.txt').writeAsString('ONE\ntwo\nthree\n');
    await run(other, ['add', '.']);
    await run(other, ['commit', '-q', '-m', 'remote work']);
    await run(other, ['push', '-q']);
  });

  tearDown(() async {
    for (final d in [bare, local, other]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  GitWriter writer() => GitWriter(svc, local.path);

  test('autostash pulls over a dirty tree and restores the edit', () async {
    // Local edits a file the incoming commit also touches, on another line.
    await File('${local.path}/a.txt').writeAsString('one\ntwo\nTHREE\n');

    // Without autostash git refuses rather than overwrite the local change.
    await expectLater(writer().pull(), throwsA(isA<GitException>()));

    await writer().pull(autostash: true);

    expect(
      await File('${local.path}/a.txt').readAsString(),
      'ONE\ntwo\nTHREE\n',
      reason: 'incoming change merged, local edit restored on top',
    );
    expect(
      (await svc.run(['log', '--oneline'], repoPath: local.path)).stdout,
      contains('remote work'),
    );
  });

  test('ff-only refuses to merge when history has diverged', () async {
    await writeCommit(local, 'c.txt', 'local work');
    await run(local, ['fetch', '-q']);

    await expectLater(
      writer().pull(ffOnly: true),
      throwsA(isA<GitException>()),
    );

    // HEAD stayed put: no merge commit was made behind the user's back.
    final head = (await svc.run([
      'log',
      '-1',
      '--format=%s',
    ], repoPath: local.path)).out;
    expect(head, 'local work');
  });

  test('ff-only fast-forwards a branch with no commits of its own', () async {
    await writer().pull(ffOnly: true);
    expect(
      (await svc.run(['log', '-1', '--format=%s'], repoPath: local.path)).out,
      'remote work',
    );
  });

  test('flags are passed through in one pull invocation', () async {
    final git = _CapturingGit();
    await GitWriter(
      git,
      '/repo',
    ).pull(rebase: true, ffOnly: true, autostash: true);
    // _net resolves the network environment first, so filter to the pull.
    expect(git.calls.where((c) => c.first == 'pull').single, [
      'pull',
      '--rebase',
      '--ff-only',
      '--autostash',
    ]);
  });

  test('a plain pull passes no options', () async {
    final git = _CapturingGit();
    await GitWriter(git, '/repo').pull();
    expect(git.calls.where((c) => c.first == 'pull').single, ['pull']);
  });

  group('preferences decide the flags a plain pull carries', () {
    test('the merge strategy pulls without --rebase', () {
      const s = AppSettings();
      expect(pullDefaults(s).rebase, isFalse);
      expect(pullDefaults(s).autostash, isTrue);
    });

    test('the rebase strategy pulls with --rebase', () {
      expect(
        pullDefaults(const AppSettings(pullStrategy: 'rebase')).rebase,
        isTrue,
      );
    });

    test('autostash can be turned off', () {
      expect(
        pullDefaults(const AppSettings(pullAutostash: false)).autostash,
        isFalse,
      );
    });
  });
}
