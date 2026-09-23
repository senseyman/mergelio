import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/repo_actions.dart';

/// Integration tests: drive a real temporary repository through the system
/// `git` binary, end to end, through the production bisect code paths
/// (`GitWriter` for mutations, `RepoActions.bisectState()` for reading state
/// back). Every other bisect test feeds the parsers hand-written strings;
/// this file is the one place that checks those strings against what git
/// itself actually prints.
void main() {
  const svc = SystemGitService();

  Future<void> g(String repoPath, List<String> args) async {
    final r = await svc.run(args, repoPath: repoPath);
    if (!r.ok) {
      throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }
  }

  Future<String> out(String repoPath, List<String> args) async {
    final r = await svc.run(args, repoPath: repoPath);
    if (!r.ok) {
      throw StateError('git ${args.join(' ')} failed: ${r.err}');
    }
    return r.out;
  }

  /// A linear chain of [commits] commits on `main`. Starting at commit
  /// number [breakAt] (1-based) every commit also carries `broken.marker`,
  /// which is never removed again, so its presence in the checked-out
  /// working tree is a real, on-disk signal of whether that commit (and
  /// everything after it) has the break — exactly what a person running
  /// a bisect by hand would look at.
  Future<Directory> makeRepo({
    required int commits,
    required int breakAt,
  }) async {
    final dir = await Directory.systemTemp.createTemp('mergelio_bisect_');
    await g(dir.path, ['init', '-q']);
    await g(dir.path, ['symbolic-ref', 'HEAD', 'refs/heads/main']);
    await g(dir.path, ['config', 'user.email', 't@example.com']);
    await g(dir.path, ['config', 'user.name', 'Tester']);
    await g(dir.path, ['config', 'commit.gpgsign', 'false']);

    for (var i = 1; i <= commits; i++) {
      await File('${dir.path}/f.txt').writeAsString('$i\n');
      if (i == breakAt) {
        await File('${dir.path}/broken.marker').writeAsString('broken\n');
      }
      await g(dir.path, ['add', '-A']);
      await g(dir.path, ['commit', '-q', '-m', 'commit $i']);
    }
    return dir;
  }

  Future<List<String>> shasOldestFirst(String repoPath) async => (await out(
    repoPath,
    ['rev-list', '--reverse', 'HEAD'],
  )).split('\n').where((l) => l.isNotEmpty).toList();

  bool isBroken(String repoPath) =>
      File('$repoPath/broken.marker').existsSync();

  RepoActions actionsFor(ProviderContainer container, String repoPath) =>
      container.read(repoActionsProvider(repoPath));

  test('a full hunt over a known break finds the first bad commit', () async {
    final repo = await makeRepo(commits: 10, breakAt: 5);
    addTearDown(() => repo.delete(recursive: true));

    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(container.dispose);

    final actions = actionsFor(container, repo.path);
    final shas = await shasOldestFirst(repo.path);
    expect(shas, hasLength(10));

    await actions.startBisect(shas.last); // newest commit is bad
    await actions.markBisect(shas.first, BisectKind.good); // oldest is good

    var state = await actions.bisectState();
    var iterations = 0;
    while (state != null && !state.finished) {
      iterations++;
      if (iterations > 20) {
        fail(
          'bisect did not converge within 20 iterations; last state: '
          'currentSha=${state.currentSha} revisionsLeft=${state.revisionsLeft}',
        );
      }
      final broken = isBroken(repo.path);
      await actions.markBisect(
        state.currentSha,
        broken ? BisectKind.bad : BisectKind.good,
      );
      state = await actions.bisectState();
    }

    expect(state, isNotNull, reason: 'bisectState went null before finishing');
    expect(state!.finished, isTrue);
    // Commit 5 (1-based) is index 4 in the oldest-first list; it is the
    // commit that introduced broken.marker, so it is the true first bad.
    expect(state.firstBad, shas[4]);

    await actions.resetBisect();
    expect(await actions.bisectState(), isNull);
    expect(await out(repo.path, ['symbolic-ref', '--short', 'HEAD']), 'main');
  });

  test(
    'parsers read real for-each-ref and rev-list --bisect-vars output',
    () async {
      final repo = await makeRepo(commits: 6, breakAt: 4);
      addTearDown(() => repo.delete(recursive: true));

      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(svc)],
      );
      addTearDown(container.dispose);

      final actions = actionsFor(container, repo.path);
      final shas = await shasOldestFirst(repo.path);

      // Mid-bisect: exactly one bad mark (newest) and one good mark (oldest),
      // the state right after a hunt is opened.
      await actions.startBisect(shas.last);
      await actions.markBisect(shas.first, BisectKind.good);

      final refsOut = await out(repo.path, [
        'for-each-ref',
        '--format=%(objectname) %(refname)',
        'refs/bisect',
      ]);
      final marks = parseBisectRefs(refsOut);
      expect(
        marks.where((m) => m.kind == BisectKind.bad).map((m) => m.sha),
        contains(shas.last),
      );
      expect(
        marks.where((m) => m.kind == BisectKind.good).map((m) => m.sha),
        contains(shas.first),
      );

      final args = bisectVarsArgs(marks);
      expect(args, isNotEmpty);
      final varsOut = await out(repo.path, [
        'rev-list',
        '--bisect-vars',
        ...args,
      ]);
      final vars = parseBisectVars(varsOut);
      expect(vars.nr, greaterThanOrEqualTo(0));
      expect(vars.rev, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(shas, contains(vars.rev));

      await actions.resetBisect();
    },
  );

  test(
    'bisectState is non-null but empty right after a bare bisect start',
    () async {
      final repo = await makeRepo(commits: 4, breakAt: 3);
      addTearDown(() => repo.delete(recursive: true));

      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(svc)],
      );
      addTearDown(container.dispose);

      // Bypass RepoActions here: this is the state git itself produces the
      // instant `bisect start` runs, before any verdict exists, which is the
      // "mark a bad commit to begin" state the bar renders.
      await g(repo.path, ['bisect', 'start']);

      final state = await actionsFor(container, repo.path).bisectState();
      expect(state, isNotNull);
      expect(state!.marks, isEmpty);
      expect(state.finished, isFalse);
      expect(state.revisionsLeft, -1);

      await g(repo.path, ['bisect', 'reset']);
    },
  );

  test('bisectState reads a lone good mark with no bad yet', () async {
    final repo = await makeRepo(commits: 4, breakAt: 3);
    addTearDown(() => repo.delete(recursive: true));

    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(container.dispose);

    final shas = await shasOldestFirst(repo.path);
    await g(repo.path, ['bisect', 'start']);
    await g(repo.path, ['bisect', 'good', shas.first]);

    final state = await actionsFor(container, repo.path).bisectState();
    expect(state, isNotNull);
    expect(state!.marks, hasLength(1));
    expect(state.marks.single.kind, BisectKind.good);
    expect(state.marks.single.sha, shas.first);
    expect(state.finished, isFalse);
    expect(state.firstBad, isNull);
    // bisectVarsArgs needs both ends; with only a good mark it stays -1
    // rather than walking the whole history to answer.
    expect(state.revisionsLeft, -1);

    await g(repo.path, ['bisect', 'reset']);
  });

  test('bisectState reads marks recorded under renamed terms', () async {
    final repo = await makeRepo(commits: 8, breakAt: 5);
    addTearDown(() => repo.delete(recursive: true));

    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(container.dispose);

    final shas = await shasOldestFirst(repo.path);
    // A repository may name the two ends whatever it likes, and git then
    // names the refs it writes after those words — refs/bisect/broken and
    // refs/bisect/works-<sha> here, with not a good or a bad among them.
    await g(repo.path, [
      'bisect',
      'start',
      '--term-old=works',
      '--term-new=broken',
    ]);
    await g(repo.path, ['bisect', 'broken', shas.last]);
    await g(repo.path, ['bisect', 'works', shas.first]);

    final state = await actionsFor(container, repo.path).bisectState();
    expect(state, isNotNull);
    expect(state!.terms.bad, 'broken');
    expect(state.terms.good, 'works');
    expect(
      state.marks.where((m) => m.kind == BisectKind.bad).map((m) => m.sha),
      contains(shas.last),
    );
    expect(
      state.marks.where((m) => m.kind == BisectKind.good).map((m) => m.sha),
      contains(shas.first),
    );
    // Both ends are known, so git can size the range: a -1 here would mean
    // the marks never made it through, and the bar would go on asking for a
    // bad commit that was marked several steps ago.
    expect(state.revisionsLeft, greaterThanOrEqualTo(0));
    expect(state.awaitingGood, isFalse);

    await g(repo.path, ['bisect', 'reset']);
  });

  test('a skip under renamed terms still reads back as a skip', () async {
    final repo = await makeRepo(commits: 8, breakAt: 5);
    addTearDown(() => repo.delete(recursive: true));

    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(svc)],
    );
    addTearDown(container.dispose);

    final shas = await shasOldestFirst(repo.path);
    await g(repo.path, [
      'bisect',
      'start',
      '--term-old=works',
      '--term-new=broken',
    ]);
    await g(repo.path, ['bisect', 'broken', shas.last]);
    await g(repo.path, ['bisect', 'works', shas.first]);
    await g(repo.path, ['bisect', 'skip']);

    final state = await actionsFor(container, repo.path).bisectState();
    expect(state, isNotNull);
    expect(
      state!.marks.where((m) => m.kind == BisectKind.skip),
      isNotEmpty,
      reason: 'skip refs keep their own name even when the terms are renamed',
    );

    await g(repo.path, ['bisect', 'reset']);
  });
}
