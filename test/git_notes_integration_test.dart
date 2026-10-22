import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';

import 'support/hermetic_git.dart';

/// Reading, writing and sharing notes against real git. Global and system
/// config are switched off so the developer's own `core.notesRef` cannot
/// leak in.
void main() {
  const svc = HermeticGit();

  late Directory dir;
  late String repo;
  late String remote;

  Future<String> g(List<String> args, {String? at}) async {
    final r = await svc.run(args, repoPath: at ?? repo);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
    return r.out;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_notes_');
    repo = '${dir.path}/r';
    remote = '${dir.path}/remote.git';
    await Directory(repo).create();
    await g(['init', '-q']);
    await g(['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(['config', 'user.email', 't@example.com']);
    await g(['config', 'user.name', 'Tester']);
    await g(['commit', '-q', '--allow-empty', '-m', 'one']);
    await g(['commit', '-q', '--allow-empty', '-m', 'two']);
    await g(['init', '-q', '--bare', remote], at: dir.path);
    await g(['remote', 'add', 'origin', remote]);
    await g(['push', '-q', 'origin', 'main']);
  });

  tearDown(() => dir.delete(recursive: true));

  GitReader reader() => GitReader(svc, repo);
  GitWriter writer() => GitWriter(svc, repo);
  Future<String> head() => g(['rev-parse', 'HEAD']);

  group('reading', () {
    test('a repository without notes has an empty index', () async {
      expect(await reader().noteIndex(), isEmpty);
    });

    test('the index lists every annotated commit', () async {
      final sha = await head();
      await g(['notes', 'add', '-m', 'hello', sha]);
      final blob = await g(['rev-parse', 'refs/notes/commits:$sha']);
      expect(await reader().noteIndex(), {sha: blob});
    });

    test('a commit without a note reads as null', () async {
      expect(await reader().note(await head()), isNull);
    });

    test('a note reads back as written', () async {
      final sha = await head();
      await g(['notes', 'add', '-m', 'line one\n\nline three', sha]);
      expect(await reader().note(sha), 'line one\n\nline three');
    });

    test('a note that starts indented reads back with its indent', () async {
      final sha = await head();
      await g(['notes', 'add', '-m', '  indented\nnext', sha]);
      expect(await reader().note(sha), '  indented\nnext');
    });

    test('follows core.notesRef', () async {
      final sha = await head();
      await g(['notes', 'add', '-m', 'default', sha]);
      await g(['config', 'core.notesRef', 'refs/notes/review']);
      expect(await reader().noteIndex(), isEmpty);
      expect(await reader().note(sha), isNull);
      expect(await reader().notesRef(), 'refs/notes/review');
    });
  });

  group('writing', () {
    test('setNote adds, then overwrites', () async {
      final sha = await head();
      await writer().setNote(sha, 'first');
      expect(await reader().note(sha), 'first');
      await writer().setNote(sha, 'second\n# kept');
      expect(await reader().note(sha), 'second\n# kept');
    });

    test('an empty note removes the one there', () async {
      final sha = await head();
      await writer().setNote(sha, 'first');
      await writer().setNote(sha, '  \n');
      expect(await reader().note(sha), isNull);
    });

    test('removeNote is quiet when there is nothing to remove', () async {
      final sha = await head();
      await writer().removeNote(sha);
      await writer().setNote(sha, 'x');
      await writer().removeNote(sha);
      expect(await reader().note(sha), isNull);
    });

    test('the identity given authors the note', () async {
      final sha = await head();
      await writer().setNote(
        sha,
        'x',
        authorName: 'Maria K',
        authorEmail: 'maria@work.com',
      );
      expect(
        await g(['log', '-1', '--format=%an <%ae>', 'refs/notes/commits']),
        'Maria K <maria@work.com>',
      );
    });
  });

  group('sharing', () {
    test('pushNotes publishes the notes ref', () async {
      final sha = await head();
      await writer().setNote(sha, 'shared');
      await writer().pushNotes('origin');
      expect(
        await g(['rev-parse', 'refs/notes/commits'], at: remote),
        await g(['rev-parse', 'refs/notes/commits']),
      );
    });

    test('pushNotes sends the ref core.notesRef names', () async {
      await g(['config', 'core.notesRef', 'refs/notes/review']);
      await writer().setNote(await head(), 'review');
      await writer().pushNotes('origin');
      expect(
        await g(['rev-parse', 'refs/notes/review'], at: remote),
        await g(['rev-parse', 'refs/notes/review']),
      );
    });

    test('fetchNotes brings notes from the remote', () async {
      final sha = await head();
      final clone = '${dir.path}/clone';
      await g(['clone', '-q', '-b', 'main', remote, clone], at: dir.path);
      await g(['config', 'user.email', 'o@example.com'], at: clone);
      await g(['config', 'user.name', 'Other'], at: clone);
      await g(['notes', 'add', '-m', 'from afar', sha], at: clone);
      await g(['push', '-q', 'origin', 'refs/notes/commits'], at: clone);

      await writer().fetchNotes('origin');
      expect(await reader().note(sha), 'from afar');
    });

    test('a diverged push fails with git\'s explanation', () async {
      final sha = await head();
      final clone = '${dir.path}/clone';
      await g(['clone', '-q', '-b', 'main', remote, clone], at: dir.path);
      await g(['config', 'user.email', 'o@example.com'], at: clone);
      await g(['config', 'user.name', 'Other'], at: clone);
      await g(['notes', 'add', '-m', 'theirs', sha], at: clone);
      await g(['push', '-q', 'origin', 'refs/notes/commits'], at: clone);
      await writer().setNote(sha, 'mine');

      await expectLater(
        writer().pushNotes('origin'),
        throwsA(
          isA<GitException>().having(
            (e) => e.result?.err,
            'stderr',
            contains('rejected'),
          ),
        ),
      );
    });
  });
}
