/// Locating a usable `git`, and recognising the cases where the one we found
/// cannot run at all.
///
/// A GUI app does not inherit the shell's environment. On macOS it is launched
/// with the bare system PATH, so `git` resolves to `/usr/bin/git` — a stub that
/// forwards to whatever the active Xcode provides, and refuses outright when
/// Xcode is unlicensed or absent. The developer's real git, the one their
/// terminal uses, sits in a Homebrew prefix the app never sees.
library;

import 'dart:io';

/// Absolute paths worth trying before falling back to a PATH lookup, in order
/// of preference.
///
/// macOS needs them because of the stub described above. Windows needs them
/// because Git for Windows offers an install option that deliberately keeps
/// git off PATH, and because a PATH edited after login is invisible to
/// processes started from the old session. Linux needs none: the deb and rpm
/// both depend on git, so it is installed where any session PATH finds it.
List<String> gitBinaryCandidates(
  String operatingSystem, {
  Map<String, String>? environment,
}) {
  switch (operatingSystem) {
    case 'macos':
      return const ['/opt/homebrew/bin/git', '/usr/local/bin/git'];
    case 'windows':
      final env = environment ?? Platform.environment;
      // A variable with no value means that root does not apply to this
      // machine — a 32-bit host has no ProgramFiles(x86) — so drop it rather
      // than probing a path built from an empty string.
      return [
        for (final (variable, suffix) in const [
          ('ProgramFiles', r'\Git\cmd\git.exe'),
          ('ProgramFiles(x86)', r'\Git\cmd\git.exe'),
          ('LOCALAPPDATA', r'\Programs\Git\cmd\git.exe'),
        ])
          if (env[variable]?.isNotEmpty ?? false) '${env[variable]}$suffix',
      ];
    default:
      return const [];
  }
}

/// How to get a git when there is none to run. Nothing about the repository
/// can be reached until this is fixed, so the message names the usual way in
/// on [operatingSystem] rather than leaving the user to guess.
String missingGitMessage(String operatingSystem) => switch (operatingSystem) {
  'windows' =>
    'git could not be found. Install Git for Windows and choose the option '
        'that adds it to PATH, then reopen Mergelio — a PATH changed after '
        'sign-in only reaches apps started afterwards.',
  'macos' =>
    'git could not be found. Install it with `xcode-select --install`, or '
        '`brew install git`, then reopen Mergelio.',
  _ =>
    'git could not be found. Install it with your package manager, then '
        'reopen Mergelio.',
};

/// First of [candidates] that [exists] reports present, or a bare `git` for
/// the OS to resolve against PATH.
String resolveGitBinary({
  required List<String> candidates,
  required bool Function(String path) exists,
}) {
  for (final path in candidates) {
    if (exists(path)) return path;
  }
  return 'git';
}

/// An actionable description of why git could not run at all, or null when
/// [exitCode]/[stderr] describe git doing its job — including failing at it.
///
/// These are not repository problems and no retry or different command will
/// get past them, so they are worth telling apart from the ordinary failures
/// a caller is expected to handle.
String? toolchainFailure(int exitCode, String stderr) {
  if (exitCode == 0) return null;
  if (stderr.contains('agreed to the Xcode license')) {
    return 'git cannot run: the Xcode licence has not been accepted. '
        'Run `sudo xcodebuild -license accept` in Terminal, then reopen '
        'Mergelio.';
  }
  if (stderr.contains('invalid active developer path') ||
      stderr.contains('no developer tools were found')) {
    return 'git cannot run: the Xcode command line tools are missing. '
        'Run `xcode-select --install` in Terminal, then reopen Mergelio.';
  }
  return null;
}
