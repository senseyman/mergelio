import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lfs.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:path/path.dart' as p;

/// Scripts git by exact argument list and records each call together with
/// the busy lanes that were held while it ran.
class _FakeGit implements GitService {
  final calls = <List<String>>[];
  final lanesAtCall = <String, ({bool repo, bool fetch})>{};
  final responses = <String, GitResult>{};
  final stdins = <String, String?>{};
  late ProviderContainer container;
  Object? throwOnRun;
  final dirs = <String, String?>{};

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    final key = args.join(' ');
    stdins[key] = stdin;
    dirs[key] = repoPath;
    lanesAtCall[key] = (
      repo: container.read(busyProvider) != null,
      fetch: container.read(fetchBusyProvider) != null,
    );
    // The network environment probes config; nothing is configured.
    if (args.first == 'config') return const GitResult(1, '', '');
    if (args.first == 'lfs' && throwOnRun != null) throw throwOnRun!;
    return responses[key] ?? const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;

  Iterable<List<String>> get lfsAndGitCalls =>
      calls.where((c) => c.first != 'config');
}

void main() {
  late _FakeGit git;
  late InMemoryKeyValueStore kv;
  late ProviderContainer container;
  late RepoActions actions;

  setUp(() {
    git = _FakeGit();
    kv = InMemoryKeyValueStore();
    container = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(kv),
      ],
    );
    git.container = container;
    actions = container.read(repoActionsProvider('/r'));
    addTearDown(container.dispose);
  });

  int gen() => container.read(lfsGenerationProvider('/r'));
  List<String> toastTitles() =>
      container.read(toastProvider).map((t) => t.title).toList();
  List<List<String>> ran() => git.lfsAndGitCalls.toList();

  test('lfsFetchAll runs fetch --all on the fetch lane and bumps', () async {
    expect(gen(), 0);
    await actions.lfsFetchAll();
    expect(ran(), [
      ['lfs', 'fetch', '--all'],
    ]);
    final lanes = git.lanesAtCall['lfs fetch --all']!;
    expect(lanes.fetch, isTrue);
    expect(lanes.repo, isFalse);
    expect(gen(), 1);
  });

  test(
    'lfsDownloadFile pulls with an include and holds the repo lane',
    () async {
      await actions.lfsDownloadFile('b c.bin');
      expect(ran(), [
        ['lfs', 'pull', '--include=b c.bin'],
      ]);
      expect(git.lanesAtCall['lfs pull --include=b c.bin']!.repo, isTrue);
      expect(gen(), 1);
    },
  );

  test('lfsFetchObject fetches one path at a rev on the fetch lane', () async {
    await actions.lfsFetchObject('origin', 'abc^', 'art.psd');
    expect(ran(), [
      ['lfs', 'fetch', 'origin', 'abc^', '--include=art.psd'],
    ]);
    final lanes = git.lanesAtCall['lfs fetch origin abc^ --include=art.psd']!;
    expect(lanes.fetch, isTrue);
    expect(lanes.repo, isFalse);
  });

  test('lfsPull runs pull and bumps the generation on success', () async {
    await actions.lfsPull();
    expect(ran(), [
      ['lfs', 'pull'],
    ]);
    expect(toastTitles(), ['Pull LFS files complete']);
    expect(gen(), 1);
  });

  test(
    'a failing pull still bumps the generation and toasts the failure',
    () async {
      git.responses['lfs pull'] = const GitResult(2, '', 'smudge error');
      await actions.lfsPull();
      expect(gen(), 1);
      expect(toastTitles(), ['Pull LFS files failed']);
      expect(container.read(toastProvider).single.description, 'smudge error');
    },
  );

  test('a pull with no remote to reach says so, not the raw error', () async {
    git.responses['lfs pull'] = const GitResult(
      2,
      '',
      'batch request: missing protocol: ""\n'
          "Failed to fetch some objects from ''",
    );
    await actions.lfsPull();
    expect(
      container.read(toastProvider).single.description,
      'This repository has no remote to download LFS files from.',
    );
  });

  test('the operation is journaled', () async {
    await actions.lfsPull();
    final j = OperationJournal(kv, '/r');
    await j.load();
    expect(j.records.map((r) => r.label), contains('Pull LFS files'));
    expect(j.records.every((r) => r.status != OpStatus.pending), isTrue);
  });

  test(
    'lfsPrunePreview reports local minus retained, with no success toast',
    () async {
      git.responses['lfs prune --dry-run --verbose'] = const GitResult(
        0,
        '3 local objects, 1 retained, done.\n * <oid> (3.0 KB)\n',
        '',
      );
      final r = await actions.lfsPrunePreview();
      expect(r.completed, isTrue);
      expect(r.preview, const LfsPrunePreview(count: 2));
      expect(toastTitles(), isEmpty);
      expect(gen(), 1);
    },
  );

  test(
    'lfsPrunePreview with unreadable output yields a null preview',
    () async {
      git.responses['lfs prune --dry-run --verbose'] = const GitResult(
        0,
        'nothing recognisable',
        '',
      );
      final r = await actions.lfsPrunePreview();
      expect(r.completed, isTrue);
      expect(r.preview, isNull);
    },
  );

  test('lfsPrunePreview cancelled by the user is not completed', () async {
    git.throwOnRun = GitCancelledException('git lfs prune');
    final r = await actions.lfsPrunePreview();
    expect(r.completed, isFalse);
    expect(r.preview, isNull);
  });

  test('lfsPrunePreview skipped on a busy lane is not completed', () async {
    container.read(busyProvider.notifier).state = const BusyState('Other');
    final r = await actions.lfsPrunePreview();
    expect(r.completed, isFalse);
    expect(r.preview, isNull);
    expect(git.calls.where((c) => c.first == 'lfs'), isEmpty);
  });

  test(
    'lfsPrunePreview failure reports completed false and an error toast',
    () async {
      git.responses['lfs prune --dry-run --verbose'] = const GitResult(
        2,
        '',
        'boom',
      );
      final r = await actions.lfsPrunePreview();
      expect(r.completed, isFalse);
      expect(r.preview, isNull);
      final t = container.read(toastProvider).single;
      expect(t.kind, ToastKind.error);
    },
  );

  test('lfsTrack runs track, returns true, bumps, and adds nothing', () async {
    final ok = await actions.lfsTrack('*.psd');
    expect(ok, isTrue);
    expect(ran(), [
      ['lfs', 'track', '--', '*.psd'],
    ]);
    expect(ran().any((c) => c.first == 'add'), isFalse);
    expect(gen(), 1);
  });

  test(
    'lfsConvertCandidates keeps files whose filter attribute is lfs',
    () async {
      git.responses['ls-files -z'] = const GitResult(
        0,
        'a.psd\x00dir/b.psd\x00c.txt\x00',
        '',
      );
      git.responses['check-attr -z --stdin filter'] = const GitResult(
        0,
        'a.psd\x00filter\x00lfs\x00'
            'dir/b.psd\x00filter\x00lfs\x00'
            'c.txt\x00filter\x00unspecified\x00',
        '',
      );
      git.responses['lfs ls-files -l'] = const GitResult(
        0,
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa * a.psd\n',
        '',
      );
      final r = await actions.lfsConvertCandidates();
      expect(r, ['dir/b.psd']);
      expect(ran(), [
        ['ls-files', '-z'],
        ['check-attr', '-z', '--stdin', 'filter'],
        ['lfs', 'ls-files', '-l'],
      ]);
      expect(
        git.stdins['check-attr -z --stdin filter'],
        'a.psd\x00dir/b.psd\x00c.txt\x00',
      );
    },
  );

  test(
    'lfsConvertCandidates treats a bracketed filename as a plain file',
    () async {
      git.responses['ls-files -z'] = const GitResult(
        0,
        'dir/x [1].psd\x00b.txt\x00',
        '',
      );
      git.responses['check-attr -z --stdin filter'] = const GitResult(
        0,
        'dir/x [1].psd\x00filter\x00lfs\x00b.txt\x00filter\x00unspecified\x00',
        '',
      );
      git.responses['lfs ls-files -l'] = const GitResult(0, '', '');
      final r = await actions.lfsConvertCandidates();
      expect(r, ['dir/x [1].psd']);
      expect(ran().first, ['ls-files', '-z']);
    },
  );

  test('lfsConvert renormalizes on the repo lane, never commits', () async {
    final ok = await actions.lfsConvert(['dir/b.psd']);
    expect(ok, isTrue);
    expect(ran(), [
      ['add', '--renormalize', '--', 'dir/b.psd'],
      [
        'ls-files',
        '-z',
        '-m',
        '-o',
        '--exclude-standard',
        '--',
        ':(glob)**/.gitattributes',
      ],
    ]);
    expect(git.lanesAtCall['add --renormalize -- dir/b.psd']!.repo, isTrue);
    expect(container.read(busyProvider), isNull);
    expect(ran().any((c) => c.first == 'commit'), isFalse);
    expect(gen(), 1);
  });

  // Staged pointers without the rule that makes them pointers commit into a
  // repository that no longer knows those paths are LFS.
  test('lfsConvert also stages changed .gitattributes files', () async {
    git.responses['ls-files -z -m -o --exclude-standard -- '
        ':(glob)**/.gitattributes'] = const GitResult(
      0,
      'sub/.gitattributes\x00.gitattributes\x00',
      '',
    );
    expect(await actions.lfsConvert(['dir/b.psd']), isTrue);
    expect(ran(), [
      ['add', '--renormalize', '--', 'dir/b.psd'],
      [
        'ls-files',
        '-z',
        '-m',
        '-o',
        '--exclude-standard',
        '--',
        ':(glob)**/.gitattributes',
      ],
      ['add', '--', 'sub/.gitattributes', '.gitattributes'],
    ]);
    expect(ran().any((c) => c.first == 'commit'), isFalse);
  });

  test('lfsUntrack runs lfs untrack', () async {
    expect(await actions.lfsUntrack('*.psd', '.gitattributes'), isTrue);
    expect(ran(), [
      ['lfs', 'untrack', '--', '*.psd'],
      // Read back to confirm git-lfs really removed it.
      ['lfs', 'track'],
    ]);
    expect(git.dirs['lfs untrack -- *.psd'], '/r');
  });

  // git-lfs lists a nested pattern prefixed with its directory, but only
  // removes it when run in that directory with the pattern as written there.
  test('lfsUntrack of a nested pattern runs in its directory', () async {
    expect(
      await actions.lfsUntrack('sub/a/*.psd', 'sub/a/.gitattributes'),
      isTrue,
    );
    expect(ran(), [
      ['lfs', 'untrack', '--', '*.psd'],
      // Read back to confirm git-lfs really removed it.
      ['lfs', 'track'],
    ]);
    expect(git.dirs['lfs untrack -- *.psd'], p.join('/r', 'sub/a'));
  });

  group('lfsUntrack when git-lfs leaves the pattern in place', () {
    const escaped = r'x[[:space:]]\[1\].z';
    late Directory repo;
    late RepoActions local;

    setUp(() {
      // The repository sits inside a scratch root, so a path that climbs out
      // of it lands somewhere this test owns.
      final root = Directory.systemTemp.createTempSync('mergelio_untrack_');
      addTearDown(() => root.deleteSync(recursive: true));
      repo = Directory(p.join(root.path, 'repo'))..createSync();
      local = container.read(repoActionsProvider(repo.path));
    });

    String listing(String pattern, String source) =>
        'Listing tracked patterns\n    $pattern ($source)\n'
        'Listing excluded patterns\n';

    test('removes the line from its .gitattributes itself', () async {
      final attrs = File(p.join(repo.path, '.gitattributes'))
        ..writeAsStringSync(
          '*.txt text\n$escaped filter=lfs diff=lfs merge=lfs -text\n',
        );
      git.responses['lfs track'] = GitResult(
        0,
        listing(escaped, '.gitattributes'),
        '',
      );
      expect(await local.lfsUntrack(escaped, '.gitattributes'), isTrue);
      expect(attrs.readAsStringSync(), '*.txt text\n');
      expect(git.calls.where((c) => c.first == 'add'), isEmpty);
    });

    test(
      'edits a nested file, writing the pattern as that file does',
      () async {
        Directory(p.join(repo.path, 'sub')).createSync();
        final attrs = File(p.join(repo.path, 'sub', '.gitattributes'))
          ..writeAsStringSync('$escaped filter=lfs diff=lfs merge=lfs -text\n');
        git.responses['lfs track'] = GitResult(
          0,
          listing('sub/$escaped', 'sub/.gitattributes'),
          '',
        );
        expect(
          await local.lfsUntrack('sub/$escaped', 'sub/.gitattributes'),
          isTrue,
        );
        expect(attrs.readAsStringSync(), '');
      },
    );

    test('leaves the file alone when git-lfs did remove it', () async {
      final attrs = File(p.join(repo.path, '.gitattributes'))
        ..writeAsStringSync('*.psd filter=lfs diff=lfs merge=lfs -text\n');
      git.responses['lfs track'] = const GitResult(
        0,
        'Listing tracked patterns\nListing excluded patterns\n',
        '',
      );
      expect(await local.lfsUntrack('*.psd', '.gitattributes'), isTrue);
      expect(
        attrs.readAsStringSync(),
        '*.psd filter=lfs diff=lfs merge=lfs -text\n',
      );
    });

    test('reports failure when the line cannot be found either', () async {
      File(p.join(repo.path, '.gitattributes')).writeAsStringSync('');
      git.responses['lfs track'] = GitResult(
        0,
        listing(escaped, '.gitattributes'),
        '',
      );
      expect(await local.lfsUntrack(escaped, '.gitattributes'), isFalse);
      expect(
        container.read(toastProvider).map((t) => t.kind),
        contains(ToastKind.error),
      );
    });

    test('never edits a file outside the repository', () async {
      const line = '$escaped filter=lfs diff=lfs merge=lfs -text\n';
      final outside = File(p.join(repo.parent.path, '.gitattributes'))
        ..writeAsStringSync(line);
      git.responses['lfs track'] = GitResult(
        0,
        listing(escaped, '../.gitattributes'),
        '',
      );
      expect(await local.lfsUntrack(escaped, '../.gitattributes'), isFalse);
      expect(outside.readAsStringSync(), line);
    });
  });

  test('lfsUntrack keeps a nested pattern that lacks the prefix', () async {
    expect(await actions.lfsUntrack('*.psd', 'sub/.gitattributes'), isTrue);
    expect(ran(), [
      ['lfs', 'untrack', '--', '*.psd'],
      // Read back to confirm git-lfs really removed it.
      ['lfs', 'track'],
    ]);
    expect(git.dirs['lfs untrack -- *.psd'], p.join('/r', 'sub'));
  });

  test('lfsTrackFile tracks one exact filename', () async {
    expect(await actions.lfsTrackFile('dir/x [1].psd'), isTrue);
    expect(ran(), [
      ['lfs', 'track', '--filename', '--', 'dir/x [1].psd'],
    ]);
  });

  test('lfsTrackedPatterns parses the track listing', () async {
    git.responses['lfs track'] = const GitResult(
      0,
      'Listing tracked patterns\n    *.psd (.gitattributes)\nListing excluded patterns\n',
      '',
    );
    final r = await actions.lfsTrackedPatterns();
    expect(r, hasLength(1));
    expect(r.single.pattern, '*.psd');
  });

  test('lfsPrune runs prune on the repo lane', () async {
    await actions.lfsPrune();
    expect(ran(), [
      ['lfs', 'prune'],
    ]);
    expect(git.lanesAtCall['lfs prune']!.repo, isTrue);
  });

  test('a running fetch-lane op does not stop lfsTrack', () async {
    container.read(fetchBusyProvider.notifier).state = const BusyState('Fetch');
    expect(await actions.lfsTrack('*.psd'), isTrue);
    expect(ran(), [
      ['lfs', 'track', '--', '*.psd'],
    ]);
  });

  test('lfsInstallHooks installs locally; failure toasts stderr', () async {
    expect(await actions.lfsInstallHooks(), isTrue);
    expect(ran(), [
      ['lfs', 'install', '--local'],
    ]);

    git.responses['lfs install --local'] = const GitResult(
      2,
      '',
      'Hook already exists: pre-push',
    );
    expect(await actions.lfsInstallHooks(), isFalse);
    final t = container.read(toastProvider).last;
    expect(t.kind, ToastKind.error);
    expect(t.description, contains('Hook already exists: pre-push'));
    expect(gen(), 2);
  });

  test('local LFS ops refuse while another op holds the repo lane', () async {
    container.read(busyProvider.notifier).state = const BusyState('Other');
    expect(await actions.lfsTrack('*.psd'), isFalse);
    expect(await actions.lfsConvert(['a']), isFalse);
    expect(ran(), isEmpty);
    final t = container.read(toastProvider).last;
    expect(t.kind, ToastKind.warning);
    expect(t.title, 'An operation is already running');
  });

  test('lfsPull holds the repo lane while running and releases it', () async {
    await actions.lfsPull();
    final lanes = git.lanesAtCall['lfs pull']!;
    expect(lanes.repo, isTrue);
    expect(lanes.fetch, isFalse);
    expect(container.read(busyProvider), isNull);
  });

  test('lfsConvert is journaled', () async {
    await actions.lfsConvert(['dir/b.psd']);
    final j = OperationJournal(kv, '/r');
    await j.load();
    expect(j.records.map((r) => r.label), contains('Convert files to LFS'));
    expect(j.records.every((r) => r.status != OpStatus.pending), isTrue);
  });

  test('an empty file listing runs no check-attr', () async {
    git.responses['ls-files -z'] = const GitResult(0, '', '');
    expect(await actions.lfsConvertCandidates(), isEmpty);
    expect(git.calls.any((c) => c.first == 'check-attr'), isFalse);
  });
}
