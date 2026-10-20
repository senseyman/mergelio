import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/external_tools.dart';
import 'package:mergelio/domain/git/external_git_tools.dart';
import 'package:mergelio/domain/git/git_service.dart';

import 'support/hermetic_git.dart';

/// git does the actual hand-off: it picks the tool, fills `$LOCAL`/`$MERGED`,
/// and stages a merge the tool reports as done. These run real git with a
/// shell one-liner standing in for the tool, so what git does on success and
/// failure is observed, not assumed.
void main() {
  late Directory dir;
  late String repo;
  late GitService svc;
  late ExternalGitTools tools;

  Future<String> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_ext_');
    repo = '${dir.path}/r';
    svc = const HermeticGit();
    await svc.run(['init', '-q', '-b', 'main', repo], repoPath: dir.path);
    await g(['config', 'user.name', 't']);
    await g(['config', 'user.email', 't@t']);
    await g(['config', 'commit.gpgsign', 'false']);
    tools = ExternalGitTools(svc, repo);
  });

  tearDown(() => dir.delete(recursive: true));

  Future<void> commitFile(String body, String msg) async {
    await File('$repo/f').writeAsString(body);
    await g(['add', 'f']);
    await g(['commit', '-qm', msg]);
  }

  /// Leaves `f` conflicted between main and `side`.
  Future<void> conflict() async {
    await commitFile('a\n', 'base');
    await g(['switch', '-qc', 'side']);
    await commitFile('b\n', 'side');
    await g(['switch', '-q', 'main']);
    await commitFile('c\n', 'main');
    final r = await svc.run(['merge', 'side'], repoPath: repo);
    expect(r.ok, isFalse);
  }

  test('reads the tool keys in effect, and nothing else', () async {
    expect(await tools.config(), isA<ExternalToolConfig>());
    expect((await tools.config()).values, isEmpty);
    await g(['config', 'merge.tool', 'bc']);
    await g(['config', 'diff.guiTool', 'meld']);
    await g(['config', 'mergetool.my.cmd', 'true']);
    await g(['config', 'user.name', 'x']);
    final c = await tools.config();
    expect(c.value('merge.tool'), 'bc');
    expect(c.value('diff.guitool'), 'meld');
    expect(c.value('mergetool.my.cmd'), 'true');
    expect(c.values.keys, isNot(contains('user.name')));
  });

  test('a broken config is an error, not "no tool"', () async {
    await File('$repo/.git/config').writeAsString('[broken');
    expect(tools.config, throwsA(isA<GitException>()));
  });

  test('diff base is the first parent, or the empty tree for a root', () async {
    await commitFile('a\n', 'one');
    final root = await g(['rev-parse', 'HEAD']);
    await commitFile('b\n', 'two');
    final head = await g(['rev-parse', 'HEAD']);
    expect(await tools.diffBase(head), root);
    expect(
      await tools.diffBase(root),
      '4b825dc642cb6eb9a060e54bf8d69288fbee4904',
    );
  });

  test('difftool hands git both sides of a commit', () async {
    await commitFile('a\n', 'one');
    await commitFile('b\n', 'two');
    final out = '${dir.path}/seen';
    await g([
      'config',
      'difftool.probe.cmd',
      'cat "\$LOCAL" "\$REMOTE" > "$out"',
    ]);
    await g(['config', 'diff.tool', 'probe']);
    final head = await g(['rev-parse', 'HEAD']);
    final r = await tools.difftool(
      difftoolArgs(path: 'f', from: await tools.diffBase(head), to: head),
    );
    expect(r.ok, isTrue, reason: r.err);
    expect(await File(out).readAsString(), 'a\nb\n');
  });

  test(
    'a merge tool that succeeds leaves the file staged, uncommitted',
    () async {
      await conflict();
      final head = await g(['rev-parse', 'HEAD']);
      await g(['config', 'merge.tool', 'take']);
      await g(['config', 'mergetool.take.cmd', 'cp "\$REMOTE" "\$MERGED"']);
      await g(['config', 'mergetool.take.trustExitCode', 'true']);
      await g(['config', 'mergetool.keepBackup', 'false']);

      final r = await tools.mergetool(mergetoolArgs('f'));

      expect(r.ok, isTrue, reason: r.err);
      expect(await g(['status', '--porcelain', '--', 'f']), 'M  f');
      expect(await File('$repo/f').readAsString(), 'b\n');
      // Still mid-merge: committing it is the user's move.
      expect(await g(['rev-parse', 'HEAD']), head);
      expect(File('$repo/.git/MERGE_HEAD').existsSync(), isTrue);
    },
  );

  test('a merge tool that fails leaves the conflict in place', () async {
    await conflict();
    await g(['config', 'merge.tool', 'nope']);
    await g(['config', 'mergetool.nope.cmd', 'exit 1']);
    await g(['config', 'mergetool.nope.trustExitCode', 'true']);

    final r = await tools.mergetool(mergetoolArgs('f'));

    expect(r.ok, isFalse);
    expect(await g(['status', '--porcelain', '--', 'f']), 'UU f');
  });

  test('an untrusted tool that left the file alone does not count', () async {
    await conflict();
    await g(['config', 'merge.tool', 'idle']);
    await g(['config', 'mergetool.idle.cmd', 'true']);

    // git would ask "Was the merge successful?" — stdin is closed, so no.
    final r = await tools.mergetool(mergetoolArgs('f'));

    expect(r.ok, isFalse);
    expect(await g(['status', '--porcelain', '--', 'f']), 'UU f');
  });
}
