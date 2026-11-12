import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/git/git_providers.dart';
import '../../domain/git/git_toolchain.dart';
import '../../domain/net/proxy.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/network.dart';
import '../../state/settings_controller.dart';
import 'prefs_rows.dart';

/// The host the status line is worked out for. `no_proxy` can treat hosts
/// differently, but one representative answer is what a person checking
/// "is my proxy being used" needs.
final _probe = Uri.parse('https://github.com/');

/// Where the proxy for Mergelio's own requests is chosen, and where the
/// proxy actually in use is shown along with the setting that picked it.
class NetworkTab extends ConsumerStatefulWidget {
  /// The repository shown behind Preferences, whose ssh remotes are named
  /// when git is told to use this proxy. Null when no repository is open.
  final String? repoPath;
  const NetworkTab({super.key, this.repoPath});

  @override
  ConsumerState<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends ConsumerState<NetworkTab> {
  @override
  void initState() {
    super.initState();
    // git's config may have been edited since it was read; opening this tab
    // is when someone wants the current answer. Deferred, because the tree
    // is still building.
    Future.microtask(() {
      if (mounted) ref.invalidate(gitHttpProxyProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider);
    final mode = ProxyMode.parse(s.proxyMode);
    final route = ref.watch(proxyPolicyProvider).valueOrNull?.routeFor(_probe);
    final settings = ref.read(settingsProvider.notifier);
    final forGit = mode != ProxyMode.auto && s.proxyForGit;
    final gitTooOld = forGit
        ? _tooOldForGit(ref.watch(gitVersionProvider).valueOrNull)
        : null;
    final repo = widget.repoPath;
    final sshRemotes = forGit && repo != null
        ? ref.watch(sshRemotesProvider(repo)).valueOrNull ?? const <String>[]
        : const <String>[];

    final faint = TextStyle(color: t.textFaint, fontSize: 12);
    Widget chip(String label, ProxyMode value) => ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: mode == value,
      onSelected: (_) => settings.setProxyMode(value),
    );
    Widget note(String text, [TextStyle? style]) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: style ?? faint),
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l.proxyTitle,
          style: TextStyle(color: t.textPrimary, fontSize: 13),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(l.proxyModeAuto, ProxyMode.auto),
            chip(l.proxyModeManual, ProxyMode.manual),
            chip(l.proxyModeOff, ProxyMode.off),
          ],
        ),
        if (mode == ProxyMode.manual)
          _ProxyUrlField(url: s.proxyUrl, onChanged: settings.setProxyUrl),
        if (route != null) ...[
          note(
            _status(l, route),
            route is ProxyUnsupported
                ? TextStyle(color: t.danger, fontSize: 12)
                : TextStyle(color: t.textPrimary, fontSize: 12),
          ),
          if (route is ProxyVia && route.credentialsDropped)
            note(
              l.proxyCredentialsDropped(_settingLabel(l, route.setting!)),
              TextStyle(color: t.danger, fontSize: 12),
            ),
        ],
        if (mode == ProxyMode.auto) ...[
          note(l.proxyAutoNote),
          if (Platform.isMacOS) note(l.proxyGuiEnvNote),
        ],
        if (mode == ProxyMode.manual) note(l.proxyManualNote),
        // Automatic already is what git does, so there is nothing to apply.
        if (mode != ProxyMode.auto) ...[
          const SizedBox(height: 8),
          SwitchRow(l.proxyForGit, s.proxyForGit, settings.setProxyForGit),
        ],
        if (forGit && gitTooOld != null)
          note(
            l.proxyForGitTooOld(gitTooOld),
            TextStyle(color: t.danger, fontSize: 12),
          )
        else
          note(forGit ? l.proxyForGitNote : l.proxyGitNote),
        if (sshRemotes.isNotEmpty)
          note(
            l.proxySshRemotes(
              sshRemotes.length,
              p.basename(repo!),
              sshRemotes.join(', '),
            ),
            TextStyle(color: t.textPrimary, fontSize: 12),
          ),
      ],
    );
  }

  /// The version of a git that cannot take config through the environment,
  /// or null when it can or is not known yet.
  String? _tooOldForGit(String? version) {
    if (version == null || gitVersionAtLeast(version, 2, 31)) return null;
    return RegExp(r'\d+(\.\d+)+').firstMatch(version)?.group(0) ?? version;
  }

  /// A setting as a person would look for it: the typed url is the field
  /// above, not an internal name.
  String _settingLabel(AppLocalizations l, String setting) =>
      setting == kManualProxySetting ? l.proxyUrlLabel : setting;

  String _status(AppLocalizations l, ProxyRoute route) => switch (route) {
    ProxyUnsupported(:final setting) => l.proxyStatusUnsupported(setting!),
    ProxyVia(:final address, setting: kManualProxySetting) => l.proxyStatusVia(
      address,
    ),
    ProxyVia(:final address, :final setting) => l.proxyStatusViaFrom(
      address,
      setting!,
    ),
    ProxyDirect(setting: final String setting) => l.proxyStatusDirectFrom(
      setting,
    ),
    ProxyDirect() => l.proxyStatusDirect,
  };
}

/// The typed proxy url, saved on submit or when focus leaves rather than on
/// every keystroke, so a half-typed url never routes a request.
class _ProxyUrlField extends StatefulWidget {
  final String url;
  final ValueChanged<String> onChanged;
  const _ProxyUrlField({required this.url, required this.onChanged});

  @override
  State<_ProxyUrlField> createState() => _ProxyUrlFieldState();
}

class _ProxyUrlFieldState extends State<_ProxyUrlField> {
  late final _field = TextEditingController(text: widget.url);
  late final _focus = FocusNode()..addListener(_onFocus);

  @override
  void didUpdateWidget(_ProxyUrlField old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url && !_focus.hasFocus) _field.text = widget.url;
  }

  @override
  void dispose() {
    _focus.dispose();
    _field.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _save();
  }

  void _save() {
    final text = _field.text.trim();
    if (text != widget.url) widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: _field,
        focusNode: _focus,
        style: AppFonts.mns(size: 12.5, color: t.textPrimary),
        decoration: InputDecoration(
          labelText: l.proxyUrlLabel,
          hintText: 'http://proxy.example.com:3128',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
      ),
    );
  }
}
