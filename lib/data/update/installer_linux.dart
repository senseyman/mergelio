import 'dart:io';

import 'update_installer.dart';

/// Deliberately does nothing.
///
/// The .deb and the .rpm are owned by dpkg and rpm. Replacing their files from
/// inside the app would leave the package database describing an install that
/// no longer exists, and the next `apt upgrade` would fight it. Linux users get
/// told an update exists and are sent to the download; a proper APT/DNF
/// repository is the real answer and is not part of this work.
class LinuxInstaller implements UpdateInstaller {
  const LinuxInstaller();

  @override
  bool get canInstallInPlace => false;

  @override
  Future<void> handOff(File artifact) async => throw const UpdateInstallError(
    'Linux packages are updated by the system package manager',
  );
}
