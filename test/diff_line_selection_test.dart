import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/ui/diff/line_selection.dart';

void main() {
  const sel = DiffLineSelection(
    path: 'a.txt',
    hunkIndex: 1,
    anchor: 4,
    focus: 7,
  );

  test('a selection covers the range between its ends', () {
    expect(sel.lines, {4, 5, 6, 7});
  });

  test('dragging upwards selects the same range', () {
    const upwards = DiffLineSelection(
      path: 'a.txt',
      hunkIndex: 1,
      anchor: 7,
      focus: 4,
    );
    expect(upwards.lines, sel.lines);
  });

  test('a single line is a selection of one', () {
    const one = DiffLineSelection(
      path: 'a.txt',
      hunkIndex: 1,
      anchor: 4,
      focus: 4,
    );
    expect(one.lines, {4});
  });

  test('covers only its own hunk of its own file', () {
    expect(sel.covers('a.txt', 1, 5), isTrue);
    expect(sel.covers('a.txt', 1, 8), isFalse);
    // The same line index in the next hunk is a different line entirely.
    expect(sel.covers('a.txt', 2, 5), isFalse);
    expect(sel.covers('b.txt', 1, 5), isFalse);
  });

  test('extending moves the focus and leaves the anchor', () {
    final wider = sel.extendTo(9);
    expect(wider.anchor, 4);
    expect(wider.focus, 9);
    expect(wider.lines, {4, 5, 6, 7, 8, 9});
  });

  test('extending backwards past the anchor flips the range', () {
    final flipped = sel.extendTo(2);
    expect(flipped.anchor, 4);
    expect(flipped.lines, {2, 3, 4});
  });
}
