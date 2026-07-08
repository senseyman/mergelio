/// Windows ↔ WSL2 path handling. When a Windows build opens a repository that
/// lives inside a WSL distribution, the path arrives as a UNC share
/// (`\\wsl$\Ubuntu\home\me\repo` or the newer `\\wsl.localhost\...`). System
/// git on Windows can operate on these directly, but the UI needs to recognise
/// and prettify them, and interoperate with `/mnt/<drive>` style paths.
library;

/// True if [path] is a WSL UNC share path.
bool isWslPath(String path) {
  final p = path.replaceAll('/', r'\');
  return p.startsWith(r'\\wsl$\') || p.startsWith(r'\\wsl.localhost\');
}

/// The WSL distribution name embedded in a WSL UNC [path], or null.
/// `\\wsl$\Ubuntu\home` → `Ubuntu`.
String? wslDistro(String path) {
  if (!isWslPath(path)) return null;
  final p = path.replaceAll('/', r'\');
  final rest = p.startsWith(r'\\wsl$\')
      ? p.substring(r'\\wsl$\'.length)
      : p.substring(r'\\wsl.localhost\'.length);
  final slash = rest.indexOf(r'\');
  return slash == -1 ? (rest.isEmpty ? null : rest) : rest.substring(0, slash);
}

/// A compact, forward-slashed label for a WSL path suitable for display:
/// `\\wsl$\Ubuntu\home\me\repo` → `wsl:Ubuntu/home/me/repo`. Non-WSL paths are
/// returned unchanged.
String displayPath(String path) {
  if (!isWslPath(path)) return path;
  final distro = wslDistro(path);
  // Degenerate bare share (`\\wsl$\` with no distro) — nothing to prettify.
  if (distro == null) return path;
  final p = path.replaceAll('/', r'\');
  final prefix = p.startsWith(r'\\wsl$\') ? r'\\wsl$\' : r'\\wsl.localhost\';
  final body = p.substring(prefix.length + distro.length);
  final unix = body.replaceAll(r'\', '/');
  return 'wsl:$distro$unix';
}

/// Converts a Windows drive path to its WSL `/mnt` equivalent, e.g.
/// `C:\Users\me\repo` → `/mnt/c/Users/me/repo`. Returns [path] unchanged if it
/// is not a drive-letter path.
String windowsToMnt(String path) {
  final m = RegExp(r'^([A-Za-z]):[\\/](.*)$').firstMatch(path);
  if (m == null) return path;
  final drive = m.group(1)!.toLowerCase();
  final rest = m.group(2)!.replaceAll(r'\', '/');
  return '/mnt/$drive/$rest';
}

/// Converts a WSL `/mnt` path back to a Windows drive path, e.g.
/// `/mnt/c/Users/me` → `C:\Users\me`. Returns [path] unchanged otherwise.
String mntToWindows(String path) {
  final m = RegExp(r'^/mnt/([a-zA-Z])/(.*)$').firstMatch(path);
  if (m == null) return path;
  final drive = m.group(1)!.toUpperCase();
  final rest = m.group(2)!.replaceAll('/', r'\');
  return '$drive:\\$rest';
}
