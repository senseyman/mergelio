// Clone is the one network operation that runs before a repository exists, and
// it used to skip everything the others get: no ssh watchdog, no credential
// prompt, no way to give up on a dead host, no submodules.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/askpass.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/repo_bootstrap.dart';

class _FakeGit implements GitService {
  final List<List<String>> calls = [];
  final List<Map<String, String>?> envs = [];

  /// Called with the live cancel handle when `clone` starts, so a test can act
  /// as the user pressing Cancel mid-transfer.
  void Function(GitCancel cancel)? onClone;

  /// Files the clone leaves in the destination before it is given up on.
  String? partialFile;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
  }) async {
    calls.add(args);
    envs.add(environment);
    if (args.first != 'clone') return const GitResult(0, '', '');
    final target = args.last;
    if (partialFile != null) {
      Directory(target).createSync(recursive: true);
      File('$target/$partialFile').writeAsStringSync('half a repo');
    }
    if (cancel != null && onClone != null) {
      onClone!(cancel);
      if (cancel.isCancelled) {
        throw GitCancelledException('git clone cancelled');
      }
    }
    Directory(target).createSync(recursive: true);
    return const GitResult(0, '', '');
  }

  List<String>? get cloneArgs {
    for (final c in calls) {
      if (c.first == 'clone') return c;
    }
    return null;
  }

  Map<String, String>? get cloneEnv {
    for (var i = 0; i < calls.length; i++) {
      if (calls[i].first == 'clone') return envs[i];
    }
    return null;
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late Directory work;
  late _FakeGit git;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('mergelio_clone_');
    git = _FakeGit();
  });

  tearDown(() async {
    if (await work.exists()) await work.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(git)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('clone brings submodules up with the working tree', () async {
    await container()
        .read(repoBootstrapProvider)
        .clone(url: 'git@host:acme/repo.git', parentDir: work.path);

    expect(git.cloneArgs, contains('--recurse-submodules'));
  });

  test(
    'clone runs under the same network hardening as fetch and push',
    () async {
      await container()
          .read(repoBootstrapProvider)
          .clone(url: 'git@host:acme/repo.git', parentDir: work.path);

      final env = git.cloneEnv;
      expect(env?['GIT_SSH_COMMAND'], contains('ConnectTimeout=10'));
      expect(env?['GIT_TERMINAL_PROMPT'], '0');
    },
  );

  test('cloning over ssh can ask for a passphrase', () async {
    final before = askpassHelper;
    addTearDown(() => askpassHelper = before);
    askpassHelper = '/support/askpass.sh';

    await container()
        .read(repoBootstrapProvider)
        .clone(url: 'git@host:acme/repo.git', parentDir: work.path);

    expect(git.cloneEnv?['GIT_ASKPASS'], '/support/askpass.sh');
    expect(git.cloneEnv?['SSH_ASKPASS_REQUIRE'], 'force');
  });

  test('a running clone can be given up on', () async {
    final c = container();
    git.onClone = (_) => c.read(busyProvider)?.onCancel?.call();

    final path = await c
        .read(repoBootstrapProvider)
        .clone(url: 'git@host:acme/repo.git', parentDir: work.path);

    expect(path, isNull);
    expect(c.read(toastProvider).last.title, contains('cancelled'));
    // The lane is released, so the next clone is not refused.
    expect(c.read(busyProvider), isNull);
  });

  test('an abandoned clone leaves no half-repository behind', () async {
    final c = container();
    git
      ..partialFile = 'objects.pack'
      ..onClone = (cancel) => cancel.cancel();

    await c
        .read(repoBootstrapProvider)
        .clone(
          url: 'git@host:acme/repo.git',
          parentDir: work.path,
          folderName: 'repo',
        );

    expect(Directory('${work.path}/repo').existsSync(), isFalse);
  });

  test(
    'a destination the user had already made is emptied, not removed',
    () async {
      final c = container();
      Directory('${work.path}/repo').createSync();
      git
        ..partialFile = 'objects.pack'
        ..onClone = (cancel) => cancel.cancel();

      await c
          .read(repoBootstrapProvider)
          .clone(
            url: 'git@host:acme/repo.git',
            parentDir: work.path,
            folderName: 'repo',
          );

      expect(Directory('${work.path}/repo').existsSync(), isTrue);
      expect(Directory('${work.path}/repo').listSync(), isEmpty);
    },
  );
}
