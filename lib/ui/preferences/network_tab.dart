import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../domain/net/proxy.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/network.dart';
import '../../state/settings_controller.dart';

/// The host the status line is worked out for. `no_proxy` can treat hosts
/// differently, but one representative answer is what a person checking
/// "is my proxy being used" needs.
final _probe = Uri.parse('https://github.com/');

/// Where the proxy for Mergelio's own requests is chosen, and where the
/// proxy actually in use is shown along with the setting that picked it.
class NetworkTab extends ConsumerStatefulWidget {
  const NetworkTab({super.key});

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
    final policy = ref.watch(proxyPolicyProvider).valueOrNull;
    final settings = ref.read(settingsProvider.notifier);

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
        if (policy != null)
          note(
            _status(l, policy.routeFor(_probe)),
            policy.routeFor(_probe) is ProxyUnsupported
                ? TextStyle(color: t.danger, fontSize: 12)
                : TextStyle(color: t.textPrimary, fontSize: 12),
          ),
        if (mode == ProxyMode.auto) ...[
          note(l.proxyAutoNote),
          if (Platform.isMacOS) note(l.proxyGuiEnvNote),
        ],
        note(l.proxyGitNote),
      ],
    );
  }

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
