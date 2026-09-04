import 'dart:io';

/// Something went wrong between a verified download and a running installer.
class UpdateInstallError implements Exception {
  final String message;
  const UpdateInstallError(this.message);
  @override
  String toString() => 'UpdateInstallError: $message';
}

/// The seam that keeps installers testable: every process the update path
/// starts goes through here, so a test asserts on the command line instead of
/// launching anything.
abstract class ProcessLauncher {
  Future<ProcessResult> run(String executable, List<String> arguments);

  /// Starts a process that outlives this one. The updater relies on that: the
  /// process it starts is the one that replaces the running app.
  Future<void> startDetached(String executable, List<String> arguments);
}

class SystemProcessLauncher implements ProcessLauncher {
  const SystemProcessLauncher();

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      Process.run(executable, arguments);

  @override
  Future<void> startDetached(String executable, List<String> arguments) async {
    await Process.start(executable, arguments, mode: ProcessStartMode.detached);
  }
}

abstract class UpdateInstaller {
  /// False where the platform owns the install - a package manager, or a
  /// read-only location. The app then points at the download instead.
  bool get canInstallInPlace;

  /// Verifies [artifact] once more against the platform's own signing rules,
  /// then hands it to whatever will perform the replacement.
  Future<void> handOff(File artifact);
}
