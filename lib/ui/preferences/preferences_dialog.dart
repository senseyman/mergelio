import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/ssh_keys.dart';
import '../../domain/theme_io.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/settings_controller.dart';
import '../common/dialogs.dart';
import '../graph/commit_columns.dart';
import 'logs_row.dart';

/// Preferences with General and Appearance tabs. All edits apply live and
/// persist through the settings controller.
Future<void> showPreferencesDialog(BuildContext context) => showAppModal<void>(
  context: context,
  title: 'Preferences',
  icon: Icons.settings_outlined,
  width: 560,
  body: const SizedBox(height: 460, child: _PrefsBody()),
);

class _PrefsBody extends StatelessWidget {
  const _PrefsBody();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            labelColor: t.textPrimary,
            unselectedLabelColor: t.textFaint,
            indicatorColor: t.accent,
            tabs: [
              Tab(text: l.prefsTabGeneral),
              Tab(text: l.prefsTabAppearance),
              Tab(text: l.prefsTabShortcuts),
              Tab(text: l.prefsTabCredentials),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _GeneralTab(),
                _AppearanceTab(),
                _ShortcutsTab(),
                _CredentialsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralTab extends ConsumerWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _ChoiceRow(
          l.prefsLanguage,
          const ['', 'en', 'uk'],
          s.localeCode,
          c.setLocaleCode,
          labelFor: (v) => switch (v) {
            'en' => l.languageEnglish,
            'uk' => l.languageUkrainian,
            _ => l.languageSystem,
          },
        ),
        _SwitchRow(l.prefsAutoFetch, s.autoFetch, c.setAutoFetch),
        if (s.autoFetch)
          _ChoiceRow(
            l.prefsAutoFetchInterval,
            const ['5', '15', '30', '60', '300'],
            '${s.autoFetchIntervalSeconds}',
            (v) => c.setAutoFetchInterval(int.parse(v)),
            labelFor: (v) => switch (v) {
              '60' => '1m',
              '300' => '5m',
              _ => '${v}s',
            },
          ),
        _SwitchRow(
          l.prefsConfirmDestructive,
          s.confirmDestructive,
          c.setConfirmDestructive,
        ),
        _SwitchRow(l.prefsRestoreTabs, s.restoreTabs, c.setRestoreTabs),
        _SwitchRow(l.prefsTelemetry, s.telemetryEnabled, c.setTelemetryEnabled),
        _ZoomRow(label: l.prefsZoom, scale: s.uiScale, controller: c),
        _ChoiceRow(
          l.prefsPullStrategy,
          const ['merge', 'rebase'],
          s.pullStrategy,
          c.setPullStrategy,
          labelFor: (v) => v == 'rebase' ? l.strategyRebase : l.strategyMerge,
        ),
        _ChoiceRow(
          l.prefsDateFormat,
          const ['medium', 'iso', 'short'],
          s.dateFormat,
          c.setDateFormat,
          labelFor: (v) => switch (v) {
            'iso' => l.dateIso,
            'short' => l.dateShort,
            _ => l.dateMedium,
          },
        ),
        _ChoiceRow(
          l.prefsClockFormat,
          const ['24h', '12h'],
          s.clockFormat,
          c.setClockFormat,
          labelFor: (v) => v == '12h' ? l.clock12 : l.clock24,
        ),
        const Divider(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            l.prefsGraphColumns,
            style: TextStyle(color: t.textFaint, fontSize: 12),
          ),
        ),
        for (final e in graphColumnLabels.entries)
          _SwitchRow(
            e.value,
            s.graphCols[e.key] ?? true,
            (_) => c.toggleGraphCol(e.key),
          ),
        _SwitchRow(
          l.prefsCompactRows,
          s.graphCompact,
          (_) => c.toggleGraphCompact(),
        ),
        const Divider(height: 20),
        const LogsRow(),
      ],
    );
  }
}

/// UI-zoom control: −/percent/+ stepping the 100–200% scale.
class _ZoomRow extends StatelessWidget {
  final String label;
  final double scale;
  final SettingsController controller;
  const _ZoomRow({
    required this.label,
    required this.scale,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: t.textPrimary, fontSize: 13),
            ),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: '⌘−',
            onPressed: scale > 1.0 ? controller.zoomOut : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${(scale * 100).round()}%',
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: '⌘+',
            onPressed: scale < 2.0 ? controller.zoomIn : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Read-only reference of the app's keyboard shortcuts.
class _ShortcutsTab extends StatelessWidget {
  const _ShortcutsTab();

  static const _shortcuts = [
    ('⌘K / ⌘⇧P', 'Command palette'),
    ('⌘F', 'Search commits'),
    ('N / ⇧N', 'Next / previous search match'),
    ('⌘⏎', 'Commit (in composer)'),
    ('⌘B', 'Create branch'),
    ('⌘\\', 'Collapse left panel'),
    ('⌘`', 'Toggle terminal'),
    ('⌘ + / −', 'Zoom in / out'),
    ('⌘0', 'Reset zoom'),
    ('⌘Z', 'Undo last action'),
    ('⌘⇧Z', 'Redo'),
    ('⌘,', 'Preferences'),
    ('Esc', 'Close dialog / cancel'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final (keys, desc) in _shortcuts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: t.bgPanel,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    keys,
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(desc, style: TextStyle(color: t.textMuted, fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shows how Mergelio authenticates with remotes. Editing credentials is
/// delegated to the system (git credential helper / SSH agent) — the app never
/// stores secrets itself.
class _CredentialsTab extends ConsumerStatefulWidget {
  const _CredentialsTab();

  @override
  ConsumerState<_CredentialsTab> createState() => _CredentialsTabState();
}

class _CredentialsTabState extends ConsumerState<_CredentialsTab> {
  final _ssh = SshKeys();
  late Future<List<SshKey>> _keys = _ssh.list();

  void _reload() => setState(() => _keys = _ssh.list());

  Future<void> _generate() async {
    final name = await showInputDialog(
      context,
      title: 'Generate SSH key',
      label: 'Key file name (e.g. id_ed25519_work)',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await _ssh.generate(name.trim(), comment: 'mergelio');
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show(
            'Key generated without a passphrase',
            description:
                'Run ssh-keygen -p -f ~/.ssh/${name.trim()} to add one.',
            kind: ToastKind.success,
          );
      _reload();
    } on Object catch (e) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('Generate failed', description: '$e', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text(
          'Authentication',
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'HTTPS remotes use your system git credential helper; SSH remotes '
          'use your SSH agent and keys. Mergelio never stores or reads your '
          'passwords or private keys — only public keys are listed here.',
          style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(
              'SSH KEYS',
              style: TextStyle(
                color: t.textFaint,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _generate,
              child: const Text(
                'Generate key…',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        FutureBuilder(
          future: _keys,
          builder: (context, snap) {
            final keys = snap.data ?? const <SshKey>[];
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (keys.isEmpty) {
              return Text(
                'No SSH keys found in ~/.ssh',
                style: TextStyle(color: t.textFaint, fontSize: 12),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final k in keys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.key_outlined, size: 14, color: t.textFaint),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                k.name,
                                style: TextStyle(
                                  color: t.textPrimary,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                k.publicKey.split(' ').take(2).join(' '),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textFaint,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tooltip(
                          message: 'Copy public key',
                          child: IconButton(
                            iconSize: 15,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: k.publicKey),
                              );
                              ref
                                  .read(toastProvider.notifier)
                                  .show(
                                    'Public key copied',
                                    kind: ToastKind.success,
                                  );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AppearanceTab extends ConsumerWidget {
  const _AppearanceTab();

  static const _presets = [
    0xFF6E7BFF,
    0xFF4C5BF5,
    0xFF0E9F6E,
    0xFFB54708,
    0xFFD92D20,
    0xFF7A5AF8,
    0xFF0BA5EC,
    0xFFDD2590,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final c = ref.read(settingsProvider.notifier);
    final base = AppTokens.defaultBranchPalette;
    final themeLabels = {
      'dark': l.themeDark,
      'light': l.themeLight,
      'system': l.themeSystem,
    };

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _ChoiceRow(
          l.prefsTheme,
          const ['dark', 'light', 'system'],
          switch (s.themeMode) {
            ThemeMode.light => 'light',
            ThemeMode.system => 'system',
            ThemeMode.dark => 'dark',
          },
          (v) => c.setThemeMode(switch (v) {
            'light' => ThemeMode.light,
            'system' => ThemeMode.system,
            _ => ThemeMode.dark,
          }),
          labelFor: (v) => themeLabels[v] ?? v,
        ),
        _ChoiceRow(
          l.prefsGroupStyle,
          const ['dropdown', 'pills', 'rail'],
          s.groupStyle,
          c.setGroupStyle,
        ),
        const SizedBox(height: 8),
        Text(l.prefsAccent, style: TextStyle(color: t.textFaint, fontSize: 12)),
        _ColorRow(
          selected: s.accentValue,
          onPick: (argb) => c.setAccent(Color(argb)),
        ),
        const SizedBox(height: 12),
        Text(
          l.prefsBranchColours,
          style: TextStyle(color: t.textFaint, fontSize: 12),
        ),
        for (var i = 0; i < base.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: t.textFaint, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: _ColorRow(
                    selected:
                        s.branchColorOverrides['$i'] ?? base[i].toARGB32(),
                    onPick: (argb) => c.setBranchColor(i, Color(argb)),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: c.resetBranchColors,
              child: Text(l.prefsResetColours),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                final spec = c.currentTheme('mergelio-custom', [
                  for (final b in base) b.toARGB32(),
                ]);
                Clipboard.setData(ClipboardData(text: spec.encode()));
                ref
                    .read(toastProvider.notifier)
                    .show('Theme JSON copied', kind: ToastKind.success);
              },
              child: Text(l.export),
            ),
            TextButton(
              onPressed: () async {
                final raw = await showInputDialog(
                  context,
                  title: 'Import theme',
                  label: 'Paste theme JSON',
                );
                if (raw == null) return;
                try {
                  c.applyTheme(ThemeSpec.decode(raw));
                } on Object {
                  ref
                      .read(toastProvider.notifier)
                      .show('Invalid theme JSON', kind: ToastKind.error);
                }
              },
              child: Text(l.import),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l.prefsSavedThemes,
          style: TextStyle(color: t.textFaint, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final name in s.savedThemes.keys)
              InputChip(
                label: Text(name, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  c.applySavedTheme(name);
                  ref
                      .read(toastProvider.notifier)
                      .show('Applied "$name"', kind: ToastKind.success);
                },
                onDeleted: () => c.deleteSavedTheme(name),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 15),
              label: Text(
                l.prefsSaveCurrent,
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () async {
                final name = await showInputDialog(
                  context,
                  title: 'Save theme',
                  label: 'Theme name',
                );
                if (name == null || name.trim().isEmpty) return;
                c.saveTheme(name.trim(), [for (final b in base) b.toARGB32()]);
                ref
                    .read(toastProvider.notifier)
                    .show('Saved "$name"', kind: ToastKind.success);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(label, style: TextStyle(color: t.textPrimary, fontSize: 13)),
      value: value,
      activeThumbColor: t.accent,
      onChanged: onChanged,
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  final String label;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  // Maps an option code to its display label; identity by default.
  final String Function(String)? labelFor;
  const _ChoiceRow(
    this.label,
    this.options,
    this.value,
    this.onChanged, {
    this.labelFor,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: t.textPrimary, fontSize: 13),
            ),
          ),
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                label: Text(
                  labelFor?.call(o) ?? o,
                  style: const TextStyle(fontSize: 12),
                ),
                selected: value == o,
                onSelected: (_) => onChanged(o),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onPick;
  const _ColorRow({required this.selected, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isPreset = _AppearanceTab._presets.contains(selected);
    return Wrap(
      spacing: 6,
      children: [
        for (final c in _AppearanceTab._presets)
          InkWell(
            onTap: () => onPick(c),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected == c ? t.textPrimary : t.border,
                  width: selected == c ? 2 : 1,
                ),
              ),
            ),
          ),
        // Free-form colour: shows the current custom colour (highlighted when
        // the selection is not one of the presets) and prompts for a hex value.
        InkWell(
          onTap: () async {
            final raw = await showInputDialog(
              context,
              title: 'Custom colour',
              label: 'Hex (e.g. #6E7BFF)',
            );
            if (raw == null) return;
            final argb = parseHexColor(raw);
            if (argb != null) onPick(argb);
          },
          child: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isPreset ? null : Color(selected),
              shape: BoxShape.circle,
              border: Border.all(
                color: isPreset ? t.border : t.textPrimary,
                width: isPreset ? 1 : 2,
              ),
            ),
            child: isPreset
                ? Icon(Icons.colorize, size: 12, color: t.textFaint)
                : null,
          ),
        ),
      ],
    );
  }
}

/// Parses a #RRGGBB or #AARRGGBB hex string to an opaque ARGB int, or null when
/// the input is not a valid 6/8-digit hex colour.
int? parseHexColor(String s) {
  final clean = s.replaceAll('#', '').trim();
  final hex = clean.length == 8 ? clean.substring(2) : clean;
  if (hex.length != 6) return null;
  final v = int.tryParse(hex, radix: 16);
  return v == null ? null : 0xFF000000 | v;
}
