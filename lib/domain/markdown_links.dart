/// Whether [path] is a Markdown file the app can also show rendered.
bool isMarkdownPath(String path) => path.toLowerCase().endsWith('.md');

/// Where a link or image source in a Markdown file leads.
sealed class MarkdownTarget {
  const MarkdownTarget();
}

/// A page on the web, opened in the browser.
class WebTarget extends MarkdownTarget {
  final Uri uri;
  const WebTarget(this.uri);
}

/// Another file in the same repository.
class RepoFileTarget extends MarkdownTarget {
  /// Repo-relative, `/`-separated.
  final String path;
  const RepoFileTarget(this.path);
}

/// Resolves [href] as written in the Markdown file at the repo-relative
/// [from]. Null when it leads nowhere the app will follow: an in-page anchor,
/// a folder, a scheme other than http(s), or a path climbing out of the
/// repository.
MarkdownTarget? resolveMarkdownHref(String? href, {required String from}) {
  if (href == null || href.isEmpty || href.startsWith('#')) return null;
  final Uri uri;
  try {
    uri = Uri.parse(href);
  } on FormatException {
    return null;
  }
  if (uri.hasScheme) {
    return uri.isScheme('https') || uri.isScheme('http')
        ? WebTarget(uri)
        : null;
  }
  // Scheme-relative: a host without saying how to reach it.
  if (uri.hasAuthority) return null;
  // Read off the text rather than [Uri.path], which quietly drops a `..`
  // above the root and would turn an escape into a file inside.
  final end = href.indexOf(RegExp('[?#]'));
  final String raw;
  try {
    raw = Uri.decodeComponent(end < 0 ? href : href.substring(0, end));
  } on ArgumentError {
    return null;
  }
  if (raw.isEmpty || raw.endsWith('/')) return null;

  // A leading slash means the repository root, the way forges read it.
  final parts = raw.startsWith('/')
      ? <String>[]
      : (from.split('/')..removeLast());
  for (final seg in raw.split('/')) {
    switch (seg) {
      case '' || '.':
        continue;
      case '..':
        if (parts.isEmpty) return null;
        parts.removeLast();
      default:
        parts.add(seg);
    }
  }
  // `.` and `..` end on a folder, never a file.
  final last = raw.split('/').last;
  if (parts.isEmpty || last == '.' || last == '..') return null;
  return RepoFileTarget(parts.join('/'));
}
