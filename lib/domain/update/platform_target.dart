/// Artifact key for a machine, matching the keys in the update manifest.
///
/// Returns null where no build is published for that combination: the app then
/// reports that an update exists without offering to install one.
String? platformKey({
  required String os,
  required String arch,
  String osRelease = '',
}) {
  switch (os) {
    case 'macos':
      return arch == 'arm64' ? 'macos-arm64' : null;
    case 'windows':
      return arch == 'x64' ? 'windows-x64' : null;
    case 'linux':
      if (arch != 'x64') return null;
      return _isRpmFamily(osRelease) ? 'linux-x64-rpm' : 'linux-x64-deb';
    default:
      return null;
  }
}

/// Which package manager owns the install. Neither format self-updates, but the
/// distinction decides which download the user is pointed at.
bool _isRpmFamily(String osRelease) {
  final lower = osRelease.toLowerCase();
  for (final line in lower.split('\n')) {
    if (!line.startsWith('id=') && !line.startsWith('id_like=')) continue;
    final value = line.split('=').last.replaceAll('"', '');
    for (final id in value.split(RegExp(r'\s+'))) {
      if (const {'fedora', 'rhel', 'centos', 'suse', 'opensuse'}.contains(id)) {
        return true;
      }
    }
  }
  return false;
}
