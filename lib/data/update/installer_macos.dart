import 'dart:io';

import 'package:path/path.dart' as p;

import 'update_installer.dart';

/// Replaces the running .app with a freshly downloaded one.
///
/// The swap cannot happen from inside the process being replaced, so it is done
/// by a small detached script that waits for this process to exit first. The
/// old bundle is moved aside rather than deleted, and moved back if the copy
/// fails: a failed update leaves a working app behind.
const String _swapScript = r'''
#!/bin/bash
# args: <pid of the app to wait for> <new bundle> <bundle to replace>
set -u
pid=$1; new=$2; target=$3

for _ in $(seq 1 300); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.2
done

backup="${target}.old"
rm -rf "$backup"
mv "$target" "$backup" || exit 1

if ! ditto "$new" "$target"; then
  rm -rf "$target"
  mv "$backup" "$target"
  open "$target"
  exit 1
fi

rm -rf "$backup"
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
open "$target"
''';

class MacosInstaller implements UpdateInstaller {
  final ProcessLauncher _launcher;
  final String _bundlePath;
  final int _processId;
  final Directory? workDir;

  MacosInstaller({
    ProcessLauncher? launcher,
    String? bundlePath,
    int? processId,
    this.workDir,
  }) : _launcher = launcher ?? const SystemProcessLauncher(),
       _bundlePath = bundlePath ?? _runningBundlePath(),
       // `pid` here is the top-level getter from dart:io - this process's own
       // id, which the swap script waits on before touching the bundle.
       _processId = processId ?? pid;

  /// `/Applications/mergelio.app/Contents/MacOS/mergelio` -> the bundle root.
  static String _runningBundlePath() {
    final exe = Platform.resolvedExecutable;
    return p.dirname(p.dirname(p.dirname(exe)));
  }

  /// An app launched from a disk image or a quarantined folder sits in a
  /// read-only location, and App Translocation moves it somewhere it cannot
  /// write to at all. There the swap is impossible and the user is sent to the
  /// download instead.
  @override
  bool get canInstallInPlace {
    try {
      final probe = File(
        p.join(p.dirname(_bundlePath), '.mergelio-write-test'),
      );
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> handOff(File artifact) async {
    final work = workDir ?? artifact.parent;
    final extracted = Directory(p.join(work.path, 'extracted'));
    extracted.createSync(recursive: true);

    final unzip = await _launcher.run('ditto', [
      '-x',
      '-k',
      artifact.path,
      extracted.path,
    ]);
    if (unzip.exitCode != 0) {
      throw UpdateInstallError('could not unpack the update: ${unzip.stderr}');
    }

    final bundle = extracted.listSync().whereType<Directory>().firstWhere(
      (d) => d.path.endsWith('.app'),
      orElse: () => throw const UpdateInstallError('the archive holds no .app'),
    );

    final signed = await _launcher.run('codesign', [
      '--verify',
      '--deep',
      '--strict',
      bundle.path,
    ]);
    if (signed.exitCode != 0) {
      throw UpdateInstallError('signature check failed: ${signed.stderr}');
    }

    final gatekeeper = await _launcher.run('spctl', [
      '-a',
      '-t',
      'exec',
      bundle.path,
    ]);
    if (gatekeeper.exitCode != 0) {
      throw UpdateInstallError('Gatekeeper rejected the update');
    }

    final script = File(p.join(work.path, 'swap-bundle.sh'));
    script.writeAsStringSync(_swapScript);

    await _launcher.startDetached('/bin/bash', [
      script.path,
      '$_processId',
      bundle.path,
      _bundlePath,
    ]);
  }
}
