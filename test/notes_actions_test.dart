import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/state/repo_actions.dart';

import 'support/hermetic_git.dart';

/// Records every git command so a test can say which ones ran.
class _LoggingGit implements GitService {
  final log = <List<String>>[];
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

  Future<String> g(List<String> args, {String? at}) async {
    final r = await const HermeticGit().run(args, repoPath: at ?? repo);
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

    test('fetchNotes reports a remote without notes as a failure', () async {
      await actions().fetchNotes('origin');
      final t = c.read(toastProvider).last;
      expect(t.kind, ToastKind.error);
      expect(t.description, contains('refs/notes/commits'));
    });
  });
}
