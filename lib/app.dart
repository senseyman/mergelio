import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'core/tokens.dart';
import 'state/settings_controller.dart';
import 'ui/shell/app_shell.dart';

class MergelioApp extends ConsumerWidget {
  const MergelioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final accent = Color(settings.accentValue);
    // Apply any per-index branch-colour overrides over the default palette.
    final base = AppTokens.defaultBranchPalette;
    final palette = [
      for (var i = 0; i < base.length; i++)
        settings.branchColorOverrides.containsKey('$i')
            ? Color(settings.branchColorOverrides['$i']!)
            : base[i],
    ];
    return MaterialApp(
      title: 'Mergelio',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(
        Brightness.light,
        accent: accent,
        branchPalette: palette,
      ),
      darkTheme: buildTheme(
        Brightness.dark,
        accent: accent,
        branchPalette: palette,
      ),
      home: const AppShell(),
    );
  }
}
