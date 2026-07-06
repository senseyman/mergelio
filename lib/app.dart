import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'state/settings_controller.dart';
import 'ui/shell/app_shell.dart';

class MergelioApp extends ConsumerWidget {
  const MergelioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accent = Color(settings.accentValue);
    return MaterialApp(
      title: 'Mergelio',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(Brightness.light, accent: accent),
      darkTheme: buildTheme(Brightness.dark, accent: accent),
      home: const AppShell(),
    );
  }
}
