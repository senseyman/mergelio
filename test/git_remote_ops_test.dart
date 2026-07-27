import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  GitReader reader() => GitReader(svc, dir.path);
  GitWriter writer() => GitWriter(svc, dir.path);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_remote_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('add, rename, retarget and remove a remote', () async {
    await writer().addRemote('upstream', 'https://example.com/u.git');
    expect(await reader().remotes(), ['upstream']);
    expect(await reader().remoteUrl('upstream'), 'https://example.com/u.git');

    await writer().renameRemote('upstream', 'fork');
    expect(await reader().remotes(), ['fork']);

    await writer().setRemoteUrl('fork', 'https://example.com/f.git');
    expect(await reader().remoteUrl('fork'), 'https://example.com/f.git');

    await writer().removeRemote('fork');
    expect(await reader().remotes(), isEmpty);
  });

  test('adding a name that already exists fails', () async {
    await writer().addRemote('origin', 'https://example.com/o.git');
    expect(
      () => writer().addRemote('origin', 'https://example.com/x.git'),
      throwsA(isA<GitException>()),
    );
  });

  test('removing an unknown remote fails', () async {
    expect(() => writer().removeRemote('nope'), throwsA(isA<GitException>()));
  });
}
