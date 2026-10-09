import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/working_selection.dart';

/// Picking several files in one side of the Changes panel: plain click picks
/// one, Cmd/Ctrl-click toggles, Shift-click takes the run from the anchor.
void main() {
  const order = ['a', 'b', 'c', 'd', 'e'];
  const u = WorkingSide.unstaged;
  const s = WorkingSide.staged;

  test('starts empty', () {
    expect(WorkingSelection.none.isEmpty, isTrue);
    expect(WorkingSelection.none.within(u, order), isEmpty);
  });

  test('a plain click selects only that file and anchors on it', () {
    final sel = WorkingSelection.none
        .toggle(u, 'a')
        .toggle(u, 'b')
        .select(u, 'd');
    expect(sel.paths, {'d'});
    expect(sel.anchor, 'd');
    expect(sel.side, u);
  });

  test('toggle adds and removes, moving the anchor', () {
    var sel = WorkingSelection.none.select(u, 'a').toggle(u, 'c');
    expect(sel.paths, {'a', 'c'});
    expect(sel.anchor, 'c');
    sel = sel.toggle(u, 'a');
    expect(sel.paths, {'c'});
    expect(sel.anchor, 'a');
  });

  test('toggling the last file off leaves nothing selected', () {
    final sel = WorkingSelection.none.select(u, 'a').toggle(u, 'a');
    expect(sel.isEmpty, isTrue);
  });

  test('extend takes the run from the anchor, either direction', () {
    final down = WorkingSelection.none.select(u, 'b').extend(u, 'd', order);
    expect(down.paths, {'b', 'c', 'd'});
    expect(down.anchor, 'b');
    final up = down.extend(u, 'a', order);
    expect(up.paths, {'a', 'b'}, reason: 'the run replaces the old one');
    expect(up.anchor, 'b');
  });

  test('extend without an anchor selects just the clicked file', () {
    final sel = WorkingSelection.none.extend(u, 'c', order);
    expect(sel.paths, {'c'});
    expect(sel.anchor, 'c');
  });

  test('extend falls back to a single pick when the anchor is gone', () {
    final sel = WorkingSelection.none.select(u, 'gone').extend(u, 'c', order);
    expect(sel.paths, {'c'});
  });

  test('picking in the other side starts over there', () {
    final base = WorkingSelection.none.select(u, 'a').toggle(u, 'b');
    expect(base.toggle(s, 'a').paths, {'a'});
    expect(base.toggle(s, 'a').side, s);
    expect(base.extend(s, 'c', order).paths, {'c'});
  });

  test('contains is per side, so a partial file is picked in one list', () {
    final sel = WorkingSelection.none.select(u, 'a');
    expect(sel.contains(u, 'a'), isTrue);
    expect(sel.contains(s, 'a'), isFalse);
  });

  test('within keeps display order and drops vanished paths', () {
    final sel = WorkingSelection.none
        .select(u, 'd')
        .toggle(u, 'gone')
        .toggle(u, 'a');
    expect(sel.within(u, order), ['a', 'd']);
    expect(sel.within(s, order), isEmpty);
  });
}
