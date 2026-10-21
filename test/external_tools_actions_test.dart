import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/external_tools.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/external_tools.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/merge_session.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

import 'support/hermetic_git.dart';

class _RecordingLauncher implements ExternalLauncher {
  final calls = <(String, List<String>)>[];
  ProcessResult result = ProcessResult(1, 0, '', '');
  ProcessException? failure;

  @override
  Future<ProcessResult> run(String executable, List<String> args) async {
    calls.add((executable, args));
    if (failure != null) throw failure!;
    return result;
  }
}

/// Every git command the actions ran, so a test can prove what was never
/// asked of git — no commit, no continue.
class _LoggingGit implements GitService {
  final log = <List<String>>[];
  static const _inner = HermeticGit();

  /// Runs after each command, before its result is handed back: a stand-in
  /// for the user acting while git is busy.
  void Function(List<String> args)? afterRun;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    log.add(args);
    final r = await _inner.run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
      stdin: stdin,
    );
    afterRun?.call(args);
    return r;
  }

  @override
  Future<String> version() => _inner.version();

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);
}

void main() {
  late Directory dir;
  late String repo;
  late _LoggingGit git;
  late _RecordingLauncher launcher;
  late ProviderContainer c;

  Future<String> g(List<String> args) async {
    final r = await const HermeticGit().run(args, repoPath: repo);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  Future<void> commitFile(String name, String body, String msg) async {
    await File('$repo/$name').writeAsString(body);
    await g(['add', name]);
    await g(['commit', '-qm', msg]);
  }

  ProviderContainer container({String editor = ''}) {
    final c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        externalLauncherProvider.overrideWithValue(launcher),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            AppSettings(editorCommand: editor),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  RepoActions actions() => c.read(repoActionsProvider(repo));
  List<Toast> toasts() => c.read(toastProvider);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_extact_');
    repo = '${dir.path}/r';
    await const HermeticGit().run([
      'init',
      '-q',
      '-b',
      'main',
      repo,
    ], repoPath: dir.path);
    await g(['config', 'user.name', 't']);
    await g(['config', 'user.email', 't@t']);
    await g(['config', 'commit.gpgsign', 'false']);
    git = _LoggingGit();
    launcher = _RecordingLauncher();
    c = container();
  });

  tearDown(() => dir.delete(recursive: true));

  group('openInEditor', () {
    test('the platform opener gets the absolute path', () async {
      await commitFile('a.txt', 'x\n', 'one');
      await actions().openInEditor('a.txt');
      final (exe, args) = launcher.calls.single;
      expect(exe, Platform.isMacOS ? 'open' : isNotEmpty);
      expect(args, ['$repo/a.txt']);
      expect(toasts(), isEmpty);
    });

    test('the configured command gets file and line', () async {
      c = container(editor: 'code -g {file}:{line}');
      await commitFile('a.txt', 'x\n', 'one');
      await actions().openInEditor('a.txt', line: 7);
      expect(launcher.calls.single.$1, 'code');
      expect(launcher.calls.single.$2, ['-g', '$repo/a.txt:7']);
    });

    test('a file not on disk is a warning, nothing starts', () async {
      await actions().openInEditor('gone.txt');
      expect(launcher.calls, isEmpty);
      expect(toasts().single.kind, ToastKind.warning);
      expect(toasts().single.title, contains('gone.txt'));
    });

    test('a command that does not split is an error, nothing starts', () async {
      c = container(editor: 'code "{file}');
      await commitFile('a.txt', 'x\n', 'one');
      await actions().openInEditor('a.txt');
      expect(launcher.calls, isEmpty);
      expect(toasts().single.kind, ToastKind.error);
    });

    test('a program that cannot start is reported by name', () async {
      c = container(editor: 'nope {file}');
      launcher.failure = const ProcessException('nope', [], 'not found', 2);
      await commitFile('a.txt', 'x\n', 'one');
      await actions().openInEditor('a.txt');
      expect(toasts().single.kind, ToastKind.error);
      expect(toasts().single.title, contains('nope'));
      expect(toasts().single.description, 'not found');
    });

    test('a non-zero exit is reported with its stderr', () async {
      c = container(editor: 'ed {file}');
      launcher.result = ProcessResult(1, 4, '', 'bad file\n');
      await commitFile('a.txt', 'x\n', 'one');
      await actions().openInEditor('a.txt');
      expect(toasts().single.kind, ToastKind.error);
      expect(toasts().single.description, 'bad file');
    });
  });

  group('openDifftool', () {
    late String seen;

    setUp(() async {
      seen = '${dir.path}/seen';
      await g([
        'config',
        'difftool.probe.cmd',
        'cat "\$LOCAL" "\$REMOTE" > "$seen"',
      ]);
    });

    test('with no tool set it warns and runs nothing', () async {
      await commitFile('f', 'a\n', 'one');
      await File('$repo/f').writeAsString('b\n');
      await actions().openDifftool(DiffTarget(repoPath: repo, path: 'f'));
      expect(git.log.where((a) => a.first == 'difftool'), isEmpty);
      expect(toasts().single.kind, ToastKind.warning);
    });

    test('a terminal-only builtin warns and runs nothing', () async {
      await g(['config', 'diff.tool', 'vimdiff']);
      await commitFile('f', 'a\n', 'one');
      await File('$repo/f').writeAsString('b\n');
      await actions().openDifftool(DiffTarget(repoPath: repo, path: 'f'));
      expect(git.log.where((a) => a.first == 'difftool'), isEmpty);
      expect(toasts().single.title, contains('vimdiff'));
    });

    test('an unstaged change: index against working tree', () async {
      await g(['config', 'diff.tool', 'probe']);
      await commitFile('f', 'a\n', 'one');
      await File('$repo/f').writeAsString('b\n');
      await actions().openDifftool(DiffTarget(repoPath: repo, path: 'f'));
      expect(await File(seen).readAsString(), 'a\nb\n');
      expect(toasts(), isEmpty);
    });

    test('a staged change: HEAD against the index', () async {
      await g(['config', 'diff.tool', 'probe']);
      await commitFile('f', 'a\n', 'one');
      await File('$repo/f').writeAsString('b\n');
      await g(['add', 'f']);
      await File('$repo/f').writeAsString('c\n');
      await actions().openDifftool(
        DiffTarget(repoPath: repo, path: 'f', staged: true),
      );
      expect(await File(seen).readAsString(), 'a\nb\n');
    });

    test('a commit against its parent, and a root commit', () async {
      await g(['config', 'diff.tool', 'probe']);
      await commitFile('f', 'a\n', 'one');
      final root = await g(['rev-parse', 'HEAD']);
      await commitFile('f', 'b\n', 'two');
      final head = await g(['rev-parse', 'HEAD']);

      await actions().openDifftool(
        DiffTarget(repoPath: repo, path: 'f', commitSha: head),
      );
      expect(await File(seen).readAsString(), 'a\nb\n');

      await actions().openDifftool(
        DiffTarget(repoPath: repo, path: 'f', commitSha: root),
      );
      expect(await File(seen).readAsString(), 'a\n');
    });

    test('a comparison uses its base revision', () async {
      await g(['config', 'diff.tool', 'probe']);
      await commitFile('f', 'a\n', 'one');
      final base = await g(['rev-parse', 'HEAD']);
      await commitFile('f', 'b\n', 'two');
      await commitFile('f', 'c\n', 'three');
      final head = await g(['rev-parse', 'HEAD']);
      await actions().openDifftool(
        DiffTarget(repoPath: repo, path: 'f', commitSha: head, baseRev: base),
      );
      expect(await File(seen).readAsString(), 'a\nc\n');
    });

    test('diff.guitool is honoured with --gui', () async {
      await g(['config', 'diff.tool', 'vimdiff']);
      await g(['config', 'diff.guitool', 'probe']);
      await commitFile('f', 'a\n', 'one');
      await File('$repo/f').writeAsString('b\n');
      await actions().openDifftool(DiffTarget(repoPath: repo, path: 'f'));
      expect(
        git.log.singleWhere((a) => a.first == 'difftool'),
        contains('--gui'),
      );
      expect(await File(seen).readAsString(), 'a\nb\n');
    });

    test('a tool that fails is reported with git\'s stderr', () async {
      await g(['config', 'diff.tool', 'bad']);
      await g(['config', 'difftool.bad.cmd', 'echo boom >&2; exit 1']);
      await g(['config', 'difftool.trustExitCode', 'true']);
      await commitFile('f', 'a\n', 'one');
      await File('$repo/f').writeAsString('b\n');
      await actions().openDifftool(DiffTarget(repoPath: repo, path: 'f'));
      expect(toasts().single.kind, ToastKind.error);
      expect(toasts().single.description, contains('boom'));
    });

    test('at most $kMaxOpenDiffTools are open at once', () async {
      // Stays open until the test says it is closed.
      final release = '${dir.path}/release';
      await g([
        'config',
        'difftool.wait.cmd',
        'while [ ! -f "$release" ]; do sleep 0.05; done',
      ]);
      await g(['config', 'diff.tool', 'wait']);
      await commitFile('f', 'a\n', 'one');
      await File('$repo/f').writeAsString('b\n');
      final target = DiffTarget(repoPath: repo, path: 'f');

      final open = [
        for (var i = 0; i < kMaxOpenDiffTools; i++)
          actions().openDifftool(target),
      ];
      // Let every one get as far as starting git.
      while (git.log.where((a) => a.first == 'difftool').length <
          kMaxOpenDiffTools) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await actions().openDifftool(target);
      expect(
        git.log.where((a) => a.first == 'difftool'),
        hasLength(kMaxOpenDiffTools),
      );
      expect(toasts().single.kind, ToastKind.warning);

      await File(release).writeAsString('');
      await Future.wait(open);
      // Closing them frees the slots again.
      await actions().openDifftool(target);
      expect(
        git.log.where((a) => a.first == 'difftool'),
        hasLength(kMaxOpenDiffTools + 1),
      );
    });

    test('runs off the busy lane: other actions are not blocked', () async {
      await g(['config', 'diff.tool', 'probe']);
      await commitFile('f', 'a\n', 'one');
      await File('$repo/f').writeAsString('b\n');
      final run = actions().openDifftool(DiffTarget(repoPath: repo, path: 'f'));
      expect(c.read(busyProvider), isNull);
      await run;
    });
  });

  group('openMergeTool', () {
    /// `f` and `g` both conflicted between main and `side`, with a session
    /// open the way a conflicted merge leaves one.
    Future<void> conflict() async {
      await commitFile('f', 'a\n', 'base f');
      await commitFile('g', 'a\n', 'base g');
      await g(['switch', '-qc', 'side']);
      await commitFile('f', 'b\n', 'side f');
      await commitFile('g', 'b\n', 'side g');
      await g(['switch', '-q', 'main']);
      await commitFile('f', 'c\n', 'main f');
      await commitFile('g', 'c\n', 'main g');
      await actions().merge('side');
      expect(c.read(mergeSessionProvider(repo))!.files, hasLength(2));
      git.log.clear();
    }

    Future<void> takeTheirs() async {
      await g(['config', 'merge.tool', 'take']);
      await g(['config', 'mergetool.take.cmd', 'cp "\$REMOTE" "\$MERGED"']);
      await g(['config', 'mergetool.take.trustExitCode', 'true']);
      await g(['config', 'mergetool.keepBackup', 'false']);
    }

    test(
      'a resolved file leaves the session, staged and uncommitted',
      () async {
        await conflict();
        await takeTheirs();
        final head = await g(['rev-parse', 'HEAD']);

        await actions().openMergeTool('f');

        final session = c.read(mergeSessionProvider(repo))!;
        expect(session.files.map((f) => f.path), ['g']);
        expect(await g(['status', '--porcelain', '--', 'f']), 'M  f');
        expect(await g(['rev-parse', 'HEAD']), head);
        expect(toasts().last.kind, ToastKind.success);
        expect(c.read(busyProvider), isNull);
      },
    );

    test('the last file finishes the session as Resolve would', () async {
      await conflict();
      await takeTheirs();
      final head = await g(['rev-parse', 'HEAD']);

      await actions().openMergeTool('f');
      await actions().openMergeTool('g');

      expect(c.read(mergeSessionProvider(repo)), isNull);
      expect(await g(['status', '--porcelain']), 'M  f\nM  g');
      // Still mid-merge, and nothing committed or continued on the way.
      expect(await g(['rev-parse', 'HEAD']), head);
      expect(File('$repo/.git/MERGE_HEAD').existsSync(), isTrue);
      for (final args in git.log) {
        expect(args.first, isNot(anyOf('commit', 'merge', 'rebase')));
        expect(args, isNot(contains('--continue')));
      }
    });

    test('a failed tool keeps the file, and the choices made in it', () async {
      await conflict();
      await g(['config', 'merge.tool', 'half']);
      // Rewrites the file, then reports failure: git puts the file back.
      await g([
        'config',
        'mergetool.half.cmd',
        'echo scribbled > "\$MERGED"; exit 1',
      ]);
      await g(['config', 'mergetool.half.trustExitCode', 'true']);
      final before = c.read(mergeSessionProvider(repo))!;
      final hunk = before.files.first.hunkIndices.first;
      final chosen = before.replaceFile(
        0,
        before.files.first.withResolution(hunk, Resolution.ours),
      );
      c.read(mergeSessionProvider(repo).notifier).state = chosen;

      await actions().openMergeTool('f');

      expect(c.read(mergeSessionProvider(repo)), same(chosen));
      expect(
        await File('$repo/f').readAsString(),
        isNot(contains('scribbled')),
      );
      expect(await g(['status', '--porcelain', '--', 'f']), 'UU f');
      expect(toasts().last.kind, ToastKind.warning);
      expect(toasts().last.title, contains('f'));
    });

    test('a path one side deleted is refused, nothing runs', () async {
      await commitFile('f', 'a\n', 'base');
      await g(['switch', '-qc', 'side']);
      await g(['rm', '-q', 'f']);
      await g(['commit', '-qm', 'delete']);
      await g(['switch', '-q', 'main']);
      await commitFile('f', 'c\n', 'main');
      await actions().merge('side');
      expect(c.read(mergeSessionProvider(repo))!.files.single.path, 'f');
      await takeTheirs();
      git.log.clear();

      await actions().openMergeTool('f');

      // git would stop to ask modified-or-deleted, and leave temp files.
      expect(git.log.where((a) => a.first == 'mergetool'), isEmpty);
      expect(toasts().last.kind, ToastKind.warning);
      expect(await g(['status', '--porcelain']), 'UD f');
      expect(c.read(busyProvider), isNull);
    });

    /// A tool that stays open until [release] exists, then takes theirs.
    Future<String> slowTool() async {
      final release = '${dir.path}/release';
      await g(['config', 'merge.tool', 'slow']);
      await g([
        'config',
        'mergetool.slow.cmd',
        'while [ ! -f "$release" ]; do sleep 0.05; done; '
            'cp "\$REMOTE" "\$MERGED"',
      ]);
      await g(['config', 'mergetool.slow.trustExitCode', 'true']);
      await g(['config', 'mergetool.keepBackup', 'false']);
      // A tool left running by a test must still end before the directory
      // goes.
      addTearDown(() => File(release).writeAsString(''));
      return release;
    }

    /// Waits until git has handed the file to the tool. git makes its copies
    /// just before starting it, so their being there is the signal — a fixed
    /// wait is too short on a loaded machine.
    Future<void> untilToolRuns() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      bool copied() =>
          Directory(repo).listSync().any((e) => e.path.contains('f_LOCAL_'));
      while (!copied()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('git never started the merge tool');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('abort and resolve wait while the tool is open', () async {
      await conflict();
      final release = await slowTool();
      final run = actions().openMergeTool('f');
      await untilToolRuns();
      final session = c.read(mergeSessionProvider(repo))!;

      await actions().abortMerge();
      await actions().resolveConflicts(session);

      // Neither ran: still mid-merge, both files conflicted, session intact.
      expect(File('$repo/.git/MERGE_HEAD').existsSync(), isTrue);
      expect(await g(['status', '--porcelain', '--', 'g']), 'UU g');
      expect(c.read(mergeSessionProvider(repo)), same(session));
      expect(
        toasts().where((t) => t.title == 'An operation is already running'),
        hasLength(2),
      );

      await File(release).writeAsString('');
      await run;
      expect(await g(['status', '--porcelain', '--', 'f']), 'M  f');
    });

    test('a cancelled tool leaves no copies behind, and says so', () async {
      await conflict();
      await File('$repo/f_BASE_1').writeAsString('mine\n');
      await slowTool();
      final run = actions().openMergeTool('f');
      await untilToolRuns();
      final untrackedBefore = await g(['status', '--porcelain', '-uall']);
      expect(untrackedBefore, contains('f_LOCAL_'));

      c.read(busyProvider)!.onCancel!();
      await run;

      final status = await g(['status', '--porcelain', '-uall']);
      expect(status, isNot(contains('_LOCAL_')));
      expect(status, isNot(contains('_BACKUP_')));
      // A file of the user's that merely looks like one is left alone.
      expect(File('$repo/f_BASE_1').existsSync(), isTrue);
      expect(status, contains('UU f'));
      expect(toasts().last.kind, ToastKind.warning);
      expect(toasts().last.title, contains('slow'));
      expect(c.read(mergeSessionProvider(repo))!.files, hasLength(2));
    });

    test('a cancel before the tool starts never starts it', () async {
      await conflict();
      await takeTheirs();
      // The user cancels while the tool config is still being read.
      git.afterRun = (args) {
        if (args.contains(kExternalToolConfigPattern)) {
          c.read(busyProvider)!.onCancel!();
        }
      };

      await actions().openMergeTool('f');

      expect(git.log.where((a) => a.first == 'mergetool'), isEmpty);
      expect(toasts().last.title, 'Merge tool cancelled');
      expect(c.read(busyProvider), isNull);
      expect(await g(['status', '--porcelain', '--', 'f']), 'UU f');
      expect(c.read(mergeSessionProvider(repo))!.files, hasLength(2));
    });

    test('a choice made while git reads back is kept', () async {
      await conflict();
      await takeTheirs();
      // Let the refresh the merge scheduled run first, so the only status
      // read left is the one after the tool.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      git.afterRun = (args) {
        // The read-back after the tool, not a refresh before it.
        if (args.first != 'status' ||
            !git.log.any((a) => a.first == 'mergetool')) {
          return;
        }
        final s = c.read(mergeSessionProvider(repo))!;
        final i = s.files.indexWhere((f) => f.path == 'g');
        final h = s.files[i].hunkIndices.first;
        c.read(mergeSessionProvider(repo).notifier).state = s.replaceFile(
          i,
          s.files[i].withResolution(h, Resolution.ours),
        );
        git.afterRun = null;
      };

      await actions().openMergeTool('f');

      final g2 = c.read(mergeSessionProvider(repo))!.files.single;
      expect(g2.path, 'g');
      expect(g2.resolutions, isNotEmpty);
    });

    test('with no merge tool set it warns and runs nothing', () async {
      await conflict();
      await g(['config', 'diff.tool', 'probe']);
      await actions().openMergeTool('f');
      expect(git.log.where((a) => a.first == 'mergetool'), isEmpty);
      expect(toasts().last.kind, ToastKind.warning);
      expect(c.read(mergeSessionProvider(repo))!.files, hasLength(2));
    });

    test('refuses while another operation holds the repository', () async {
      await conflict();
      await takeTheirs();
      c.read(busyProvider.notifier).state = const BusyState('Pull');
      await actions().openMergeTool('f');
      expect(git.log.where((a) => a.first == 'mergetool'), isEmpty);
      expect(toasts().last.kind, ToastKind.warning);
    });

    test('holds the busy lane while the tool is open', () async {
      await conflict();
      await takeTheirs();
      final run = actions().openMergeTool('f');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(busyProvider)?.label, isNotNull);
      expect(c.read(busyProvider)?.onCancel, isNotNull);
      await run;
      expect(c.read(busyProvider), isNull);
    });
  });
}
