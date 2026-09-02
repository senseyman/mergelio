import 'dart:io';

import 'installer_linux.dart';
import 'installer_macos.dart';
import 'installer_windows.dart';
import 'update_installer.dart';

UpdateInstaller installerForHost({
  ProcessLauncher launcher = const SystemProcessLauncher(),
}) {
  if (Platform.isMacOS) return MacosInstaller(launcher: launcher);
  if (Platform.isWindows) return WindowsInstaller(launcher: launcher);
  return const LinuxInstaller();
}
