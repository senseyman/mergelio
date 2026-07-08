import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import 'repo_data.dart';

/// Whether the dockable terminal panel is shown. Toggled by ⌘`.
final terminalVisibleProvider = StateProvider<bool>((ref) => false);

/// A terminal input string signals a finished command (worth refreshing repo
/// state for) when the user pressed Enter. Pure so it can be unit-tested.
bool inputEndsCommand(String input) =>
    input.contains('\r') || input.contains('\n');

/// A live terminal: an xterm emulator wired to a real system-shell PTY running
/// in the repository directory. After the user runs a command (presses Enter),
/// it refreshes the repo view — debounced so interactive tools don't thrash it.
class PtySession {
  final Terminal terminal;
  final Pty pty;
  final VoidCallback _onCommand;
  Timer? _debounce;
  bool _disposed = false;

  PtySession._(this.terminal, this.pty, this._onCommand) {
    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    terminal.onOutput = (data) {
      if (_disposed) return;
      pty.write(const Utf8Encoder().convert(data));
      if (inputEndsCommand(data)) _scheduleRefresh();
    };
    terminal.onResize = (w, h, pw, ph) {
      if (!_disposed) pty.resize(h, w);
    };
  }

  factory PtySession.start(
    String workingDirectory, {
    required VoidCallback onCommand,
  }) {
    final terminal = Terminal(maxLines: 10000);
    final shell =
        Platform.environment['SHELL'] ??
        (Platform.isWindows ? 'cmd.exe' : '/bin/sh');
    final pty = Pty.start(
      shell,
      workingDirectory: workingDirectory,
      rows: 24,
      columns: 80,
    );
    return PtySession._(terminal, pty, onCommand);
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!_disposed) _onCommand();
    });
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    try {
      pty.kill();
    } on Object {
      /* already exited */
    }
  }
}

/// One PTY session per repo; refreshes that repo's data after each command.
/// Killed when the provider is disposed (repo closed / app exit).
final terminalSessionProvider = Provider.family<PtySession, String>((
  ref,
  path,
) {
  final session = PtySession.start(
    path,
    onCommand: () {
      // Re-read git state after a command that may have mutated the repo.
      ref.invalidate(repoDataProvider(path));
    },
  );
  ref.onDispose(session.dispose);
  return session;
});
