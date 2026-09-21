// Paging for an API that reports where the next page lives in a Link header
// rather than in the body. The header is a comma-separated list of
// `<url>; rel="name"` sections, and only the `next` one matters here.

/// Section of a Link header: the bracketed URL, then its parameters.
final _section = RegExp(r'<([^>]*)>\s*;\s*(.*)');

/// A `rel` parameter's value, quoted with either kind of quote or bare.
final _rel = RegExp(
  r'''rel\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,;]+))''',
  caseSensitive: false,
);

/// Whether the `rel` parameter in [params] is exactly `next`, not merely
/// prefixed with it. A server should not be able to steer the pager by
/// naming a rel like `nextish`.
bool _isNextRel(String params) {
  final match = _rel.firstMatch(params);
  if (match == null) return false;
  final value = match.group(1) ?? match.group(2) ?? match.group(3);
  return value?.toLowerCase() == 'next';
}

/// Splits a Link header into its `<url>; rel="..."` sections.
///
/// A plain `header.split(',')` would also split on a comma that is part of
/// the URL itself (a query string cursor, say), cutting that section — and
/// every URL after it — in two before either half ever reaches [_section].
/// Commas only separate sections outside the angle brackets, so this only
/// ever splits there, tracking bracket depth rather than assuming the URL
/// contains no `<` or `>` of its own.
List<String> _splitSections(String header) {
  final sections = <String>[];
  final current = StringBuffer();
  var depth = 0;
  for (final rune in header.runes) {
    final char = String.fromCharCode(rune);
    if (char == '<') {
      depth++;
    } else if (char == '>' && depth > 0) {
      depth--;
    }
    if (char == ',' && depth == 0) {
      sections.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  sections.add(current.toString());
  return sections;
}

/// The URL of the next page named by [linkHeader], or null when the header is
/// absent, names no next page, or names one that cannot be used.
///
/// Anything unparseable is skipped rather than raised: a paging header is not
/// worth failing a request that already returned its first page.
Uri? nextPageUrl(String? linkHeader) {
  final header = linkHeader?.trim() ?? '';
  if (header.isEmpty) return null;

  for (final part in _splitSections(header)) {
    final match = _section.firstMatch(part.trim());
    if (match == null) continue;
    if (!_isNextRel(match.group(2)!)) continue;
    final url = Uri.tryParse(match.group(1)!.trim());
    // The server chooses this URL, so it gets the same transport rule every
    // other call gets: https or nothing.
    if (url == null || url.scheme != 'https' || !url.hasAuthority) return null;
    return url;
  }
  return null;
}
