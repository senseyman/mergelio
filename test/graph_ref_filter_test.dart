import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/graph_ref_filter.dart';

void main() {
  const a = 'refs/heads/a';
  const b = 'refs/remotes/origin/b';

  test('starts empty', () {
    expect(GraphRefFilter.none.isEmpty, isTrue);
  });

  test('hiding and soloing keep a ref in one set at a time', () {
    var f = GraphRefFilter.none.toggleHidden(a);
    expect(f.hidden, {a});

    f = f.toggleSolo(a);
    expect(f.solo, {a});
    expect(f.hidden, isEmpty);

    f = f.toggleHidden(a);
    expect(f.hidden, {a});
    expect(f.solo, isEmpty);

    f = f.toggleHidden(a);
    expect(f.isEmpty, isTrue);
  });

  test('round-trips through json, and bad json reads as empty', () {
    final f = GraphRefFilter.none.toggleHidden(a).toggleSolo(b);
    expect(GraphRefFilter.fromJson(f.toJson()), f);
    expect(GraphRefFilter.fromJson('not json'), GraphRefFilter.none);
    expect(GraphRefFilter.fromJson('{"hidden": 3}'), GraphRefFilter.none);
  });

  group('walkStart', () {
    test('no filter walks everything with stashes', () {
      final w = GraphRefFilter.none.walkStart(liveSolo: const {});
      expect(w.args, ['--all']);
      expect(w.stashes, isTrue);
    });

    test('hidden refs are excluded before --all, in a stable order', () {
      final f = GraphRefFilter.none.toggleHidden(b).toggleHidden(a);
      final w = f.walkStart(liveSolo: const {});
      expect(w.args, ['--exclude=$a', '--exclude=$b', '--all']);
      expect(w.stashes, isTrue);
    });

    test('soloed refs replace --all and leave stashes out', () {
      final f = GraphRefFilter.none.toggleSolo(b).toggleSolo(a);
      final w = f.walkStart(liveSolo: const {a, b});
      expect(w.args, [a, b]);
      expect(w.stashes, isFalse);
    });

    test('only soloed refs that still exist are walked', () {
      final f = GraphRefFilter.none.toggleSolo(a).toggleSolo(b);
      expect(f.walkStart(liveSolo: const {b}).args, [b]);
    });

    test('when no soloed ref exists, everything but hidden is walked', () {
      final f = GraphRefFilter(hidden: const {a}, solo: const {b});
      final w = f.walkStart(liveSolo: const {});
      expect(w.args, ['--exclude=$a', '--all']);
      expect(w.stashes, isTrue);
    });
  });

  group('effective', () {
    const live = {a, b, 'refs/heads/main'};

    test('drops refs that no longer exist', () {
      expect(
        const GraphRefFilter(hidden: {a, 'refs/heads/gone'})
            .effective(live: live, current: 'main'),
        const GraphRefFilter(hidden: {a}),
      );
      expect(
        const GraphRefFilter(solo: {b, 'refs/heads/also-gone'})
            .effective(live: live, current: 'main'),
        const GraphRefFilter(solo: {b}),
      );
    });

    test('a hidden current branch is not in effect: HEAD keeps it', () {
      final f = const GraphRefFilter(hidden: {a, 'refs/heads/main'})
          .effective(live: live, current: 'main');
      expect(f.hidden, {a});
    });

    test('with no live soloed ref, the walk is all but hidden', () {
      final f = const GraphRefFilter(
        hidden: {a},
        solo: {'refs/heads/gone'},
      ).effective(live: live, current: null);
      expect(f, const GraphRefFilter(hidden: {a}));
    });

    test('while soloing, hidden refs play no part', () {
      final f = const GraphRefFilter(
        hidden: {a},
        solo: {b},
      ).effective(live: live, current: null);
      expect(f, const GraphRefFilter(solo: {b}));
    });
  });

  group('rowMark', () {
    test('marks a hidden ref, a soloed ref, and leaves the rest', () {
      const f = GraphRefFilter(hidden: {a}, solo: {b});
      expect(f.rowMark(a), GraphRowMark.hidden);
      expect(f.rowMark(b), GraphRowMark.solo);
      expect(f.rowMark('refs/heads/other'), GraphRowMark.none);
    });

    test('a hidden checked-out branch is not marked: HEAD keeps it', () {
      const f = GraphRefFilter(hidden: {a});
      expect(f.rowMark(a, current: true), GraphRowMark.none);
    });

    test('a ref in both sets reads as soloed, as the walk treats it', () {
      const f = GraphRefFilter(hidden: {a}, solo: {a});
      expect(f.rowMark(a), GraphRowMark.solo);
    });
  });

  test('fromJson keeps a ref in one set, solo winning as in the walk', () {
    final f = GraphRefFilter.fromJson(
      '{"hidden": ["$a", "$b"], "solo": ["$a"]}',
    );
    expect(f, const GraphRefFilter(hidden: {b}, solo: {a}));
  });

  test('fromJson skips non-string entries of a valid list', () {
    final f = GraphRefFilter.fromJson(
      '{"hidden": ["$a", 3, null], "solo": []}',
    );
    expect(f, const GraphRefFilter(hidden: {a}));
  });
}
