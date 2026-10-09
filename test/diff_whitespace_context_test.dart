import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blame.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/diff_view_options.dart';
import 'package:mergelio/state/file_insight.dart';
import 'package:mergelio/state/settings.dart';

/// Whitespace and context options: the reader turns them into git flags, the
/// document provider threads them through and refuses to offer patches built
/// from a whitespace-blind diff, and a whitespace-only change is not mistaken
/// for no change at all.
void main() {
  late Directory repo;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  // Forty lines with line 20 swapped out, so a 3-line window reaches neither
  // end but a 10-line one reaches line 10.
  String body(String line20) =>
      [for (var i = 1; i <= 40; i++) i == 20 ? line20 : 'line $i'].join('\n');

  Future<void> write(String name, String text) =>
      File('${repo.path}/$name').writeAsString(text);

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_ws_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await write('x.txt', '${body('line 20')}\n');
    await write('ws.txt', 'a b\nc\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    await write('x.txt', '${body('CHANGED')}\n');
    // Only the amount of whitespace changes.
    await write('ws.txt', 'a    b\nc\n');
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  group('whitespaceArgs', () {
    test('maps each mode to its git flag', () {
      expect(whitespaceArgs(DiffWhitespace.show), isEmpty);
      expect(whitespaceArgs(DiffWhitespace.ignoreChange), [
        '--ignore-space-change',
      ]);
      expect(whitespaceArgs(DiffWhitespace.ignoreAll), ['--ignore-all-space']);
    });
  });

  group('GitReader whitespace', () {
    test('workingDiff hides a whitespace-only change when ignored', () async {
      final r = GitReader(svc, repo.path);
      expect(await r.workingDiff('ws.txt'), contains('+a    b'));
      expect(
        await r.workingDiff('ws.txt', whitespace: DiffWhitespace.ignoreChange),
        isNot(contains('@@')),
      );
    });

    test(
      'ignoreChange keeps a whitespace insertion, ignoreAll drops it',
      () async {
        await write('ws.txt', 'ab\nc\n');
        await g(['add', 'ws.txt']);
        await g(['commit', '-q', '-m', 'joined']);
        await write('ws.txt', 'a b\nc\n');
        final r = GitReader(svc, repo.path);
        expect(
          await r.workingDiff(
            'ws.txt',
            whitespace: DiffWhitespace.ignoreChange,
          ),
          contains('+a b'),
        );
        expect(
          await r.workingDiff('ws.txt', whitespace: DiffWhitespace.ignoreAll),
          isNot(contains('@@')),
        );
      },
    );

    test('stagedDiff, commitDiff and compareDiff honour the mode', () async {
      await g(['add', 'ws.txt']);
      final r = GitReader(svc, repo.path);
      const ws = DiffWhitespace.ignoreAll;
      expect(
        await r.stagedDiff('ws.txt', whitespace: ws),
        isNot(contains('@@')),
      );
      await g(['commit', '-q', '-m', 'spaces']);
      expect(
        await r.commitDiff('HEAD', 'ws.txt', whitespace: ws),
        isNot(contains('@@')),
      );
      expect(
        await r.compareDiff('HEAD~1', 'HEAD', 'ws.txt', whitespace: ws),
        isNot(contains('@@')),
      );
      // Sanity: without the flag each of them shows the change.
      expect(await r.commitDiff('HEAD', 'ws.txt'), contains('@@'));
    });

    test('untrackedDiff accepts the mode', () async {
      await write('new.txt', 'fresh\n');
      final raw = await GitReader(
        svc,
        repo.path,
      ).untrackedDiff('new.txt', whitespace: DiffWhitespace.ignoreAll);
      expect(raw, contains('+fresh'));
    });

    test('blame ignoring whitespace keeps the original author line', () async {
      await g(['add', 'ws.txt']);
      await g(['commit', '-q', '-m', 'spaces']);
      final r = GitReader(svc, repo.path);
      final base = (await svc.run([
        'rev-parse',
        'HEAD~1',
      ], repoPath: repo.path)).stdout.trim();
      final plain = parseBlame(await r.blame('ws.txt'));
      final ignored = parseBlame(
        await r.blame('ws.txt', ignoreWhitespace: true),
      );
      expect(plain.first.sha, isNot(base));
      expect(ignored.first.sha, base);
    });
  });

  group('DiffViewOptions', () {
    test('defaults to showing whitespace with git\'s 3 lines', () {
      const o = DiffViewOptions();
      expect(o.whitespace, DiffWhitespace.show);
      expect(o.contextLines, 3);
      expect(o.isDefault, isTrue);
      expect(o.copyWith(contextLines: 5).isDefault, isFalse);
    });

    test('contextArg leaves the default to git', () {
      expect(const DiffViewOptions().contextArg(wholeFile: false), isNull);
      expect(
        const DiffViewOptions(contextLines: 10).contextArg(wholeFile: false),
        10,
      );
      expect(
        const DiffViewOptions(contextLines: 10).contextArg(wholeFile: true),
        kWholeFileContext,
      );
    });

    test('round-trips through settings and survives junk', () {
      final s = const AppSettings().copyWith(
        diffWhitespace: 'ignoreAll',
        diffContextLines: 10,
      );
      final o = DiffViewOptions.fromSettings(s);
      expect(o.whitespace, DiffWhitespace.ignoreAll);
      expect(o.contextLines, 10);
      expect(
        DiffViewOptions.fromSettings(
          const AppSettings().copyWith(
            diffWhitespace: 'bogus',
            diffContextLines: 7,
          ),
        ),
        const DiffViewOptions(),
      );
    });
  });

  group('diffDocumentProvider', () {
    Future<DiffDoc> load(
      String path, {
      DiffViewOptions options = const DiffViewOptions(),
      bool staged = false,
    }) {
      final c = ProviderContainer(
        overrides: [diffViewOptionsProvider.overrideWith((_) => options)],
      );
      addTearDown(c.dispose);
      return c.read(
        diffDocumentProvider(
          DiffTarget(repoPath: repo.path, path: path, staged: staged),
        ).future,
      );
    }

    List<String> texts(DiffDoc doc) => [
      for (final f in doc.files)
        for (final h in f.hunks)
          for (final l in h.lines) l.text,
    ];

    test('context lines widen the window', () async {
      final narrow = texts(await load('x.txt'));
      final wide = texts(
        await load('x.txt', options: const DiffViewOptions(contextLines: 10)),
      );
      expect(narrow, isNot(contains('line 10')));
      expect(wide, contains('line 10'));
      expect(wide, isNot(contains('line 1')));
    });

    test('a whitespace-blind document cannot apply patches', () async {
      final shown = await load('x.txt');
      expect(shown.whitespaceIgnored, isFalse);
      expect(shown.canApplyPatches, isTrue);
      final hidden = await load(
        'x.txt',
        options: const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
      );
      expect(hidden.whitespaceIgnored, isTrue);
      expect(hidden.editable, isTrue);
      expect(hidden.canApplyPatches, isFalse);
    });

    test('a whitespace-only change stays on its side, not untracked', () async {
      final doc = await load(
        'ws.txt',
        options: const DiffViewOptions(whitespace: DiffWhitespace.ignoreChange),
      );
      expect(doc.isEmpty, isTrue);
      expect(doc.staged, isFalse);
      expect(doc.whitespaceOnly, isTrue);
    });

    test('a whitespace-only staged change stays on the staged side', () async {
      await g(['add', 'ws.txt']);
      final doc = await load(
        'ws.txt',
        staged: true,
        options: const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
      );
      expect(doc.isEmpty, isTrue);
      expect(doc.staged, isTrue);
      expect(doc.whitespaceOnly, isTrue);
    });

    test('an untracked file stays patchable with whitespace ignored', () async {
      // An all-added read has nothing for -w or -b to hide, so it is read
      // exactly and its lines can still be staged.
      await write('new.txt', 'a  b\n\n  c\n');
      final doc = await load(
        'new.txt',
        options: const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
      );
      expect(doc.files.single.status, isNot(GitChange.modified));
      expect(doc.whitespaceIgnored, isFalse);
      expect(doc.canApplyPatches, isTrue);
    });

    test('a real change is never whitespaceOnly', () async {
      final doc = await load(
        'x.txt',
        options: const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
      );
      expect(doc.isEmpty, isFalse);
      expect(doc.whitespaceOnly, isFalse);
    });

    test(
      'a commit that only changed the file mode is not whitespaceOnly',
      () async {
        // update-index also stages the file's content, so put back the
        // committed text first to leave only the mode in the commit.
        await g(['checkout', '--', 'x.txt']);
        await g(['update-index', '--chmod=+x', 'x.txt']);
        await g(['commit', '-q', '-m', 'chmod']);
        final c = ProviderContainer(
          overrides: [
            diffViewOptionsProvider.overrideWith(
              (_) =>
                  const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
            ),
          ],
        );
        addTearDown(c.dispose);
        final sha = (await svc.run([
          'rev-parse',
          'HEAD',
        ], repoPath: repo.path)).stdout.trim();
        final doc = await c.read(
          diffDocumentProvider(
            DiffTarget(repoPath: repo.path, path: 'x.txt', commitSha: sha),
          ).future,
        );
        expect(doc.isEmpty, isTrue);
        expect(doc.whitespaceOnly, isFalse);
      },
    );

    test('a commit that only changed whitespace is whitespaceOnly', () async {
      await g(['add', 'ws.txt']);
      await g(['commit', '-q', '-m', 'spaces']);
      final c = ProviderContainer(
        overrides: [
          diffViewOptionsProvider.overrideWith(
            (_) => const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
          ),
        ],
      );
      addTearDown(c.dispose);
      final doc = await c.read(
        diffDocumentProvider(
          DiffTarget(repoPath: repo.path, path: 'ws.txt', commitSha: 'HEAD'),
        ).future,
      );
      expect(doc.isEmpty, isTrue);
      expect(doc.whitespaceOnly, isTrue);
    });
  });

  test('blameProvider ignores whitespace when the diff does', () async {
    await g(['add', 'ws.txt']);
    await g(['commit', '-q', '-m', 'spaces']);
    final base = (await svc.run([
      'rev-parse',
      'HEAD~1',
    ], repoPath: repo.path)).stdout.trim();
    final c = ProviderContainer(
      overrides: [
        diffViewOptionsProvider.overrideWith(
          (_) => const DiffViewOptions(whitespace: DiffWhitespace.ignoreChange),
        ),
      ],
    );
    addTearDown(c.dispose);
    final lines = await c.read(
      blameProvider((repo: repo.path, path: 'ws.txt', rev: null)).future,
    );
    expect(lines.first.sha, base);
  });
}
