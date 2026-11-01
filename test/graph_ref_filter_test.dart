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
}
