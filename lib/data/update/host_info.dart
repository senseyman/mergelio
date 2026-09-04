import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/update/app_version.dart';
import '../../domain/update/platform_target.dart';

/// Dart reports the host architecture only inside its version banner, as the
/// quoted `<os>_<arch>` pair at the end. There is no first-class API for it.
String archFromDartVersion(String version) {
  final quoted = RegExp(r'"([a-z0-9]+)_([a-z0-9]+)"').firstMatch(version);
  return quoted?.group(2) ?? '';
}

Future<String?> currentPlatformKey() async {
  var osRelease = '';
  if (Platform.isLinux) {
    final file = File('/etc/os-release');
    if (file.existsSync()) osRelease = await file.readAsString();
  }
  return platformKey(
    os: Platform.operatingSystem,
    arch: archFromDartVersion(Platform.version),
    osRelease: osRelease,
  );
}

/// The running build's identity, read from the packaged metadata rather than a
/// constant, so a stale hardcoded version can never claim to be current.
Future<AppVersion> currentAppVersion() async {
  final info = await PackageInfo.fromPlatform();
  final build = int.tryParse(info.buildNumber) ?? 0;
  return AppVersion.parse('${info.version}+$build');
}
