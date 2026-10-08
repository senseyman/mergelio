import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/rebase_plan.dart';

void main() {
  RebaseStep pick(String sha, [String message = '']) =>
      RebaseStep(sha, RebaseAction.pick, message: message);

  List<String> ids(List<RebaseStep> steps) => [for (final s in steps) s.id];

  group('exec and break steps', () {
    test('a commit step is keyed by its sha', () {
      expect(pick('aaa').id, 'aaa');
      expect(pick('aaa').isCommit, isTrue);
    });

    test('exec and break are not commits and carry their own id', () {
      const e = RebaseStep.exec('make test', id: 'x1');
      const b = RebaseStep.breakpoint(id: 'b1');
      expect(e.isCommit, isFalse);
      expect(b.isCommit, isFalse);
      expect(e.id, 'x1');
      expect(e.command, 'make test');
      expect(b.action, RebaseAction.breakpoint);
    });

    test('the per-commit action list leaves exec and break out', () {
      expect(rebaseCommitActions, [
        RebaseAction.pick,
        RebaseAction.reword,
        RebaseAction.squash,
        RebaseAction.fixup,
        RebaseAction.drop,
      ]);
    });

    test('exec and break land in the todo where they sit in the plan', () {
      final todo = buildRebaseTodo([
        pick('aaa'),
        const RebaseStep.exec('flutter test', id: 'x1'),
        const RebaseStep.breakpoint(id: 'b1'),
        pick('bbb'),
      ]);
      expect(todo, 'pick aaa\nexec flutter test\nbreak\npick bbb\n');
    });

    test('an exec command is trimmed but otherwise passed as typed', () {
      final todo = buildRebaseTodo([
        pick('aaa'),
        const RebaseStep.exec("  make 'a b' && echo \$HOME  ", id: 'x1'),
      ]);
      expect(todo, contains("exec make 'a b' && echo \$HOME\n"));
    });
  });

  group('update-ref lines', () {
    test('a branch on a commit follows that commit', () {
      final todo = buildRebaseTodo(
        [pick('aaa'), pick('bbb')],
        updateRefs: {
          'aaa': ['stack/one'],
        },
      );
      expect(todo, 'pick aaa\nupdate-ref refs/heads/stack/one\npick bbb\n');
    });

    test('the ref waits for the squash and fixup run under its commit', () {
      final todo = buildRebaseTodo(
        [
          pick('aaa'),
          const RebaseStep('fff', RebaseAction.fixup),
          const RebaseStep('sss', RebaseAction.squash),
          pick('bbb'),
        ],
        updateRefs: {
          'aaa': ['one'],
        },
      );
      expect(
        todo,
        'pick aaa\nfixup fff\nsquash sss\nupdate-ref refs/heads/one\n'
        'pick bbb\n',
      );
    });

    test('the ref goes before an exec so the test runs on the moved ref', () {
      final todo = buildRebaseTodo(
        [pick('aaa'), const RebaseStep.exec('make', id: 'x')],
        updateRefs: {
          'aaa': ['one', 'two'],
        },
      );
      expect(
        todo,
        'pick aaa\nupdate-ref refs/heads/one\nupdate-ref refs/heads/two\n'
        'exec make\n',
      );
    });

    test('a branch on a dropped commit stays at that place in the stack', () {
      final todo = buildRebaseTodo(
        [pick('aaa'), const RebaseStep('bbb', RebaseAction.drop), pick('ccc')],
        updateRefs: {
          'bbb': ['one'],
        },
      );
      expect(todo, 'pick aaa\nupdate-ref refs/heads/one\npick ccc\n');
    });

    test('a branch on a folded commit lands on the folded result', () {
      final todo = buildRebaseTodo(
        [pick('aaa'), const RebaseStep('fff', RebaseAction.fixup), pick('bbb')],
        updateRefs: {
          'aaa': ['on-target'],
          'fff': ['on-fixup'],
        },
      );
      expect(
        todo,
        'pick aaa\nfixup fff\nupdate-ref refs/heads/on-target\n'
        'update-ref refs/heads/on-fixup\npick bbb\n',
      );
    });

    test('a branch on an autosquash target is moved once, after the fold', () {
      final r = autosquash([
        pick('aaa', 'A'),
        pick('bbb', 'B'),
        pick('fff', 'fixup! A'),
      ]);
      final todo = buildRebaseTodo(
        r.steps,
        updateRefs: {
          'aaa': ['on-a'],
        },
      );
      expect(
        todo,
        'pick aaa\nfixup fff\nupdate-ref refs/heads/on-a\npick bbb\n',
      );
    });

    test(
      'leading exec and break steps never get an update-ref of their own',
      () {
        final todo = buildRebaseTodo(
          [
            const RebaseStep.exec('make', id: 'x'),
            const RebaseStep.breakpoint(id: 'b'),
            pick('aaa'),
          ],
          updateRefs: {
            'aaa': ['one'],
          },
        );
        expect(todo, 'exec make\nbreak\npick aaa\nupdate-ref refs/heads/one\n');
      },
    );

    test('a branch on a commit outside the plan is ignored', () {
      final todo = buildRebaseTodo(
        [pick('aaa')],
        updateRefs: {
          'zzz': ['one'],
        },
      );
      expect(todo, 'pick aaa\n');
    });
  });

  group('rebasePlanError with exec and break', () {
    test('a leading exec does not count as the first kept commit', () {
      expect(
        rebasePlanError([
          const RebaseStep.exec('make', id: 'x'),
          const RebaseStep('aaa', RebaseAction.fixup),
        ]),
        isNotNull,
      );
      expect(
        rebasePlanError([
          const RebaseStep.breakpoint(id: 'b'),
          pick('aaa'),
          const RebaseStep('bbb', RebaseAction.fixup),
        ]),
        isNull,
      );
    });

    test('an empty exec command is rejected', () {
      expect(
        rebasePlanError([pick('aaa'), const RebaseStep.exec('  ', id: 'x')]),
        isNotNull,
      );
    });

    test('a multi-line exec command is rejected', () {
      expect(
        rebasePlanError([
          pick('aaa'),
          const RebaseStep.exec('make\nrm -rf /', id: 'x'),
        ]),
        isNotNull,
      );
    });
  });

  group('applyPreset with exec and break', () {
    test('only commit steps change; exec and break keep their place', () {
      final out = applyPreset([
        const RebaseStep.exec('make', id: 'x'),
        pick('aaa'),
        const RebaseStep.breakpoint(id: 'b'),
        pick('bbb'),
      ], RebasePreset.squashAll);
      expect(ids(out), ['x', 'aaa', 'b', 'bbb']);
      expect(
        [for (final s in out) s.action],
        [
          RebaseAction.exec,
          RebaseAction.pick,
          RebaseAction.breakpoint,
          RebaseAction.squash,
        ],
      );
      expect(out.first.command, 'make');
    });
  });

  group('autosquashSubject', () {
    test('reads fixup and squash prefixes', () {
      expect(autosquashSubject('fixup! Add login'), (
        kind: RebaseAction.fixup,
        target: 'Add login',
      ));
      expect(autosquashSubject('squash! Add login'), (
        kind: RebaseAction.squash,
        target: 'Add login',
      ));
    });

    test('a stacked prefix keeps the outer kind and the innermost target', () {
      expect(autosquashSubject('fixup! squash! fixup! Add login'), (
        kind: RebaseAction.fixup,
        target: 'Add login',
      ));
    });

    test('an ordinary subject or amend! is not a candidate', () {
      expect(autosquashSubject('Add login'), isNull);
      expect(autosquashSubject('amend! Add login'), isNull);
      expect(autosquashSubject('fixup!Add login'), isNull);
      expect(autosquashSubject('fixup! '), isNull);
    });
  });

  group('autosquash', () {
    test('moves a fixup under its target and marks it', () {
      final r = autosquash([
        pick('aaa', 'Add login'),
        pick('bbb', 'Add logout'),
        pick('fff', 'fixup! Add login'),
      ]);
      expect(ids(r.steps), ['aaa', 'fff', 'bbb']);
      expect(r.steps[1].action, RebaseAction.fixup);
      expect(r.pairs, {'fff': 'aaa'});
    });

    test('squash! becomes a squash', () {
      final r = autosquash([
        pick('aaa', 'Add login'),
        pick('sss', 'squash! Add login'),
      ]);
      expect(r.steps[1].action, RebaseAction.squash);
    });

    test('several fixups keep their order under the same target', () {
      final r = autosquash([
        pick('aaa', 'A'),
        pick('bbb', 'B'),
        pick('f1', 'fixup! A'),
        pick('f2', 'squash! A'),
      ]);
      expect(ids(r.steps), ['aaa', 'f1', 'f2', 'bbb']);
    });

    test('a target can be named by sha prefix, then by subject prefix', () {
      final r = autosquash([
        pick('abc123', 'Add login form'),
        pick('bbb', 'B'),
        pick('f1', 'fixup! abc1'),
        pick('f2', 'fixup! Add login'),
      ]);
      expect(r.pairs, {'f1': 'abc123', 'f2': 'abc123'});
    });

    test('an exact subject wins over a prefix match', () {
      final r = autosquash([
        pick('aaa', 'Add login form'),
        pick('bbb', 'Add login'),
        pick('f1', 'fixup! Add login'),
      ]);
      expect(r.pairs, {'f1': 'bbb'});
    });

    test('a fixup whose target comes later or is missing stays put', () {
      final r = autosquash([
        pick('f1', 'fixup! B'),
        pick('bbb', 'B'),
        pick('f2', 'fixup! Nope'),
      ]);
      expect(ids(r.steps), ['f1', 'bbb', 'f2']);
      expect(r.pairs, isEmpty);
      expect(r.steps.every((s) => s.action == RebaseAction.pick), isTrue);
    });

    test('a fixup of a fixup lands with the group of the real target', () {
      final r = autosquash([
        pick('aaa', 'A'),
        pick('bbb', 'B'),
        pick('f1', 'fixup! A'),
        pick('f2', 'fixup! fixup! A'),
      ]);
      expect(ids(r.steps), ['aaa', 'f1', 'f2', 'bbb']);
    });

    test('exec and break steps stay with the commit they followed', () {
      final r = autosquash([
        pick('aaa', 'A'),
        const RebaseStep.exec('make', id: 'x'),
        pick('bbb', 'B'),
        pick('f1', 'fixup! A'),
      ]);
      expect(ids(r.steps), ['aaa', 'f1', 'x', 'bbb']);
    });

    test('nothing to pair returns the plan unchanged', () {
      final steps = [pick('aaa', 'A'), pick('bbb', 'B')];
      final r = autosquash(steps);
      expect(ids(r.steps), ['aaa', 'bbb']);
      expect(r.pairs, isEmpty);
    });
  });

  group('undoAutosquash', () {
    test('puts paired commits back in their original place as picks', () {
      final original = [
        pick('aaa', 'A'),
        pick('bbb', 'B'),
        pick('f1', 'fixup! A'),
        pick('ccc', 'C'),
      ];
      final r = autosquash(original);
      final back = undoAutosquash(r.steps, original, r.pairs.keys.toSet());
      expect(ids(back), ['aaa', 'bbb', 'f1', 'ccc']);
      expect(back.every((s) => s.action == RebaseAction.pick), isTrue);
    });

    test('exec steps added meanwhile survive', () {
      final original = [
        pick('aaa', 'A'),
        pick('bbb', 'B'),
        pick('f1', 'fixup! A'),
      ];
      final r = autosquash(original);
      final edited = [...r.steps, const RebaseStep.exec('make', id: 'x')];
      final back = undoAutosquash(edited, original, r.pairs.keys.toSet());
      expect(ids(back), ['aaa', 'bbb', 'f1', 'x']);
    });

    test('a paired commit whose predecessor was paired too follows it', () {
      final original = [
        pick('aaa', 'A'),
        pick('bbb', 'B'),
        pick('f1', 'fixup! A'),
        pick('f2', 'fixup! A'),
      ];
      final r = autosquash(original);
      final back = undoAutosquash(r.steps, original, r.pairs.keys.toSet());
      expect(ids(back), ['aaa', 'bbb', 'f1', 'f2']);
    });

    test('a paired commit that was first goes back to the top', () {
      final original = [pick('aaa', 'A'), pick('f1', 'fixup! A')];
      // Moved by hand above its target after autosquash.
      final moved = [
        const RebaseStep('f1', RebaseAction.fixup, message: 'fixup! A'),
        pick('aaa', 'A'),
      ];
      final back = undoAutosquash(moved, original, {'f1'});
      expect(ids(back), ['aaa', 'f1']);
    });
  });

  group('parseRebaseStop', () {
    test('a failed exec is the last line of done', () {
      expect(
        parseRebaseStop('pick aaa\nexec make test\n'),
        const RebaseStop.exec('make test'),
      );
      expect(
        parseRebaseStop('pick aaa\nx make test'),
        const RebaseStop.exec('make test'),
      );
    });

    test('a break is the last line of done', () {
      expect(
        parseRebaseStop('pick aaa\nbreak\n'),
        const RebaseStop.breakpoint(),
      );
      expect(parseRebaseStop('pick aaa\nb\n'), const RebaseStop.breakpoint());
    });

    test('a rejected reword is its own stop, not an exec the user wrote', () {
      final todo = buildRebaseTodo([
        const RebaseStep('aaa', RebaseAction.reword, message: 'new'),
      ]);
      expect(parseRebaseStop(todo), const RebaseStop.reword());
      expect(const RebaseStop.reword().isExec, isFalse);
    });

    test(
      'a user exec that happens to start like a reword is still an exec',
      () {
        const line = "exec printf '%b' \"\$MSG\" > out.txt";
        expect(
          parseRebaseStop('pick aaa\n$line\n'),
          isA<RebaseStop>().having((s) => s.kind, 'kind', RebaseStopKind.exec),
        );
        expect(todoRunsUserExec('pick aaa\n$line\n'), isTrue);
      },
    );

    test('only a reword amend counts as the internal exec', () {
      final todo = buildRebaseTodo([
        const RebaseStep(
          'aaa',
          RebaseAction.reword,
          message: 'x',
          sign: true,
          noVerify: true,
        ),
      ]);
      expect(todoRunsUserExec(todo), isFalse);
      expect(parseRebaseStop(todo), const RebaseStop.reword());
    });

    test('anything else is not a break or exec stop', () {
      expect(parseRebaseStop('pick aaa\n'), isNull);
      expect(parseRebaseStop(''), isNull);
      expect(parseRebaseStop('exec make\npick aaa\n'), isNull);
    });
  });

  test('withAction is for commit steps only', () {
    expect(
      () =>
          const RebaseStep.exec('make', id: 'x').withAction(RebaseAction.pick),
      throwsA(isA<AssertionError>()),
    );
  });

  group('supportsUpdateRefTodo', () {
    for (final (v, want) in [
      ('git version 2.37.1', false),
      ('git version 2.38.0', true),
      ('git version 2.55.0.windows.1', true),
      ('git version 3.0.0', true),
      ('not git', false),
    ]) {
      test(v, () => expect(supportsUpdateRefTodo(v), want));
    }
  });

  test('fixupSubject prefixes the target subject', () {
    expect(fixupSubject('Add login'), 'fixup! Add login');
  });
}
