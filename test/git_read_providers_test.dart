import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/notes.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/signatures.dart';
import 'package:mergelio/state/stash_contents.dart';

/// The small on-demand git reads behind notes, tags and stashes: when they
/// run git at all, what they return, and that failures reach the caller.
void main() {
  const repo = '/repo';
  const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const blob = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  late _ScriptedGit git;
  late ProviderContainer c;

  void open({String notesSignature = ''}) {
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        repoDataProvider.overrideWith(
          (ref, path) async => RepoData(notesSignature: notesSignature),
        ),
      ],
    );
    addTearDown(c.dispose);
  }

  /// Reads an autoDispose provider while keeping it alive until it settles.
  Future<T> readAuto<T>(ProviderListenable<AsyncValue<T>> p) async {
    final completer = Completer<T>();
    final sub = c.listen<AsyncValue<T>>(p, (_, next) {
      next.whenOrNull(
        data: (v) => completer.isCompleted ? null : completer.complete(v),
        error: (e, s) =>
            completer.isCompleted ? null : completer.completeError(e, s),
      );
    }, fireImmediately: true);
    try {
      return await completer.future;
    } finally {
      sub.close();
    }
  }

  setUp(() => git = _ScriptedGit());

  group('noteIndexProvider', () {
    test('a repository without notes refs runs no git', () async {
      open();
      await c.read(repoDataProvider(repo).future);
      expect(await c.read(noteIndexProvider(repo).future), isEmpty);
      expect(git.calls, isEmpty);
    });

    test('lists notes when the repository has a notes ref', () async {
      git.on(['notes', 'list'], GitResult(0, '$blob $sha\n', ''));
      open(notesSignature: 'refs/notes/commits $blob');
      await c.read(repoDataProvider(repo).future);
      expect(await c.read(noteIndexProvider(repo).future), {sha: blob});
    });

    test('a failed listing is reported, not swallowed', () async {
      git.on(['notes', 'list'], const GitResult(128, '', 'fatal: bad'));
      open(notesSignature: 'refs/notes/commits $blob');
      await c.read(repoDataProvider(repo).future);
      await expectLater(
        c.read(noteIndexProvider(repo).future),
        throwsA(isA<GitException>()),
      );
    });
  });

  group('commitNoteProvider', () {
    final key = (repo: repo, sha: sha, blob: blob);

    test('returns the note without git\'s closing newline', () async {
      git.on(['notes', 'show', sha], const GitResult(0, '  indented\n', ''));
      open();
      expect(await readAuto(commitNoteProvider(key)), '  indented');
    });

    test('a commit without a note reads as empty', () async {
      git.on(['notes', 'show', sha], const GitResult(1, '', ''));
      open();
      expect(await readAuto(commitNoteProvider(key)), '');
    });

    test('a failed read is reported', () async {
      git.on(['notes', 'show', sha], const GitResult(128, '', 'fatal'));
      open();
      await expectLater(
        readAuto(commitNoteProvider(key)),
        throwsA(isA<GitException>()),
      );
    });
  });

  group('allowedSignersFileProvider', () {
    test('null when unset', () async {
      git.on([
        'config',
        '--get',
        'gpg.ssh.allowedSignersFile',
      ], const GitResult(1, '', ''));
      open();
      expect(await readAuto(allowedSignersFileProvider(repo)), isNull);
    });

    test('null when set to nothing', () async {
      git.on([
        'config',
        '--get',
        'gpg.ssh.allowedSignersFile',
      ], const GitResult(0, '\n', ''));
      open();
      expect(await readAuto(allowedSignersFileProvider(repo)), isNull);
    });

    test('the configured path', () async {
      git.on([
        'config',
        '--get',
        'gpg.ssh.allowedSignersFile',
      ], const GitResult(0, '/home/me/.ssh/allowed\n', ''));
      open();
      expect(
        await readAuto(allowedSignersFileProvider(repo)),
        '/home/me/.ssh/allowed',
      );
    });
  });

  group('tagInfosProvider', () {
    test('a failed read is reported', () async {
      git.fallback = const GitResult(128, '', 'fatal');
      open();
      await expectLater(
        readAuto(tagInfosProvider((repo: repo, sha: sha, names: 'v1'))),
        throwsA(isA<GitException>()),
      );
      expect(
        git.calls.single,
        containsAll(['for-each-ref', '--points-at', sha]),
      );
    });

    test('a commit with no tags reads as an empty list', () async {
      git.fallback = const GitResult(0, '', '');
      open();
      expect(
        await readAuto(tagInfosProvider((repo: repo, sha: sha, names: ''))),
        isEmpty,
      );
    });
  });

  group('tagSigningProvider', () {
    test(
      'nothing configured reads as no key, not signing by default',
      () async {
        git.fallback = const GitResult(1, '', '');
        open();
        final s = await readAuto(tagSigningProvider(repo));
        expect(s.key, isNull);
        expect(s.byDefault, isFalse);
      },
    );

    test('an unreadable config is reported', () async {
      git.fallback = const GitResult(3, '', 'fatal: bad config');
      open();
      await expectLater(
        readAuto(tagSigningProvider(repo)),
        throwsA(isA<GitException>()),
      );
    });
  });

  group('stashContentsProvider', () {
    test('a stash whose base cannot be resolved is reported', () async {
      git.fallback = const GitResult(1, '', '');
      open();
      await expectLater(
        readAuto(stashContentsProvider((repoPath: repo, sha: sha))),
        throwsA(isA<GitException>()),
      );
      expect(git.calls.first, ['rev-parse', '--verify', '-q', '$sha^1']);
    });
  });

  group('signatureAuditProvider', () {
    test('stops the audit once nobody is waiting for it', () async {
      final started = Completer<GitCancel?>();
      git.hold = (args, cancel) {
        if (!started.isCompleted) started.complete(cancel);
      };
      open();
      final sub = c.listen(
        signatureAuditProvider((repo: repo, base: 'main')),
        (_, _) {},
      );
      final cancel = await started.future;
      expect(cancel, isNotNull);
      expect(cancel!.isCancelled, isFalse);

      sub.close();
      await Future<void>.delayed(Duration.zero);
      expect(cancel.isCancelled, isTrue);
    });
  });
}

/// Answers each git command from a table keyed by its arguments, recording
/// what was asked. [hold] parks a command forever, to look at it mid-flight.
class _ScriptedGit implements GitService {
  final calls = <List<String>>[];
  final _answers = <String, GitResult>{};
  GitResult fallback = const GitResult(0, '', '');
  void Function(List<String> args, GitCancel? cancel)? hold;

  void on(List<String> args, GitResult result) =>
      _answers[args.join('\u0000')] = result;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) {
    calls.add(args);
    if (hold != null) {
      hold!(args, cancel);
      return Completer<GitResult>().future;
    }
    return Future.value(_answers[args.join('\u0000')] ?? fallback);
  }

  @override
  Future<String> version() async => 'git version 2.50.0';

  @override
  Future<bool> isRepository(String path) async => true;
}
