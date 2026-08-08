import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/ui/graph/commit_columns.dart';

Commit _c(
  String sha, {
  List<String> parents = const [],
  List<GitRef> refs = const [],
}) => Commit(
  sha: sha,
  message: '',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026),
  parents: parents,
  refs: refs,
);

GitRef _local(String name) => GitRef(kind: RefKind.local, name: name);
GitRef _remote(String name) => GitRef(kind: RefKind.remote, name: name);
GitRef _head() => const GitRef(kind: RefKind.head, name: 'HEAD');

void main() {
  test('formats dates as "Mon D, YYYY"', () {
    expect(formatCommitDate(DateTime(2026, 7, 2)), 'Jul 2, 2026');
    expect(formatCommitDate(DateTime(2025, 12, 31)), 'Dec 31, 2025');
    expect(formatCommitDate(DateTime(2024, 1, 9)), 'Jan 9, 2024');
  });

  test('the time of day is left out unless it is asked for', () {
    final d = DateTime(2026, 7, 2, 14, 33);
    expect(formatCommitDate(d), 'Jul 2, 2026');
    expect(formatCommitDate(d, format: 'iso'), '2026-07-02');
    expect(formatCommitDate(d, format: 'short'), '07/02/26');
  });

  test('withTime appends a zero-padded 24-hour clock to every format', () {
    final d = DateTime(2026, 7, 2, 4, 5);
    expect(formatCommitDate(d, withTime: true), 'Jul 2, 2026 04:05');
    expect(
      formatCommitDate(d, format: 'iso', withTime: true),
      '2026-07-02 04:05',
    );
    expect(
      formatCommitDate(d, format: 'short', withTime: true),
      '07/02/26 04:05',
    );
  });

  test('a UTC commit date is rendered in the local time zone', () {
    // Author dates arrive as `%aI`, which DateTime.parse turns into a UTC
    // instant — reading it out field by field would show the UTC wall clock.
    final utc = DateTime.utc(2026, 7, 2, 22, 45);
    final local = utc.toLocal();
    expect(
      formatCommitDate(utc, format: 'iso', withTime: true),
      formatCommitDate(local, format: 'iso', withTime: true),
    );
    expect(
      formatCommitDate(utc, format: 'iso', withTime: true),
      '${local.year}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}',
    );
  });

  group('clock', () {
    test('12h renders an AM/PM clock with no leading zero on the hour', () {
      expect(
        formatCommitDate(
          DateTime(2026, 7, 2, 14, 33),
          withTime: true,
          clock: '12h',
        ),
        'Jul 2, 2026 2:33 PM',
      );
    });

    test('midnight and noon read as 12 AM and 12 PM', () {
      expect(
        formatCommitDate(
          DateTime(2026, 7, 2, 0, 5),
          withTime: true,
          clock: '12h',
        ),
        'Jul 2, 2026 12:05 AM',
      );
      expect(
        formatCommitDate(
          DateTime(2026, 7, 2, 12, 5),
          withTime: true,
          clock: '12h',
        ),
        'Jul 2, 2026 12:05 PM',
      );
    });

    test('the clock setting does nothing when no time is shown', () {
      expect(
        formatCommitDate(DateTime(2026, 7, 2, 14, 33), clock: '12h'),
        'Jul 2, 2026',
      );
    });
  });

  group('author offset', () {
    test("an offset renders the author's own wall clock, tagged with the "
        'zone', () {
      expect(
        formatCommitDate(
          DateTime.utc(2026, 7, 2, 12, 33),
          withTime: true,
          offset: const Duration(hours: 2),
        ),
        'Jul 2, 2026 14:33 +02:00',
      );
    });

    test('a negative half-hour offset keeps its sign and its minutes', () {
      expect(
        formatCommitDate(
          DateTime.utc(2026, 7, 2, 12, 33),
          withTime: true,
          offset: const Duration(hours: -5, minutes: -30),
        ),
        'Jul 2, 2026 07:03 -05:30',
      );
    });

    test('UTC is written as +00:00 rather than left off', () {
      expect(
        formatCommitDate(
          DateTime.utc(2026, 7, 2, 12, 33),
          withTime: true,
          offset: Duration.zero,
        ),
        'Jul 2, 2026 12:33 +00:00',
      );
    });

    test('the date follows the author zone across a day boundary', () {
      final utc = DateTime.utc(2026, 7, 2, 23, 30);
      expect(
        formatCommitDate(utc, withTime: true, offset: const Duration(hours: 2)),
        'Jul 3, 2026 01:30 +02:00',
      );
      // Even with no clock shown, the date is the author's day, not ours.
      expect(
        formatCommitDate(utc, offset: const Duration(hours: 2)),
        'Jul 3, 2026',
      );
    });

    test('an offset displaces the viewer local zone, whatever it is', () {
      expect(
        formatCommitDate(
          DateTime.utc(2026, 7, 2, 12, 33),
          format: 'iso',
          withTime: true,
          offset: const Duration(hours: 9),
        ),
        '2026-07-02 21:33 +09:00',
      );
    });

    test('an offset and a 12h clock combine', () {
      expect(
        formatCommitDate(
          DateTime.utc(2026, 7, 2, 12, 33),
          withTime: true,
          clock: '12h',
          offset: const Duration(hours: 2),
        ),
        'Jul 2, 2026 2:33 PM +02:00',
      );
    });
  });

  group('deriveBranchLabels', () {
    test('a commit is labelled by its own local ref', () {
      final labels = deriveBranchLabels([
        _c('tip', parents: const [], refs: [_local('main')]),
      ]);
      expect(labels['tip'], ['main']);
    });

    test(
      'a remote-only commit is labelled by its remote ref, prefix and all',
      () {
        final labels = deriveBranchLabels([
          _c('x', refs: [_remote('origin/feature')]),
        ]);
        expect(labels['x'], ['origin/feature']);
      },
    );

    test('a local ref suppresses a remote on the same commit', () {
      final labels = deriveBranchLabels([
        _c('x', refs: [_remote('origin/main'), _local('main')]),
      ]);
      expect(labels['x'], ['main']);
    });

    test('multiple local branches on one commit are all shown', () {
      final labels = deriveBranchLabels([
        _c('x', refs: [_local('main'), _local('feature/submodules')]),
      ]);
      expect(labels['x'], ['main', 'feature/submodules']);
    });

    test('a tag ref does not name a commit', () {
      final labels = deriveBranchLabels([
        _c(
          'x',
          refs: const [GitRef(kind: RefKind.tag, name: 'v1')],
        ),
      ]);
      expect(labels['x'], isNull);
    });

    test('a remote ref propagates down first parents like a local one', () {
      // origin/feature → base(root). Newest first, base has no ref of its own.
      final labels = deriveBranchLabels([
        _c('feat', parents: const ['base'], refs: [_remote('origin/feature')]),
        _c('base'),
      ]);
      expect(labels['feat'], ['origin/feature']);
      expect(labels['base'], ['origin/feature']);
    });

    test('shared ancestors take the nearest descendant branch, not a '
        'newer branch that also contains them', () {
      // feat/stage-3 → main → old1 → old2 (root). Newest first.
      final labels = deriveBranchLabels([
        _c('s3', parents: const ['main'], refs: [_local('feat/stage-3')]),
        _c('main', parents: const ['old1'], refs: [_local('main')]),
        _c('old1', parents: const ['old2']),
        _c('old2'),
      ]);
      expect(labels['s3'], ['feat/stage-3']);
      // main and everything below it belongs to main — not feat/stage-3, even
      // though stage-3 also contains these commits.
      expect(labels['main'], ['main']);
      expect(labels['old1'], ['main']);
      expect(labels['old2'], ['main']);
    });

    test('only the primary ref of a multi-ref tip propagates down', () {
      // main + feature both tip 'x'; base inherits only the first (main).
      final labels = deriveBranchLabels([
        _c(
          'x',
          parents: const ['base'],
          refs: [_local('main'), _local('feat')],
        ),
        _c('base'),
      ]);
      expect(labels['x'], ['main', 'feat']);
      expect(labels['base'], ['main']);
    });

    test('a commit\'s own ref wins over an inheriting descendant', () {
      final labels = deriveBranchLabels([
        _c('feat', parents: const ['base'], refs: [_local('feature')]),
        _c('base', refs: [_local('main')]),
      ]);
      expect(labels['base'], ['main']);
    });

    test('a merged branch keeps its own line via first parent', () {
      // merge → [m1, f2];  f2 → f1 → m1(root, main).
      final labels = deriveBranchLabels([
        _c('merge', parents: const ['m1', 'f2'], refs: [_local('main')]),
        _c('f2', parents: const ['f1'], refs: [_local('feature')]),
        _c('f1', parents: const ['m1']),
        _c('m1', refs: [_local('main')]),
      ]);
      expect(labels['f2'], ['feature']);
      expect(labels['f1'], ['feature']); // first-parent descendant is f2
      expect(labels['m1'], ['main']);
    });
  });

  group('branchColumnChips', () {
    test('a HEAD ref adds a HEAD chip above the branch chips', () {
      final chips = branchColumnChips(
        _c('x', refs: [_head(), _local('main')]),
        ['main'],
        showBranchLabel: true,
      );
      expect(chips, const [
        BranchChip(name: 'HEAD', isHead: true),
        BranchChip(name: 'main', isHead: false),
      ]);
    });

    test('a detached HEAD shows a HEAD chip even with no branch label', () {
      final chips = branchColumnChips(
        _c('x', refs: [_head()]),
        const [],
        showBranchLabel: false,
      );
      expect(chips, const [BranchChip(name: 'HEAD', isHead: true)]);
    });

    test('without a HEAD ref only the branch chips show', () {
      final chips = branchColumnChips(_c('x', refs: [_local('main')]), [
        'main',
      ], showBranchLabel: true);
      expect(chips, const [BranchChip(name: 'main', isHead: false)]);
    });

    test('branch labels are suppressed off the segment top', () {
      final chips = branchColumnChips(_c('x', refs: [_local('main')]), [
        'main',
      ], showBranchLabel: false);
      expect(chips, isEmpty);
    });
  });
}
