import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/models.dart';

/// Integration tests: build a real superproject + submodule with the system
/// `git` binary and drive them through GitReader / GitWriter.
void main() {
  const svc = SystemGitService();
  late Directory parent;
  late Directory child;

  Future<void> g(Directory d, List<String> a) async {
    final r = await svc.run(a, repoPath: d.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
  }

  Future<void> initRepo(Directory d) async {
    await g(d, ['init', '-q', '-b', 'main']);
    await g(d, ['config', 'user.email', 't@e.com']);
    await g(d, ['config', 'user.name', 'T']);
    await g(d, ['config', 'commit.gpgsign', 'false']);
  }

  setUp(() async {
    child = await Directory.systemTemp.createTemp('mergelio_subchild_');
    await initRepo(child);
    await File('${child.path}/c.txt').writeAsString('child\n');
    await g(child, ['add', '.']);
    await g(child, ['commit', '-q', '-m', 'child base']);

    parent = await Directory.systemTemp.createTemp('mergelio_subparent_');
    await initRepo(parent);
    // Local file:// submodules are blocked by default since git 2.38.
    await g(parent, ['config', 'protocol.file.allow', 'always']);
    await File('${parent.path}/p.txt').writeAsString('parent\n');
    await g(parent, ['add', '.']);
    await g(parent, ['commit', '-q', '-m', 'parent base']);
  });

  tearDown(() async {
    for (final d in [parent, child]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  GitReader reader() => GitReader(svc, parent.path);
  GitWriter writer() => GitWriter(svc, parent.path);

  // The FIRST clone of a file:// submodule requires the protocol allow flag on
  // the command line (a repo-local config is ignored for security). Production
  // clones real URLs, so the writer doesn't set it — the test does, for setup.
  Future<void> addSub() async {
    await g(parent, [
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'add',
      child.path,
      'sub',
    ]);
    await g(parent, ['commit', '-q', '-m', 'add sub']);
  }

  test('a repo with no submodules lists none', () async {
    expect(await reader().submodules(), isEmpty);
  });

  test('lists an added submodule, up to date', () async {
    await addSub();
    final subs = await reader().submodules();
    expect(subs, hasLength(1));
    final s = subs.single;
    expect(s.path, 'sub');
    expect(s.name, 'sub');
    expect(s.url, child.path);
    expect(s.status, SubmoduleStatus.upToDate);
    expect(s.sha, isNotEmpty);
  });

  test('deinit reports not-initialized; update --init restores it', () async {
    await addSub();

    await writer().submoduleDeinit('sub', force: true);
    expect(
      (await reader().submodules()).single.status,
      SubmoduleStatus.notInitialized,
    );

    // Re-init reuses .git/modules/sub, so no network clone is needed.
    await writer().submoduleUpdate(path: 'sub', init: true);
    expect(
      (await reader().submodules()).single.status,
      SubmoduleStatus.upToDate,
    );
  });

  test('remove drops the submodule entirely', () async {
    await addSub();
    await writer().submoduleRemove('sub');
    expect(await reader().submodules(), isEmpty);
  });

  test('status char maps to the right enum', () {
    expect(submoduleStatusFromChar('-'), SubmoduleStatus.notInitialized);
    expect(submoduleStatusFromChar(' '), SubmoduleStatus.upToDate);
    expect(submoduleStatusFromChar('+'), SubmoduleStatus.newCommits);
    expect(submoduleStatusFromChar('U'), SubmoduleStatus.conflict);
  });
}
