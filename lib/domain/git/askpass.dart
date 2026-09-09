import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Marker argument that turns a launch into a one-shot credential prompt for
/// git or ssh instead of the workspace window.
const askpassFlag = '--askpass';

/// Asks for the answer to be tagged with [askpassMarker]. Passed by the helper
/// script, which cannot otherwise tell the answer apart from whatever else the
/// process printed.
const askpassMarkerFlag = '--marked';

/// Tag the answer carries when [askpassMarkerFlag] was given. The engine prints
/// to stdout too — a debug build announces its VM service there — and git and
/// ssh take the first line they get as the credential.
const askpassMarker = 'MERGELIO-ASKPASS:';

/// What the prompt is asking for, which decides how it is answered.
enum AskpassKind {
  /// A passphrase or password: masked, and never written anywhere.
  secret,

  /// A username or other readable value.
  text,

  /// A yes/no question — a host key, most often — answered with a word.
  confirm,
}

/// The prompt git or ssh passed, or null for a normal launch. They pass it as
/// a single argument, but a helper reached through a shell can split it on
/// spaces, so everything after the flag is rejoined.
String? askpassPrompt(List<String> args) {
  final i = args.indexOf(askpassFlag);
  if (i < 0) return null;
  return args.skip(i + 1).join(' ').trim();
}

/// The single line the asking process reads: the answer, tagged when the helper
/// script asked for it so it can be told apart from anything else on stdout.
String askpassAnswerLine(String answer, {required bool marked}) =>
    marked ? '$askpassMarker$answer' : answer;

/// Whether the launch was asked to tag its answer. The flag comes before
/// [askpassFlag]: everything after that belongs to the prompt, which could say
/// anything at all.
bool askpassWantsMarker(List<String> args) {
  final i = args.indexOf(askpassFlag);
  return i > 0 && args.take(i).contains(askpassMarkerFlag);
}

/// Classifies [prompt] by what git and ssh actually ask. Anything unrecognised
/// counts as a secret: masking a value that did not need it costs nothing,
/// showing one that did is a leak.
AskpassKind askpassKindOf(String prompt) {
  final text = prompt.toLowerCase();
  if (text.contains('yes/no')) return AskpassKind.confirm;
  if (text.contains('username')) return AskpassKind.text;
  return AskpassKind.secret;
}

/// The helper git and ssh execute: it re-launches this app in askpass mode
/// with the prompt, and they read the answer from its stdout.
String askpassScript(String executable, {required bool windows}) {
  if (windows) {
    // No marker: picking the tagged line back out in cmd costs more than it
    // buys, and mangles an answer containing characters cmd treats as special.
    return '@echo off\r\n"$executable" $askpassFlag %*\r\n';
  }
  // Everything the process printed is captured, then narrowed to the tagged
  // line, so engine chatter is never mistaken for the credential. A refusal
  // exits non-zero before any of that.
  return '#!/bin/sh\n'
      'out=\$("$executable" $askpassMarkerFlag $askpassFlag "\$@") || exit 1\n'
      "printf '%s\\n' \"\$out\" | sed -n 's/^$askpassMarker//p' | head -n 1\n";
}

const _helperName = 'askpass';

/// Path to the installed helper, or null until [initAskpass] has run — and for
/// the rest of the session if it could not be written. A network command
/// started before then simply runs without a way to prompt, exactly as it did
/// before there was one.
String? askpassHelper;

/// Puts the helper in place and points [askpassHelper] at it. Called once at
/// startup: the command that needs it is blocked while it is asked for, so it
/// must not be resolved on the way into a fetch.
Future<void> initAskpass({String? executable, Directory? dir}) async {
  askpassHelper = await installAskpassHelper(executable: executable, dir: dir);
}

/// Writes the helper and returns its path, or null when it cannot be put in
/// working order — an operation that would have worked without a prompt must
/// not fail because the prompt could not be set up.
Future<String?> installAskpassHelper({
  String? executable,
  Directory? dir,
}) async {
  try {
    final home = dir ?? await getApplicationSupportDirectory();
    final windows = Platform.isWindows;
    final file = File(
      p.join(home.path, '$_helperName${windows ? '.cmd' : '.sh'}'),
    );
    await file.parent.create(recursive: true);
    // Rewritten every time: an app that moved (an update, a drag to another
    // folder) would otherwise leave a helper pointing at a binary that is gone.
    await file.writeAsString(
      askpassScript(
        executable ?? Platform.resolvedExecutable,
        windows: windows,
      ),
    );
    if (!windows) {
      // A new file is not executable, so this is what makes the helper usable
      // at all — and it narrows the file to its owner, who is the only one with
      // any business rewriting something every network command runs. Reporting
      // a helper that cannot be executed is worse than reporting none: git and
      // ssh would fail on it instead of falling back.
      final chmod = await Process.run('chmod', ['700', file.path]);
      if (chmod.exitCode != 0) return null;
    }
    return file.path;
  } on Object {
    return null;
  }
}
