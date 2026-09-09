import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme.dart';
import '../../domain/git/askpass.dart';
import '../../l10n/gen/app_localizations.dart';
import 'askpass_prompt.dart';

/// Runs this launch as a single credential prompt for the git or ssh process
/// that started it, and nothing else: no database, no workspace, no window
/// geometry to restore.
///
/// The answer leaves on stdout, which is a pipe back to the process that asked.
/// It never reaches the main app, and never touches disk.
Future<void> runAskpassApp(String prompt, {bool marked = false}) async {
  await windowManager.ensureInitialized();
  // Closing the window is a refusal, not an empty password. Without this the
  // process would exit cleanly having printed nothing, and git would take that
  // silence for a credential and try to authenticate with it.
  await windowManager.setPreventClose(true);
  windowManager.addListener(_CloseIsRefusal());
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(460, 260),
      minimumSize: Size(360, 220),
      center: true,
      title: 'Mergelio',
      // The command that asked is blocked until this is answered, so the window
      // has to be findable rather than lost behind the workspace.
      alwaysOnTop: true,
      titleBarStyle: TitleBarStyle.normal,
    ),
  );

  runApp(
    AskpassApp(
      prompt: prompt,
      onAnswer: (answer) async {
        stdout.writeln(askpassAnswerLine(answer, marked: marked));
        await stdout.flush();
        exit(0);
      },
      // A non-zero exit is how a helper says the user declined; git and ssh
      // then fail with an authentication error instead of waiting.
      onCancel: () => exit(1),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class _CloseIsRefusal extends WindowListener {
  @override
  void onWindowClose() => exit(1);
}

class AskpassApp extends StatelessWidget {
  final String prompt;
  final void Function(String answer) onAnswer;
  final VoidCallback onCancel;

  const AskpassApp({
    super.key,
    required this.prompt,
    required this.onAnswer,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    // Launched by git, not by the user, so there are no saved settings to read
    // here: the default theme, following the system light/dark setting.
    return MaterialApp(
      title: 'Mergelio',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: AskpassPrompt(
        prompt: prompt,
        onAnswer: onAnswer,
        onCancel: onCancel,
      ),
    );
  }
}
