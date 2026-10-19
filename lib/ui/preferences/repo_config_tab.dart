import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as pathlib;

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/git_providers.dart';
import '../../domain/git/git_service.dart';
import '../../domain/git/git_writer.dart';
import '../../domain/git/repo_config.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/profiles.dart';
import '../../state/repo_config.dart';
import '../../state/settings_controller.dart';

/// Preferences → Repository: a few git config keys for the repository in the
/// active tab, each with the value git uses and where that comes from. Writes
/// go to the repository's own config unless the user picks Global.
class RepoConfigTab extends ConsumerStatefulWidget {
  /// Null when no repository is open.
  final String? repoPath;
  const RepoConfigTab({super.key, required this.repoPath});

  @override
  ConsumerState<RepoConfigTab> createState() => _RepoConfigTabState();
}

class _RepoConfigTabState extends ConsumerState<RepoConfigTab> {
  /// Not remembered: every visit starts on the repository, so a global write
  /// is always a choice made just now.
  bool _global = false;

  /// Writes run one at a time: two `git config` processes at once race for
  /// the config lock, and the loser fails.
  Future<void> _queue = Future.value();

  /// Writes per key, so a text field whose save failed is rebuilt from what
  /// git has rather than keeping text that never landed. Per key, so a write
  /// elsewhere leaves text still being typed alone.
  final _writes = <String, int>{};

  /// Everything a write needs is taken now, so a change asked for just
  /// before the dialog closes still runs once the writes ahead of it finish.
  void _write(String repo, String key, String? value) {
    final global = _global;
    final l = AppLocalizations.of(context);
    final toasts = ref.read(toastProvider.notifier);
    final w = GitWriter(ref.read(gitServiceProvider), repo);
    _queue = _queue.then(
      (_) => _writeNow(w, l, toasts, repo, key, value, global),
    );
  }

  Future<void> _writeNow(
    GitWriter w,
    AppLocalizations l,
    ToastController toasts,
    String repo,
    String key,
    String? value,
    bool global,
  ) async {
    try {
      if (value == null) {
        await w.unsetConfig(key, global: global);
      } else {
        await w.setConfig(key, value, global: global);
      }
    } on GitException catch (e) {
      toasts.show(
        l.rcfgWriteFailed(key),
        description: e.result?.err ?? e.message,
        kind: ToastKind.error,
      );
    } on Object catch (e) {
      // Caught too, never rethrown: a failed future would leave every later
      // write chained behind it never running.
      toasts.show(
        l.rcfgWriteFailed(key),
        description: '$e',
        kind: ToastKind.error,
      );
    }
    if (!mounted) return;
    setState(() => _writes.update(key, (n) => n + 1, ifAbsent: () => 1));
    ref.invalidate(repoConfigProvider(repo));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final repo = widget.repoPath;
    if (repo == null) {
      return Center(
        child: Text(
          l.rcfgNoRepo,
          style: TextStyle(color: t.textMuted, fontSize: 13),
        ),
      );
    }
    final read = ref.watch(repoConfigProvider(repo));
    if (read.hasError) {
      final e = read.error;
      final detail = e is GitException ? (e.result?.err ?? e.message) : '$e';
      return Padding(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          l.rcfgReadFailed(detail),
          style: TextStyle(color: t.textMuted, fontSize: 13),
        ),
      );
    }
    final config = read.valueOrNull;
    if (config == null) {
      return const Center(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final scope = _global ? ConfigScope.global : ConfigScope.local;
    final profile = ref.watch(profilesProvider).active;
    final pullRebase = ref.watch(
      settingsProvider.select((s) => s.pullStrategy == 'rebase'),
    );

    String? note(String key) => switch (key) {
      'pull.rebase' => pullRebase ? l.rcfgPullRebaseApp : l.rcfgPullMergeApp,
      'fetch.prune' => l.rcfgPruneNote,
      'push.autoSetupRemote' => l.rcfgAutoSetupNote,
      _ => null,
    };

    // Pinned above the rows, so which repository and which config file a
    // change goes to is on screen whichever row is being changed.
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pathlib.basename(repo),
            style: TextStyle(
              color: t.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            repo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.mns(size: 11, color: t.textFaint),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l.rcfgWriteTo,
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
              for (final (label, global) in [
                (l.rcfgScopeLocal, false),
                (l.rcfgScopeGlobal, true),
              ])
                ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 12)),
                  selected: _global == global,
                  onSelected: (_) => setState(() => _global = global),
                ),
            ],
          ),
        ],
      ),
    );

    final rows = ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      children: [
        if (profile != null) ...[
          const SizedBox(height: 10),
          Text(
            l.rcfgProfileNote(profile.label, profile.name, profile.email),
            style: TextStyle(color: t.accent, fontSize: 12, height: 1.4),
          ),
        ],
        for (final k in kRepoConfigKeys)
          _ConfigRow(
            key: ValueKey('rcfg-${k.key}'),
            configKey: k,
            label: _labelFor(l, k.key),
            config: config,
            scope: scope,
            writes: _writes[k.key] ?? 0,
            note: note(k.key),
            onWrite: (value) => _write(repo, k.key, value),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Divider(height: 1, color: t.border),
        Expanded(child: rows),
      ],
    );
  }
}

String _labelFor(AppLocalizations l, String key) => switch (key) {
  'user.name' => l.rcfgUserName,
  'user.email' => l.rcfgUserEmail,
  'pull.rebase' => l.rcfgPullRebase,
  'push.autoSetupRemote' => l.rcfgAutoSetupRemote,
  'fetch.prune' => l.rcfgFetchPrune,
  'core.autocrlf' => l.rcfgAutocrlf,
  'commit.gpgsign' => l.rcfgGpgSign,
  'rerere.enabled' => l.rcfgRerere,
  _ => key,
};

String _scopeLabel(AppLocalizations l, ConfigScope s) => switch (s) {
  ConfigScope.system => l.rcfgScopeSystem,
  ConfigScope.global => l.rcfgScopeGlobal,
  ConfigScope.local => l.rcfgScopeLocal,
  ConfigScope.worktree => l.rcfgScopeWorktree,
  ConfigScope.command => l.rcfgScopeCommand,
  ConfigScope.unknown => l.rcfgScopeOther,
};

/// One key: its label and name, the control for the chosen scope, the value
/// in effect and, where Mergelio does its own thing, a note saying so.
class _ConfigRow extends StatelessWidget {
  final RepoConfigKey configKey;
  final String label;
  final RepoConfig config;
  final ConfigScope scope;

  /// Writes of this key so far; part of the text field's key.
  final int writes;
  final String? note;

  /// Null value unsets the key in the chosen scope.
  final ValueChanged<String?> onWrite;

  const _ConfigRow({
    super.key,
    required this.configKey,
    required this.label,
    required this.config,
    required this.scope,
    required this.writes,
    required this.note,
    required this.onWrite,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final k = configKey.key;
    final own = config.inScope(k, scope);
    final effective = config.effective(k);
    final effectiveText = effective == null
        ? l.rcfgNotSet
        : l.rcfgInEffect(
            // A bare key is git's shorthand for true.
            effective.value ?? 'true',
            _scopeLabel(l, effective.scope),
          );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(label, style: TextStyle(color: t.textPrimary, fontSize: 13)),
              Text(k, style: AppFonts.mns(size: 11, color: t.textFaint)),
            ],
          ),
          const SizedBox(height: 6),
          if (configKey.kind == ConfigKind.text)
            _TextValue(
              // Rebuilt with fresh text whenever the scope, the stored value
              // or a write attempt changes, so it never shows a stale value.
              key: ValueKey('$scope/${own?.value}/$writes'),
              initial: own?.value ?? '',
              isSet: own != null,
              onWrite: onWrite,
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chip(l.rcfgInherit, own == null, () => onWrite(null)),
                for (final c in configKey.choices)
                  _chip(
                    c,
                    own != null &&
                        normaliseConfigValue(configKey, own.value) == c,
                    () => onWrite(c),
                  ),
              ],
            ),
          const SizedBox(height: 4),
          Tooltip(
            message: effective?.origin ?? '',
            child: Text(
              effectiveText,
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 2),
            Text(
              note!,
              style: TextStyle(color: t.textFaint, fontSize: 11.5, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label, style: const TextStyle(fontSize: 12)),
    selected: selected,
    onSelected: (_) {
      if (!selected) onTap();
    },
  );
}

/// A free-text value, saved on Enter or the Save button. Saving it emptied
/// unsets the key; saving it unchanged does nothing.
class _TextValue extends StatefulWidget {
  final String initial;

  /// Whether the key is set in the chosen scope at all, even to nothing.
  final bool isSet;
  final ValueChanged<String?> onWrite;
  const _TextValue({
    super.key,
    required this.initial,
    required this.isSet,
    required this.onWrite,
  });

  @override
  State<_TextValue> createState() => _TextValueState();
}

class _TextValueState extends State<_TextValue> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final v = _c.text.trim();
    // Saving the stored value again does nothing — unless it is stored empty,
    // which git refuses to commit with; saving that clears it.
    if (v == widget.initial && !(v.isEmpty && widget.isSet)) return;
    widget.onWrite(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    return TextField(
      controller: _c,
      onSubmitted: (_) => _save(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.rButton),
        ),
        suffixIcon: IconButton(
          tooltip: l.rcfgSave,
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.check),
          onPressed: _save,
        ),
      ),
    );
  }
}
