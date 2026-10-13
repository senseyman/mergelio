import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blame.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  Future<String> sha(String rev) async =>
      (await svc.run(['rev-parse', rev], repoPath: dir.path)).out.trim();

  Future<void> write(String name, List<String> lines) =>
      File('${dir.path}/$name').writeAsString('${lines.join('\n')}\n');

  Future<String> commit(String msg) async {
    await g(['add', '-A']);
    await g(['commit', '-q', '-m', msg]);
    return sha('HEAD');
  }

  GitReader reader() => GitReader(svc, dir.path);

  Future<List<String>> blamed(
    String path, {
    BlameMoves moves = BlameMoves.off,
    String? ignoreRevsFile,
  }) async => [
    for (final l in parseBlame(
      await reader().blame(path, moves: moves, ignoreRevsFile: ignoreRevsFile),
    ))
      l.sha,
  ];

  // Long enough for git to count a moved line.
  final block = [
    for (var i = 1; i <= 6; i++)
      'block line $i with enough alphanumeric characters to count as moved',
  ];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_blame_opts_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 'm@e.com']);
    await g(['config', 'user.name', 'Maria']);
    await g(['config', 'commit.gpgsign', 'false']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('moved lines', () {
    test('within file credits a moved block to where it was written', () async {
      final tail = [
        for (var i = 1; i <= 2; i++)
          'tail line $i of the file carrying plenty of other letters too',
      ];
      await write('a.txt', [...block, ...tail]);
      final first = await commit('add');
      await write('a.txt', [...tail, ...block]);
      final moved = await commit('swap block and tail');

      // Plain blame credits whichever side the diff saw as moved to the move.
      expect(await blamed('a.txt'), contains(moved));

      final m = await blamed('a.txt', moves: BlameMoves.withinFile);
      expect(m, everyElement(first));
    });

    test('across files credits lines moved in from another file', () async {
      await write('a.txt', block);
      await write('b.txt', ['header of b']);
      final first = await commit('add');
      await write('a.txt', ['only this now']);
      await write('b.txt', ['header of b', ...block]);
      final moved = await commit('move into b');

      expect((await blamed('b.txt')).sublist(1), everyElement(moved));
      expect(
        await blamed('b.txt', moves: BlameMoves.withinFile),
        isNot(everyElement(first)),
      );
      expect(
        await blamed('b.txt', moves: BlameMoves.acrossFiles),
        everyElement(first),
      );
    });
  });

  group('ignore-revs file', () {
    late String first;
    late String reformat;

    setUp(() async {
      await write('a.txt', ['one', 'two']);
      first = await commit('add');
      await write('a.txt', ['one ', 'two ']);
      reformat = await commit('reformat');
    });

    test('skips the listed revisions when a file is given', () async {
      await File('${dir.path}/revs').writeAsString('# style\n\n$reformat\n');
      expect(await blamed('a.txt'), everyElement(reformat));
      expect(
        await blamed('a.txt', ignoreRevsFile: '${dir.path}/revs'),
        everyElement(first),
      );
    });

    test('a configured file is left out unless passed in', () async {
      await File('${dir.path}/revs').writeAsString('$reformat\n');
      await g(['config', 'blame.ignoreRevsFile', 'revs']);
      expect(await blamed('a.txt'), everyElement(reformat));
    });

    test('a configured file that is missing no longer breaks blame', () async {
      await g(['config', 'blame.ignoreRevsFile', 'gone']);
      expect(await blamed('a.txt'), everyElement(reformat));
    });
  });

  group('blameIgnoreRevsFile', () {
    test('is null with neither config nor root file', () async {
      await write('a.txt', ['x']);
      await commit('add');
      expect(await reader().blameIgnoreRevsFile(), isNull);
    });

    test('finds the root .git-blame-ignore-revs', () async {
      await File('${dir.path}/.git-blame-ignore-revs').writeAsString('\n');
      expect(
        await reader().blameIgnoreRevsFile(),
        '${dir.path}/.git-blame-ignore-revs',
      );
    });

    test('prefers the configured file, relative to the repo', () async {
      await File('${dir.path}/.git-blame-ignore-revs').writeAsString('\n');
      await Directory('${dir.path}/meta').create();
      await File('${dir.path}/meta/revs').writeAsString('\n');
      await g(['config', 'blame.ignoreRevsFile', 'meta/revs']);
      expect(await reader().blameIgnoreRevsFile(), '${dir.path}/meta/revs');
    });

    test(
      'falls back to the root file when the configured one is missing',
      () async {
        await File('${dir.path}/.git-blame-ignore-revs').writeAsString('\n');
        await g(['config', 'blame.ignoreRevsFile', 'gone']);
        expect(
          await reader().blameIgnoreRevsFile(),
          '${dir.path}/.git-blame-ignore-revs',
        );
      },
    );

    test('a directory by that name does not count', () async {
      await Directory('${dir.path}/.git-blame-ignore-revs').create();
      expect(await reader().blameIgnoreRevsFile(), isNull);
    });
  });
}
