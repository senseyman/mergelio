import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/notes.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';

import 'support/hermetic_git.dart';

/// Records every git command so a test can say which ones ran.
class _LoggingGit implements GitService {
  final log = <List<String>>[];
  void Function(List<String> args)? onRun;
  static const _inner = HermeticGit();

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) {
    log.add(args);
    onRun?.call(args);
    return _inner.run(
      args,
      repoPath: repoPath,
      timeout: timeout,
      environment: environment,
      cancel: cancel,
      stdin: stdin,
    );
  }

  @override
  Future<String> version() => _inner.version();

  @override
  Future<bool> isRepository(String path) => _inner.isRepository(path);
}

void main() {
  late Directory dir;
  late String repo;
  late String remote;
  late String sha;
  late _LoggingGit git;
  late ProviderContainer c;

  Future<String> g(List<String> args, {String? at, String? stdin}) async {
    final r = await const HermeticGit().run(
      args,
      repoPath: at ?? repo,
      stdin: stdin,
    );
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  Future<String?> note() async {
    final r = await const HermeticGit().run([
      'notes',
      'show',
      sha,
    ], repoPath: repo);
    return r.ok ? r.out : null;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_note_act_');
    repo = '${dir.path}/r';
    remote = '${dir.path}/remote.git';
    await Directory(repo).create();
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 'repo@default.com']);
    await g(['config', 'user.name', 'Repo Default']);
    await g(['commit', '-q', '--allow-empty', '-m', 'base']);
    sha = await g(['rev-parse', 'HEAD']);
    await g(['init', '-q', '--bare', remote], at: dir.path);
    await g(['remote', 'add', 'origin', remote]);
    git = _LoggingGit();
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(),
          ),
        ),
        profilesProvider.overrideWith(
          (ref) => ProfilesController(
            InMemoryKeyValueStore(),
            const ProfilesState(
              profiles: [
                Profile(
                  id: '1',
                  label: 'Work',
                  name: 'Maria K',
                  email: 'maria@work.com',
                  colorValue: 0xFF112233,
                ),
              ],
              activeId: '1',
            ),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    c.dispose();
    await dir.delete(recursive: true);
  });

  RepoActions actions() => c.read(repoActionsProvider(repo));
  bool ranNotesWrite() => git.log.any(
    (a) => a.contains('notes') && (a.contains('add') || a.contains('remove')),
  );

  group('setNote', () {
    test('adds a note, authored by the active profile', () async {
      await actions().setNote(sha, 'reviewed by QA');
      expect(await note(), 'reviewed by QA');
      expect(
        await g(['log', '-1', '--format=%an <%ae>', 'refs/notes/commits']),
        'Maria K <maria@work.com>',
      );
    });

    test('undo of a first note removes it; redo puts it back', () async {
      await actions().setNote(sha, 'first');
      await actions().undo();
      expect(await note(), isNull);
      await actions().redo();
      expect(await note(), 'first');
    });

    test('undo of an edit brings back the earlier text', () async {
      await g(['notes', 'add', '-m', 'before\n\nsecond paragraph', sha]);
      await actions().setNote(sha, 'after');
      expect(await note(), 'after');
      await actions().undo();
      expect(await note(), 'before\n\nsecond paragraph');
    });

    test('empty text removes the note, and undo restores it', () async {
      await g(['notes', 'add', '-m', 'keep me', sha]);
      await actions().setNote(sha, '   \n');
      expect(await note(), isNull);
      await actions().undo();
      expect(await note(), 'keep me');
    });

    test('unchanged text writes nothing', () async {
      await g(['notes', 'add', '-m', 'same', sha]);
      git.log.clear();
      await actions().setNote(sha, 'same\n');
      expect(ranNotesWrite(), isFalse);
    });

    test('a change git would tidy away writes nothing', () async {
      await g(['notes', 'add', '-m', 'a\n\nb', sha]);
      git.log.clear();
      await actions().setNote(sha, 'a   \n\n\n\nb  \n\n');
      expect(ranNotesWrite(), isFalse);
    });

    test('undo keeps the indentation a note starts with', () async {
      await g(['notes', 'add', '-m', '    indented\nnext', sha]);
      await actions().setNote(sha, 'replaced');
      await actions().undo();
      expect(
        (await const HermeticGit().run([
          'notes',
          'show',
          sha,
        ], repoPath: repo)).stdout,
        '    indented\nnext\n',
      );
    });

    test('empty text on a commit without a note writes nothing', () async {
      await actions().setNote(sha, '');
      expect(ranNotesWrite(), isFalse);
    });
  });

  group('an unreadable note', () {
    // A sha git cannot resolve fails `notes show` with exit 128, not the
    // "no note" exit 1.
    const bad = 'not-a-commit';

    test('setNote toasts the failure instead of throwing', () async {
      await actions().setNote(bad, 'x');
      final t = c.read(toastProvider).last;
      expect(t.kind, ToastKind.error);
      expect(t.description, contains(bad));
      expect(ranNotesWrite(), isFalse);
    });

    test('removeNote toasts the failure instead of throwing', () async {
      await actions().removeNote(bad);
      expect(c.read(toastProvider).last.kind, ToastKind.error);
      expect(ranNotesWrite(), isFalse);
    });
  });

  group('removeNote', () {
    test('removes, and undo restores the text', () async {
      await g(['notes', 'add', '-m', 'gone soon', sha]);
      await actions().removeNote(sha);
      expect(await note(), isNull);
      await actions().undo();
      expect(await note(), 'gone soon');
    });

    test('a commit without a note writes nothing', () async {
      await actions().removeNote(sha);
      expect(ranNotesWrite(), isFalse);
    });
  });

  group('sharing', () {
    test('pushNotes publishes the notes ref', () async {
      await g(['notes', 'add', '-m', 'shared', sha]);
      await actions().pushNotes('origin');
      expect(
        await g(['rev-parse', 'refs/notes/commits'], at: remote),
        await g(['rev-parse', 'refs/notes/commits']),
      );
      expect(c.read(toastProvider).last.kind, ToastKind.success);
    });

    test('pushNotes with no notes says so and pushes nothing', () async {
      await actions().pushNotes('origin');
      final t = c.read(toastProvider).last;
      expect(t.kind, ToastKind.info);
      expect(t.title, 'No notes to push');
      expect(git.log.any((a) => a.first == 'push'), isFalse);
    });

    test('fetchNotes waits for an operation on the repository', () async {
      // Fetching writes the notes ref a note edit writes too.
      c.read(busyProvider.notifier).state = BusyState('Save note');
      await actions().fetchNotes('origin');
      expect(
        c.read(toastProvider).last.title,
        'An operation is already running',
      );
      expect(git.log.any((a) => a.first == 'fetch'), isFalse);
    });

    test('fetchNotes from a remote without notes says so calmly', () async {
      await actions().fetchNotes('origin');
      final t = c.read(toastProvider).last;
      expect(t.kind, ToastKind.info);
      expect(t.title, 'origin has no notes');
    });

    test('fetchNotes merges in the remote notes, under the profile', () async {
      final clone = '${dir.path}/clone';
      await g(['push', '-q', 'origin', 'main']);
      await g(['clone', '-q', '-b', 'main', remote, clone], at: dir.path);
      await g(['config', 'user.email', 'o@example.com'], at: clone);
      await g(['config', 'user.name', 'Other'], at: clone);
      await g(['notes', 'add', '-m', 'theirs', sha], at: clone);
      await g(['push', '-q', 'origin', 'refs/notes/commits'], at: clone);
      await g(['notes', 'add', '-m', 'mine', sha]);

      await actions().fetchNotes('origin');
      expect(await note(), 'mine\n\ntheirs');
      expect(c.read(toastProvider).last.kind, ToastKind.success);
      expect(
        await g(['log', '-1', '--format=%an <%ae>', 'refs/notes/commits']),
        'Maria K <maria@work.com>',
      );
    });
  });

  group('fetch with notes', () {
    late String clone;
    setUp(() async {
      await g(['push', '-q', 'origin', 'main']);
      clone = '${dir.path}/clone';
      await g(['clone', '-q', '-b', 'main', remote, clone], at: dir.path);
      await g(['config', 'user.email', 'o@example.com'], at: clone);
      await g(['config', 'user.name', 'Other'], at: clone);
      await g(['notes', 'add', '-m', 'theirs', sha], at: clone);
      await g(['push', '-q', 'origin', 'refs/notes/commits'], at: clone);
    });

    void enable(bool on) =>
        c.read(settingsProvider.notifier).setFetchNotesWithFetch(on);

    test('a fetch brings notes when the preference is on', () async {
      enable(true);
      await actions().fetch(remote: 'origin');
      expect(await note(), 'theirs');
    });

    test('a fetch of every remote brings each one\'s notes', () async {
      enable(true);
      await actions().fetch();
      expect(await note(), 'theirs');
    });

    test('a fetch leaves notes alone when the preference is off', () async {
      await actions().fetch(remote: 'origin');
      expect(await note(), isNull);
    });

    test('auto-fetch brings notes too, without a word', () async {
      enable(true);
      await actions().fetch(silent: true);
      expect(await note(), 'theirs');
      expect(c.read(toastProvider), isEmpty);
    });

    test('auto-fetch keeps a notes failure to itself', () async {
      enable(true);
      // Local notes on a commit the remote's notes also changed cannot
      // conflict under union, so break the merge another way: a notes ref
      // that is not a commit.
      final blob = await g(['hash-object', '-w', '--stdin'], stdin: 'x');
      await g(['update-ref', 'refs/notes/commits', blob]);
      await actions().fetch(silent: true);
      expect(c.read(toastProvider), isEmpty);
    });

    test('a remote without notes adds no toast to the fetch', () async {
      enable(true);
      final empty = '${dir.path}/empty.git';
      await g(['init', '-q', '--bare', empty], at: dir.path);
      await g(['remote', 'add', 'empty', empty]);
      await actions().fetch(remote: 'empty');
      expect(c.read(toastProvider).map((t) => t.title), ['Fetch complete']);
    });

    test('notes wait when another operation holds the repository', () async {
      enable(true);
      c.read(busyProvider.notifier).state = BusyState('Merge');
      await actions().fetch(remote: 'origin');
      expect(await note(), isNull);
      expect(
        c.read(toastProvider).where((t) => t.kind == ToastKind.warning),
        isEmpty,
      );
    });
  });

  group('lane', () {
    test('a note edit reads nothing while another operation runs', () async {
      await g(['notes', 'add', '-m', 'before', sha]);
      c.read(busyProvider.notifier).state = BusyState('Merge');
      git.log.clear();
      await actions().setNote(sha, 'after');
      await actions().removeNote(sha);
      expect(git.log.where((a) => a.contains('notes')), isEmpty);
      expect(await note(), 'before');
    });

    test('a note edit holds the lane from its read to its write', () async {
      await g(['notes', 'add', '-m', 'before', sha]);
      BusyState? duringRead;
      git.onRun = (args) {
        if (args.contains('show')) duringRead = c.read(busyProvider);
      };
      await actions().setNote(sha, 'after');
      expect(duringRead, isNotNull);
      expect(c.read(busyProvider), isNull);
    });

    test('a no-op edit gives the lane back', () async {
      await g(['notes', 'add', '-m', 'same', sha]);
      await actions().setNote(sha, 'same');
      expect(c.read(busyProvider), isNull);
    });
  });

  test('a repository without notes never lists them', () async {
    final sub = c.listen(noteIndexProvider(repo), (_, _) {});
    addTearDown(sub.close);
    await c.read(repoDataProvider(repo).future);
    expect(await c.read(noteIndexProvider(repo).future), isEmpty);
    expect(git.log.where((a) => a.take(2).join(' ') == 'notes list'), isEmpty);
  });

  test('a saved note reaches the notes index after the refresh', () async {
    // The index follows the repository data, which every action refreshes.
    final sub = c.listen(noteIndexProvider(repo), (_, _) {});
    addTearDown(sub.close);
    expect(await c.read(noteIndexProvider(repo).future), isEmpty);

    await actions().setNote(sha, 'indexed');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await c.read(repoDataProvider(repo).future);
    final index = await c.read(noteIndexProvider(repo).future);
    expect(index.keys, [sha]);
  });
}
