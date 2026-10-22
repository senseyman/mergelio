import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
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
    // A second person on the same remote, with notes of their own.
    late String clone;
    Future<void> theirNote(String sha, String text) async {
      await g(['notes', 'add', '-f', '-m', text, sha], at: clone);
      await g(['push', '-q', 'origin', 'refs/notes/commits'], at: clone);
    }

    setUp(() async {
      clone = '${dir.path}/clone';
      await g(['clone', '-q', '-b', 'main', remote, clone], at: dir.path);
      await g(['config', 'user.email', 'o@example.com'], at: clone);
      await g(['config', 'user.name', 'Other'], at: clone);
    });

    test('pushNotes publishes the notes ref', () async {
      final sha = await head();
      await writer().setNote(sha, 'shared');
      expect(await writer().pushNotes('origin'), isTrue);
      expect(
        await g(['rev-parse', 'refs/notes/commits'], at: remote),
        await g(['rev-parse', 'refs/notes/commits']),
      );
    });

    test('pushNotes with no notes on either side sends nothing', () async {
      expect(await writer().pushNotes('origin'), isFalse);
      final r = await svc.run([
        'rev-parse',
        '--verify',
        'refs/notes/commits',
      ], repoPath: remote);
      expect(r.ok, isFalse);
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
      await theirNote(sha, 'from afar');

      expect(await writer().fetchNotes('origin'), isTrue);
      expect(await reader().note(sha), 'from afar');
    });

    test('fetchNotes from a remote without notes changes nothing', () async {
      final sha = await head();
      await writer().setNote(sha, 'mine');
      final before = await g(['rev-parse', 'refs/notes/commits']);

      expect(await writer().fetchNotes('origin'), isFalse);
      expect(await g(['rev-parse', 'refs/notes/commits']), before);
    });

    test('fetchNotes follows a remote whose notes were rewritten', () async {
      final sha = await head();
      await theirNote(sha, 'first');
      await writer().fetchNotes('origin');
      // They start their notes over: the remote ref no longer descends from
      // the copy fetched before.
      await g(['update-ref', '-d', 'refs/notes/commits'], at: clone);
      await g(['notes', 'add', '-m', 'fresh', sha], at: clone);
      await g(['push', '-q', '-f', 'origin', 'refs/notes/commits'], at: clone);

      expect(await writer().fetchNotes('origin'), isTrue);
      expect(
        await g(['rev-parse', 'refs/mergelio/notes/origin/commits']),
        await g(['rev-parse', 'refs/notes/commits'], at: remote),
      );
    });

    test('fetchNotes merges notes both sides added', () async {
      final sha = await head();
      final first = await g(['rev-parse', 'HEAD~1']);
      await theirNote(first, 'theirs');
      await writer().setNote(sha, 'mine');

      await writer().fetchNotes('origin');
      expect(await reader().note(sha), 'mine');
      expect(await reader().note(first), 'theirs');
    });

    test(
      'a note both sides wrote on one commit keeps both, in order',
      () async {
        final sha = await head();
        await theirNote(sha, 'their line one\ntheir line two');
        await writer().setNote(sha, 'my line');

        await writer().fetchNotes('origin');
        expect(
          await reader().note(sha),
          'my line\n\ntheir line one\ntheir line two',
        );
      },
    );

    test('pushNotes merges in notes pushed first, then pushes', () async {
      final sha = await head();
      final first = await g(['rev-parse', 'HEAD~1']);
      await theirNote(first, 'theirs');
      await writer().setNote(sha, 'mine');

      expect(await writer().pushNotes('origin'), isTrue);
      await g([
        'fetch',
        '-q',
        'origin',
        '+refs/notes/*:refs/notes/*',
      ], at: clone);
      final notes = await g(['notes', 'list'], at: clone);
      expect(notes, allOf(contains(sha), contains(first)));
    });

    test('the merge is authored by the identity given', () async {
      final sha = await head();
      await theirNote(sha, 'theirs');
      await writer().setNote(sha, 'mine');

      await writer().fetchNotes(
        'origin',
        authorName: 'Maria K',
        authorEmail: 'maria@work.com',
      );
      expect(
        await g(['log', '-1', '--format=%an <%ae>', 'refs/notes/commits']),
        'Maria K <maria@work.com>',
      );
    });

    test('merges the remote ref core.notesRef names into ours', () async {
      final sha = await head();
      await g(['notes', '--ref=review', 'add', '-m', 'theirs', sha], at: clone);
      await g(['push', '-q', 'origin', 'refs/notes/review'], at: clone);
      await theirNote(sha, 'not this one');
      await g(['config', 'core.notesRef', 'refs/notes/review']);

      await writer().fetchNotes('origin');
      expect(await reader().note(sha), 'theirs');
      expect(
        (await svc.run([
          'rev-parse',
          '--verify',
          'refs/notes/commits',
        ], repoPath: repo)).ok,
        isFalse,
      );
    });
  });

  group('history', () {
    test('notes commits and fetched notes stay out of the graph', () async {
      final sha = await head();
      await writer().setNote(sha, 'mine');
      final clone = '${dir.path}/clone';
      await g(['clone', '-q', '-b', 'main', remote, clone], at: dir.path);
      await g(['notes', 'add', '-m', 'theirs', sha], at: clone);
      await g(['push', '-q', 'origin', 'refs/notes/commits'], at: clone);
      await writer().fetchNotes('origin');

      final page = await reader().commitPage();
      expect([for (final c in page.commits) c.message], ['two', 'one']);
    });
  });
}
