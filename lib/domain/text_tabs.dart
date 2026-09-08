/// Columns a tab stop is worth. Four is what git itself assumes when it draws
/// a diff to a terminal, so a hunk lines up here the way it does there.
const kTabColumns = 4;

/// Flutter shapes a tab as a single narrow glyph — there is no tab-stop
/// support in the text engine — so a tab-indented file arrives with its
/// indentation flattened to one column. Everything that paints code as read-only
/// text expands tabs first; an editable field cannot, because its spans have to
/// map onto the document character for character.
String expandTabs(String text, {int width = kTabColumns}) =>
    expandTabsFrom(text, 0, width: width).text;

/// [expandTabs] for one piece of a line that starts at [startColumn], with the
/// column the next piece of the same line should start from.
///
/// A line reaches the painter as a run of separately coloured spans, and a tab
/// advances to the next stop from wherever it sits, so each span has to be told
/// how far along the line it begins.
({String text, int column}) expandTabsFrom(
  String text,
  int startColumn, {
  int width = kTabColumns,
}) {
  var column = startColumn;
  if (!text.contains('\t')) {
    // Nothing to expand, but the caller still needs the column it ends on.
    final lastBreak = text.lastIndexOf('\n');
    return (
      text: text,
      column: lastBreak < 0
          ? column + text.length
          : text.length - lastBreak - 1,
    );
  }

  final out = StringBuffer();
  for (final rune in text.runes) {
    switch (rune) {
      case 0x09:
        final pad = width - (column % width);
        out.write(' ' * pad);
        column += pad;
      case 0x0a:
        out.writeCharCode(rune);
        column = 0;
      default:
        out.writeCharCode(rune);
        column++;
    }
  }
  return (text: out.toString(), column: column);
}
