import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/bisect.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/git_writer.dart';
import 'package:mergelio/state/feedback.dart';
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
      expect(vars.steps, greaterThanOrEqualTo(0));

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

  // Git does not stop a commit acquiring two verdicts: marking one bad after
  // it was already marked good moves refs/bisect/bad onto it, complains, and
  // leaves the stale good ref in place. Read literally that sha appears on
  // both sides of the range, rev-list refuses it, and the bar sits on an
  // uncomputed -1 forever with no way out but Reset.
  test(
    'a commit marked both good and bad still reads a usable state',
    () async {
      final repo = await makeRepo(commits: 12, breakAt: 8);
      addTearDown(() => repo.delete(recursive: true));

      final container = ProviderContainer(
        overrides: [gitServiceProvider.overrideWithValue(svc)],
      );
      addTearDown(container.dispose);

      final actions = actionsFor(container, repo.path);
      final shas = await shasOldestFirst(repo.path);
      await actions.startBisect(shas.last);
      await actions.markBisect(shas.first, BisectKind.good);

      final midpoint = (await actions.bisectState())!.currentSha;
      await actions.markBisect(midpoint, BisectKind.good);
      // Contradicts the verdict just given. git exits non-zero here, so this
      // goes through markBisect (which reports rather than throws) exactly as
      // it would from the button.
      await actions.markBisect(midpoint, BisectKind.bad);

      // Both refs really are on disk: the state below is read from a genuinely
      // self-contradictory repository, not a hypothetical one.
      final refsOut = await out(repo.path, [
        'for-each-ref',
        '--format=%(objectname) %(refname)',
        'refs/bisect',
      ]);
      expect(refsOut, contains('$midpoint refs/bisect/bad'));
      expect(refsOut, contains('$midpoint refs/bisect/good-$midpoint'));

      final state = await actions.bisectState();
      expect(state, isNotNull);
      expect(
        state!.marks.where((m) => m.sha == midpoint),
        hasLength(1),
        reason: 'one commit must carry one verdict',
      );
      expect(state.kindOf(midpoint), BisectKind.bad);
      expect(state.marks.where((m) => m.sha == shas.first), hasLength(1));
      expect(state.kindOf(shas.first), BisectKind.good);
      // The whole point: git was asked a range it could answer, so the hunt
      // reports real counts instead of the -1 that means "never computed".
      expect(state.revisionsLeft, greaterThanOrEqualTo(0));
      expect(state.steps, greaterThanOrEqualTo(0));

      await actions.resetBisect();
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

  // --- bisect run ------------------------------------------------------------

  // A run hands the rest of the hunt to a command, and how it ended has to be
  // read back out of git's exit code and stderr. Every wording the classifier
  // keys on is pinned below against a real run: a message git prints on stdout,
  // or stops printing, is invisible to a classifier reading stderr.

  /// A hunt opened on [repo] with the newest commit bad and the oldest good,
  /// ready for a run to finish. Returns the actions it was opened through.
  Future<RepoActions> openHunt(
    ProviderContainer container,
    Directory repo,
  ) async {
    final actions = actionsFor(container, repo.path);
    final shas = await shasOldestFirst(repo.path);
    await actions.startBisect(shas.last);
    await actions.markBisect(shas.first, BisectKind.good);
    return actions;
  }

  ProviderContainer containerForTest() {
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(svc)],
    );
    // Disposing the container disposes RepoActions with it, which cancels the
    // refresh timer a run leaves behind. Without that the timer outlives the
    // test and fires against a disposed container.
    addTearDown(container.dispose);
    return container;
  }

  test('a run over a known break lands on the first bad commit', () async {
    final repo = await makeRepo(commits: 8, breakAt: 5);
    addTearDown(() => repo.delete(recursive: true));
    final actions = await openHunt(containerForTest(), repo);

    // Exit 0 says good and exit 1 says bad, decided by reading the tree git
    // has just checked out — the signal a person bisecting by hand uses.
    final outcome = await actions.runBisect('test ! -f broken.marker');

    expect(outcome, BisectRunOutcome.finished);
    final state = await actions.bisectState();
    expect(state, isNotNull);
    expect(state!.finished, isTrue);
    // Commit 5 (1-based) is the one that introduced broken.marker, so index
    // 4 of the oldest-first list is the true first bad commit.
    expect(state.firstBad, (await shasOldestFirst(repo.path))[4]);

    await actions.resetBisect();
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a command git cannot run is not mistaken for a verdict', () async {
    final repo = await makeRepo(commits: 6, breakAt: 4);
    addTearDown(() => repo.delete(recursive: true));
    final actions = await openHunt(containerForTest(), repo);

    final outcome = await actions.runBisect('./no-such-script.sh');

    expect(outcome, BisectRunOutcome.commandUnrunnable);
    // The shell exits 127 for a command it cannot find, which sits inside
    // the range git otherwise reads as a verdict. Taken as one it would
    // convict a commit the command never actually tested, so nothing at all
    // must have been decided here.
    final state = await actions.bisectState();
    expect(state, isNotNull);
    expect(state!.firstBad, isNull);

    await actions.resetBisect();
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'a command that modifies a tracked file reports the dirtied tree',
    () async {
      final repo = await makeRepo(commits: 8, breakAt: 5);
      addTearDown(() => repo.delete(recursive: true));
      final actions = await openHunt(containerForTest(), repo);

      final outcome = await actions.runBisect(
        'echo dirt >> f.txt; test ! -f broken.marker',
      );

      // git closes this with `bisect run failed: 'git bisect good' exited with
      // error code -1`, which names neither the command nor the change that
      // stopped the checkout — which is why the tree is asked about separately
      // instead of being read out of git's words.
      expect(outcome, BisectRunOutcome.treeDirtied);
      expect(
        await out(repo.path, ['status', '--porcelain', '--untracked-files=no']),
        isNotEmpty,
      );
      final state = await actions.bisectState();
      expect(state, isNotNull);
      expect(state!.firstBad, isNull);

      await g(repo.path, ['checkout', '--', '.']);
      await actions.resetBisect();
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('a run that can test nothing reports an exhausted hunt', () async {
    final repo = await makeRepo(commits: 8, breakAt: 5);
    addTearDown(() => repo.delete(recursive: true));
    final actions = await openHunt(containerForTest(), repo);

    // 125 is git's "cannot tell" code, so every candidate is skipped in turn
    // until the hunt has nothing left to try.
    final outcome = await actions.runBisect('exit 125');

    expect(outcome, BisectRunOutcome.exhausted);
    final state = await actions.bisectState();
    expect(state, isNotNull);
    expect(state!.firstBad, isNull);

    await actions.resetBisect();
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a command that writes only untracked files still finishes', () async {
    final repo = await makeRepo(commits: 8, breakAt: 5);
    addTearDown(() => repo.delete(recursive: true));
    final actions = await openHunt(containerForTest(), repo);

    // A scratch file of its own is the normal way a test command works. git
    // checks the next commit out straight through it, so the hunt lands.
    final outcome = await actions.runBisect(
      'echo x >> scratch.log; test ! -f broken.marker',
    );

    expect(outcome, BisectRunOutcome.finished);
    expect(
      (await actions.bisectState())!.firstBad,
      (await shasOldestFirst(repo.path))[4],
    );
    expect(
      await out(repo.path, ['status', '--porcelain']),
      contains('scratch.log'),
    );

    await actions.resetBisect();
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('a scratch file left behind does not hide how the run ended', () async {
    final repo = await makeRepo(commits: 8, breakAt: 5);
    addTearDown(() => repo.delete(recursive: true));
    final actions = await openHunt(containerForTest(), repo);

    final outcome = await actions.runBisect('echo x >> scratch.log; exit 125');

    // The run really did leave the tree untidy, but with a file git never
    // had to check out over. Reported as a dirtied tree it would tell the
    // user their command modified tracked files, which it did not, and hide
    // the only thing they can act on: every candidate was skipped.
    expect(outcome, BisectRunOutcome.exhausted);
    expect(
      await out(repo.path, ['status', '--porcelain']),
      contains('scratch.log'),
    );
    expect(
      await out(repo.path, ['status', '--porcelain', '--untracked-files=no']),
      isEmpty,
    );

    await actions.resetBisect();
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'the words the classifier keys on are the words git puts on stderr',
    () async {
      final repo = await makeRepo(commits: 8, breakAt: 5);
      addTearDown(() => repo.delete(recursive: true));
      final shas = await shasOldestFirst(repo.path);

      Future<void> open() async {
        await g(repo.path, ['bisect', 'start']);
        await g(repo.path, ['bisect', 'bad', shas.last]);
        await g(repo.path, ['bisect', 'good', shas.first]);
      }

      // Exhaustion. git announces "We cannot bisect more!" on stdout, where a
      // classifier reading stderr never sees it; this is the line it does get.
      await open();
      final skipped = await svc.run(
        bisectRunArgs('exit 125'),
        repoPath: repo.path,
        environment: bisectRunMessageEnv,
      );
      expect(skipped.ok, isFalse);
      expect(skipped.err, contains('bisect run cannot continue any more'));
      expect(
        classifyBisectRun(skipped.exitCode, skipped.err, treeDirty: false),
        BisectRunOutcome.exhausted,
      );
      await g(repo.path, ['bisect', 'reset']);

      // A command that cannot be executed at all.
      await open();
      final missing = await svc.run(
        bisectRunArgs('./no-such-script.sh'),
        repoPath: repo.path,
        environment: bisectRunMessageEnv,
      );
      expect(missing.ok, isFalse);
      expect(missing.err, contains('bogus exit code'));
      expect(
        classifyBisectRun(missing.exitCode, missing.err, treeDirty: false),
        BisectRunOutcome.commandUnrunnable,
      );
      await g(repo.path, ['bisect', 'reset']);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // git translates the endings a run reports. The app ships Ukrainian, so a
  // classifier that only recognises the English wording mislabels a real
  // user's run. Measured here against the system git rather than argued
  // about: the same two runs go through twice, once with the user's locale
  // left in charge and once with what production sends.
  test('a run classifies the same under a non-English locale', () async {
    const ukrainian = {'LC_ALL': 'uk_UA.UTF-8', 'LANGUAGE': 'uk'};

    final repo = await makeRepo(commits: 8, breakAt: 5);
    addTearDown(() => repo.delete(recursive: true));
    final shas = await shasOldestFirst(repo.path);

    Future<void> open() async {
      await g(repo.path, ['bisect', 'start']);
      await g(repo.path, ['bisect', 'bad', shas.last]);
      await g(repo.path, ['bisect', 'good', shas.first]);
    }

    Future<GitResult> runUnder(
      String command,
      Map<String, String> environment,
    ) async {
      await open();
      final r = await svc.run(
        bisectRunArgs(command),
        repoPath: repo.path,
        environment: environment,
      );
      await g(repo.path, ['bisect', 'reset']);
      return r;
    }

    // First: prove this machine really does have git's Ukrainian
    // translation. Without that check the assertions below would pass on an
    // English-only runner while proving nothing at all.
    final translated = await runUnder('./no-such-script.sh', ukrainian);
    if (translated.err.contains('bogus exit code')) {
      markTestSkipped(
        'git here has no Ukrainian translation, so a locale-dependent '
        'classifier cannot be caught out on this machine',
      );
      return;
    }
    expect(
      classifyBisectRun(translated.exitCode, translated.err, treeDirty: false),
      BisectRunOutcome.failed,
      reason:
          'the untranslated reading really is wrong under uk_UA — this '
          'is the defect the override below exists to close',
    );

    // Now with what production sends: the user's locale is still uk_UA, and
    // git answers in English anyway.
    final pinned = await runUnder('./no-such-script.sh', {
      ...ukrainian,
      ...bisectRunMessageEnv,
    });
    expect(pinned.err, contains('bogus exit code'));
    expect(
      classifyBisectRun(pinned.exitCode, pinned.err, treeDirty: false),
      BisectRunOutcome.commandUnrunnable,
    );

    // Exhaustion is read off the exit code, so it survives the Ukrainian
    // locale with no override at all.
    final skipped = await runUnder('exit 125', ukrainian);
    expect(
      skipped.err,
      isNot(contains('bisect run cannot continue any more')),
      reason: 'the Ukrainian locale must really be in force here',
    );
    expect(
      classifyBisectRun(skipped.exitCode, skipped.err, treeDirty: false),
      BisectRunOutcome.exhausted,
    );
  }, timeout: const Timeout(Duration(seconds: 180)));

  // End to end through the production path, for a user whose whole
  // environment is Ukrainian. Every git command the actions run gets the
  // Ukrainian locale underneath it; only what `bisectRun` sends of its own
  // sits on top, so this fails unless those overrides really do win.
  test('a run through the actions survives a Ukrainian environment', () async {
    final repo = await makeRepo(commits: 6, breakAt: 4);
    addTearDown(() => repo.delete(recursive: true));

    final ukrainian = _LocalisedGit(svc, const {
      'LC_ALL': 'uk_UA.UTF-8',
      'LANGUAGE': 'uk',
    });
    final container = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(ukrainian)],
    );
    addTearDown(container.dispose);

    // `git bisect bad` outside a bisect is git's shortest translated
    // complaint. No Cyrillic in it means this machine has no Ukrainian
    // messages, so nothing here could catch out a classifier that needs
    // English — say so rather than pass on a vacuous assertion.
    final probe = await ukrainian.run(['bisect', 'bad'], repoPath: repo.path);
    if (!_cyrillic.hasMatch(probe.err)) {
      markTestSkipped('git here has no Ukrainian translation');
      return;
    }

    final actions = container.read(repoActionsProvider(repo.path));
    final shas = await shasOldestFirst(repo.path);
    await actions.startBisect(shas.last);
    await actions.markBisect(shas.first, BisectKind.good);

    final outcome = await actions.runBisect('./no-such-script.sh');

    expect(outcome, BisectRunOutcome.commandUnrunnable);
    await actions.resetBisect();
  }, timeout: const Timeout(Duration(seconds: 180)));
  // Cancelling kills git and only git: anything git spawned in turn survives
  // it, which is documented on GitCancel and left as it is on purpose. What
  // was never tested is what those survivors do to the wait: they hold the
  // write end of git's stdout and stderr, so a join on that output never
  // completes and the cancel appears to do nothing at all.
  //
  // Measured before the fix: `runBisect` had not returned twelve seconds after
  // the user pressed Cancel, with git already dead and its command still
  // running.
  test(
    'cancelling a run whose command outlives git still returns',
    () async {
      // Distinctive enough to find in the process table, and killed on
      // tear-down so nothing is left behind.
      const command = 'sleep 137';
      Future<int> survivors() async {
        final r = await Process.run('sh', [
          '-c',
          'ps -ax -o command | grep -c "^$command\$" || true',
        ]);
        return int.tryParse('${r.stdout}'.trim()) ?? 0;
      }

      addTearDown(() => Process.run('pkill', ['-f', command]));

      final repo = await makeRepo(commits: 8, breakAt: 5);
      addTearDown(() => repo.delete(recursive: true));
      final container = containerForTest();
      final actions = await openHunt(container, repo);

      final run = actions.runBisect(command);

      // Waits for git to have actually spawned the command, rather than
      // guessing at a delay: cancelling before the child exists would kill
      // git while nothing held its pipes, which is not the case under test.
      for (var i = 0; i < 100 && await survivors() == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        await survivors(),
        greaterThan(0),
        reason: 'git never got as far as running the command',
      );

      // The app's own Cancel, reached the way the status bar reaches it.
      container.read(busyProvider)!.onCancel!();

      final outcome = await run.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail(
          'runBisect never returned after the cancel: the command git left '
          'behind still holds the output pipes open',
        ),
      );

      expect(outcome, BisectRunOutcome.cancelled);
      // The premise: the survivor really did outlive git, so the wait this
      // returned from was a wait that could never have ended on its own.
      expect(
        await survivors(),
        greaterThan(0),
        reason:
            'without a survivor holding the pipes there was nothing to '
            'stop waiting for',
      );
      // Marks already recorded stay: abandoning the automation is not
      // abandoning the hunt.
      expect(await actions.bisectState(), isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
    skip: Platform.isWindows ? 'no `sleep`/`ps` on Windows' : false,
  );
}

final _cyrillic = RegExp(r'[\u0400-\u04FF]');

/// Every command this wraps runs under [locale], unless the caller asked for
/// an override of its own — which then wins, key by key, exactly as
/// `Process.start` merges over the inherited environment.
///
/// Stands in for a user whose shell is not English. No test can change its own
/// process's environment, and that is the only other place the locale could
/// come from.
class _LocalisedGit implements GitService {
  final GitService inner;
  final Map<String, String> locale;
  _LocalisedGit(this.inner, this.locale);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) => inner.run(
    args,
    repoPath: repoPath,
    timeout: timeout,
    environment: {...locale, ...?environment},
    cancel: cancel,
    stdin: stdin,
  );

  @override
  Future<String> version() => inner.version();

  @override
  Future<bool> isRepository(String path) => inner.isRepository(path);
}
