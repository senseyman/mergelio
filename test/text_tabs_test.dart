import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/text_tabs.dart';

void main() {
  test('a tab advances to the next stop, it is not four spaces', () {
    expect(expandTabs('\tx'), '    x');
    expect(expandTabs('a\tx'), 'a   x');
    expect(expandTabs('abc\tx'), 'abc x');
    // A tab landing exactly on a stop still moves a whole column width.
    expect(expandTabs('abcd\tx'), 'abcd    x');
  });

  test('consecutive tabs stack into whole columns', () {
    expect(expandTabs('\t\tx'), '        x');
    expect(expandTabs('ab\t\tx'), 'ab      x');
  });

  test('text without tabs comes back untouched', () {
    expect(expandTabs('  no tabs here'), '  no tabs here');
    expect(expandTabs(''), '');
  });

  test('each line gets its own column count', () {
    expect(expandTabs('ab\tx\n\ty'), 'ab  x\n    y');
  });

  test('the tab width is configurable', () {
    expect(expandTabs('\tx', width: 2), '  x');
    expect(expandTabs('a\tx', width: 8), 'a       x');
  });

  test('spans of one line carry the column across the joins', () {
    // 'if (x) {' then '\t// note' arrive as separate syntax tokens, so the
    // second one only expands correctly if it knows where the first ended.
    final first = expandTabsFrom('if (x) {', 0);
    expect(first.text, 'if (x) {');
    expect(first.column, 8);

    final second = expandTabsFrom('\t// note', first.column);
    expect(second.text, '    // note');
    expect(second.column, 19);
  });

  test('a column count restarts after a newline inside a span', () {
    final r = expandTabsFrom('ab\ncd', 5);
    expect(r.text, 'ab\ncd');
    expect(r.column, 2);
  });
}
