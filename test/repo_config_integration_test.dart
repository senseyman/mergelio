import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/domain/git/repo_config.dart';

/// [SystemGitService] with the global config pointed at a scratch file and
/// the system config off, so `--global` reads and writes never touch the
/// developer's own `~/.gitconfig`.
class _ScratchGlobalGit implements GitService {
  final String globalFile;
  const _ScratchGlobalGit(this.globalFile);

  static const _inner = SystemGitService();

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => _inner.run(
    args,
    repoPath: repoPath,
    timeout: timeout,
    environment: {
      ...?environment,
      'GIT_CONFIG_GLOBAL': globalFile,
      'GIT_CONFIG_NOSYSTEM': '1',
    },
    cancel: cancel,
    stdin: stdin,
  );

  @override
  Future<String> version() => _inner.version();

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);
}

void main() {
  late Directory dir;
  late String repo;
  late String global;
  late GitService svc;

  Future<String> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_cfg_');
    repo = '${dir.path}/r';
    global = '${dir.path}/global';
    await File(global).writeAsString('');
    await Directory(repo).create();
    svc = _ScratchGlobalGit(global);
    await g(['init', '-q']);
  });

  tearDown(() => dir.delete(recursive: true));

  GitReader reader() => GitReader(svc, repo);
  GitWriter writer() => GitWriter(svc, repo);

  test('nothing set reads as empty', () async {
    expect((await reader().repoConfig()).entries, isEmpty);
  });

  test('reads every scope with its origin, local winning', () async {
    await g(['config', '--global', 'user.name', 'Glob Al']);
    await g(['config', '--global', 'pull.rebase', 'yes']);
    await g(['config', '--local', 'user.name', 'Lo Cal']);
    // Not one of the keys: never read.
    await g(['config', '--local', 'color.ui', 'auto']);
    final inc = '${dir.path}/with space/inc';
    await File(inc).create(recursive: true);
    await File(inc).writeAsString('[fetch]\n\tprune = true\n');
    await g(['config', '--local', 'include.path', inc]);

    final c = await reader().repoConfig();
    expect(c.effective('user.name')!.value, 'Lo Cal');
    expect(c.effective('user.name')!.scope, ConfigScope.local);
    expect(c.inScope('user.name', ConfigScope.global)!.value, 'Glob Al');
    expect(c.inScope('user.name', ConfigScope.global)!.origin, global);
    expect(c.effective('pull.rebase')!.value, 'yes');
    expect(c.effective('fetch.prune')!.origin, inc);
    expect(c.effective('fetch.prune')!.scope, ConfigScope.local);
    expect(c.entries.map((e) => e.key), isNot(contains('color.ui')));
  });

  test('a config git cannot read is an error', () async {
    await File('$repo/.git/config')
        .writeAsString('[broken\n', mode: FileMode.append);
    await expectLater(reader().repoConfig(), throwsA(isA<GitException>()));
  });

  group('setConfig', () {
    test('writes this repository unless told global', () async {
      await writer().setConfig('rerere.enabled', 'true');
      await writer().setConfig('pull.rebase', 'merges', global: true);
      expect(await g(['config', '--local', 'rerere.enabled']), 'true');
      expect(await g(['config', '--global', 'pull.rebase']), 'merges');
      expect(
        (await svc.run([
          'config',
          '--local',
          'pull.rebase',
        ], repoPath: repo)).ok,
        isFalse,
      );
    });

    test('writes over a key set more than once', () async {
      await g(['config', '--local', '--add', 'core.autocrlf', 'true']);
      await g(['config', '--local', '--add', 'core.autocrlf', 'false']);
      await writer().setConfig('core.autocrlf', 'input');
      expect(
        await g(['config', '--local', '--get-all', 'core.autocrlf']),
        'input',
      );
    });

    test('keeps spaces and quotes in a name', () async {
      await writer().setConfig('user.name', 'Ann "A" O\'Neil');
      expect(await g(['config', '--local', 'user.name']), 'Ann "A" O\'Neil');
    });

    test('a write git refuses is a GitException', () async {
      await File('$repo/.git/config')
          .writeAsString('[broken\n', mode: FileMode.append);
      await expectLater(
        writer().setConfig('rerere.enabled', 'true'),
        throwsA(isA<GitException>()),
      );
    });
  });

  group('unsetConfig', () {
    test('removes every value in the chosen scope only', () async {
      await g(['config', '--global', 'fetch.prune', 'true']);
      await g(['config', '--local', '--add', 'fetch.prune', 'false']);
      await g(['config', '--local', '--add', 'fetch.prune', 'true']);
      await writer().unsetConfig('fetch.prune');
      final c = await reader().repoConfig();
      expect(c.inScope('fetch.prune', ConfigScope.local), isNull);
      expect(c.effective('fetch.prune')!.scope, ConfigScope.global);

      await writer().unsetConfig('fetch.prune', global: true);
      expect((await reader().repoConfig()).effective('fetch.prune'), isNull);
    });

    test('a key that is not set is already unset', () async {
      await writer().unsetConfig('core.autocrlf');
      await writer().unsetConfig('core.autocrlf', global: true);
    });
  });
}
