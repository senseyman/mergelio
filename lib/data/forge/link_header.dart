// Paging for an API that reports where the next page lives in a Link header
// rather than in the body. The header is a comma-separated list of
// `<url>; rel="name"` sections, and only the `next` one matters here.

/// Section of a Link header: the bracketed URL, then its parameters.
final _section = RegExp(r'<([^>]*)>\s*;\s*(.*)');

/// `rel=next`, with or without quotes of either kind.
final _relNext = RegExp('''rel\\s*=\\s*['"]?next['"]?''', caseSensitive: false);

/// The URL of the next page named by [linkHeader], or null when the header is
/// absent, names no next page, or names one that cannot be used.
///
/// Anything unparseable is skipped rather than raised: a paging header is not
/// worth failing a request that already returned its first page.
Uri? nextPageUrl(String? linkHeader) {
  final header = linkHeader?.trim() ?? '';
  if (header.isEmpty) return null;

  for (final part in header.split(',')) {
    final match = _section.firstMatch(part.trim());
    if (match == null) continue;
    if (!_relNext.hasMatch(match.group(2)!)) continue;
    final url = Uri.tryParse(match.group(1)!.trim());
    // The server chooses this URL, so it gets the same transport rule every
    // other call gets: https or nothing.
    if (url == null || url.scheme != 'https' || !url.hasAuthority) return null;
    return url;
  }
  return null;
}
