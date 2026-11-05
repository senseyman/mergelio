/// git's own branch-name rules (`check-ref-format --branch`), checked
/// without spawning git. A leading `-` is refused as well: such a name sits
/// before any `--` separator wherever it is passed, and would be read as an
/// option.
bool isValidBranchName(String b) {
  if (b.isEmpty) return false;
  if (b.startsWith('-') || b.startsWith('/')) return false;
  if (b.endsWith('/') || b.endsWith('.')) return false;
  if (b.contains('..') || b.contains('//') || b.contains('@{')) return false;
  if (b.contains(RegExp(r'[\x00-\x20\x7f~^:?*\[\\]|\s'))) return false;
  return b
      .split('/')
      .every((part) => !part.startsWith('.') && !part.endsWith('.lock'));
}
