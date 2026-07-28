import 'dart:io';

import 'package:path/path.dart' as p;

/// Builds the command that shows [path] in the platform's file manager, or null
/// when the platform has none we can drive.
///
/// [select] asks for the file to be highlighted inside its folder. Linux has no
/// portable way to do that, so there the containing folder is opened instead.
(String, List<String>)? revealCommand(
  String path, {
  required String os,
  bool select = true,
}) => switch (os) {
  'macos' => ('open', select ? ['-R', path] : [path]),
  'windows' => ('explorer', [select ? '/select,$path' : path]),
  'linux' => ('xdg-open', [select ? p.dirname(path) : path]),
  _ => null,
};

/// Spawns a process; injectable so callers can be tested without opening a
/// window on the developer's machine.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> args);

/// Opens [path] in the file manager. Throws [ProcessException] if the platform
/// is unsupported or the file manager cannot be launched, so callers can report
/// the failure rather than leave the user waiting on a window that never opens.
Future<void> revealInFileManager(
  String path, {
  String? os,
  ProcessRunner? run,
}) async {
  final command = revealCommand(path, os: os ?? Platform.operatingSystem);
  if (command == null) {
    throw ProcessException(
      'reveal',
      const [],
      'Unsupported platform',
      // A missing file manager is not an OS error code; 0 keeps the message
      // the meaningful part.
      0,
    );
  }
  final (executable, args) = command;
  final result = await (run ?? Process.run)(executable, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      result.stderr.toString().trim(),
      result.exitCode,
    );
  }
}
