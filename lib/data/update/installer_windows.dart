import 'dart:io';

import 'update_installer.dart';

/// Hands the downloaded setup.exe to Inno Setup.
///
/// The installer script keeps a fixed AppId and CloseApplications=yes, so this
/// is an in-place upgrade: it shuts the running app down, replaces it, and
/// starts it again. It also asks for elevation, which surfaces a UAC prompt -
/// unavoidable while the app installs into Program Files.
class WindowsInstaller implements UpdateInstaller {
  final ProcessLauncher _launcher;

  /// Authenticode verification. Off until releases are code-signed: a check
  /// that always fails would block every update.
  final bool verifySignature;

  const WindowsInstaller({
    ProcessLauncher? launcher,
    this.verifySignature = false,
  }) : _launcher = launcher ?? const SystemProcessLauncher();

  @override
  bool get canInstallInPlace => true;

  @override
  Future<void> handOff(File artifact) async {
    if (!artifact.existsSync()) {
      throw UpdateInstallError('installer is missing: ${artifact.path}');
    }

    if (verifySignature) await _checkAuthenticode(artifact);

    // The installer brings the app back itself, through a [Run] entry that
    // fires only in silent mode. Restart Manager is deliberately not asked to
    // do it as well: it would relaunch from the elevated installer, leaving
    // the app running as administrator, and two relaunch paths would race.
    await _launcher.startDetached(artifact.path, const [
      '/SILENT',
      '/CLOSEAPPLICATIONS',
      '/NORESTART',
    ]);
  }

  Future<void> _checkAuthenticode(File artifact) async {
    final result = await _launcher.run('powershell', [
      '-NoProfile',
      '-Command',
      "(Get-AuthenticodeSignature -LiteralPath '${artifact.path}').Status",
    ]);
    if ('${result.stdout}'.trim() != 'Valid') {
      throw UpdateInstallError(
        'installer is not signed by a trusted publisher',
      );
    }
  }
}
