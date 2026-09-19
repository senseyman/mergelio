import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../data/forge/forge_credentials.dart';
import '../../data/forge/forge_http.dart';
import '../../domain/git/git_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';

const _githubHost = 'github.com';

/// Whether the forge accepts [token].
///
/// One request, made before anything is written to the keychain, so a
/// mistyped token is reported while the person is still looking at the field
/// rather than as an empty panel an hour later. Anything other than a clean
/// answer counts as "not validated": an unreachable forge is not proof of a
/// bad token, and saving on that basis would be a guess — but so would
/// accepting it.
Future<bool> validateForgeToken(
  ForgeToken token, {
  ForgeHttp Function(ForgeToken token)? httpFor,
}) async {
  final http = (httpFor ?? (t) => ForgeHttp(token: t))(token);
  try {
    final response = await http.get(Uri.https('api.github.com', '/user'));
    return response.status >= 200 && response.status < 300;
  } on Object {
    return false;
  }
}

/// A text field controller that keeps its value out of diagnostics.
///
/// [TextEditingController.toString] prints the value in full, and the
/// controller is dumped as a property of both TextField and EditableText —
/// so the plain one puts a typed token in the widget inspector and in every
/// tree dump an unrelated error produces. The value is still readable through
/// [text]; only the description changes.
class _RedactedTextEditingController extends TextEditingController {
  @override
  String toString() => '${describeIdentity(this)}(hidden)';
}

/// Connect, inspect or disconnect the token used for github.com.
class ForgeAccountRow extends ConsumerStatefulWidget {
  const ForgeAccountRow({super.key});

  @override
  ConsumerState<ForgeAccountRow> createState() => _ForgeAccountRowState();
}

class _ForgeAccountRowState extends ConsumerState<ForgeAccountRow> {
  final _field = _RedactedTextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  ForgeCredentials get _credentials =>
      ForgeCredentials(ref.read(gitServiceProvider));

  /// Drops everything that was derived from the token that has just changed.
  ///
  /// The stored token is read through a provider that caches for the life of
  /// the container, so without this a session that connects goes on sending
  /// the answer it got before — which is to say no token at all — until the
  /// app is restarted. The cached bodies go with it: a body fetched without a
  /// token must not be served as though it were fetched with one, and one
  /// fetched under a token that just changed must not be served under its
  /// replacement.
  void _forgetDerivedState() {
    ref.read(etagCacheProvider).clear();
    ref.invalidate(forgeTokenProvider);
  }

  Future<void> _connect() async {
    // setState only takes effect on the next frame, and build() is the only
    // place _busy is otherwise consulted, so a second tap landing before
    // that frame would see the same not-yet-disabled button. Checking the
    // field itself, here, does not wait on a rebuild.
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final raw = _field.text.trim();
    if (raw.isEmpty) return;
    setState(() => _busy = true);
    final token = ForgeToken(raw);
    final ok = await validateForgeToken(
      token,
      httpFor: (t) =>
          ForgeHttp(token: t, client: ref.read(forgeHttpClientProvider)),
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      ref
          .read(toastProvider.notifier)
          .show(l.forgeTokenRejected, kind: ToastKind.error);
      return;
    }
    final approved = await _credentials.approve(
      _githubHost,
      forgeTokenUsername,
      token,
    );
    _forgetDerivedState();
    if (!mounted) return;
    // approve's own contract warns it cannot promise this: a helper that
    // silently declines to store still exits zero, so the only honest proof
    // the token survived is reading it back through the same helper rather
    // than trusting the exit code that just asked it to keep one.
    var kept = false;
    if (approved) {
      kept = await _credentials.fill(_githubHost, forgeTokenUsername) != null;
      if (!mounted) return;
    }
    _field.clear();
    setState(() => _busy = false);
    if (kept) {
      ref
          .read(toastProvider.notifier)
          .show(l.forgeTokenSaved, kind: ToastKind.success);
    } else {
      ref
          .read(toastProvider.notifier)
          .show(l.forgeTokenNotKept, kind: ToastKind.error);
    }
  }

  Future<void> _disconnect() async {
    // See _connect's guard: build() is the only other place _busy is read,
    // so a second tap ahead of the next frame must be caught here instead.
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    // The helpers this app targets (osxkeychain, credential-store) key an
    // erase on host and username rather than on the password offered, so the
    // stored token does not have to be read back first. The username is not
    // optional in that arrangement: it is the whole of what distinguishes
    // this app's entry from the one the user pushes with.
    final forgotten = await _credentials.reject(
      _githubHost,
      forgeTokenUsername,
      const ForgeToken(''),
    );
    _forgetDerivedState();
    if (!mounted) return;
    setState(() => _busy = false);
    // reject's true only means git accepted the request, not that the
    // helper had a credential to forget — but false means the request never
    // reached the helper at all (an unusable host, a failed git process, or
    // a non-zero exit), so the token is still on disk and saying otherwise
    // would be the silent-failure shape this guards against.
    if (forgotten) {
      ref
          .read(toastProvider.notifier)
          .show(l.forgeTokenForgotten, kind: ToastKind.success);
    } else {
      ref
          .read(toastProvider.notifier)
          .show(l.forgeTokenNotForgotten, kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final activePath = ref.watch(workspaceProvider).activeTab?.path;
    final rateLimit = activePath == null
        ? null
        : ref.watch(forgeRateLimitProvider(activePath)).valueOrNull;
    // The refresh-interval control only makes sense once a token is on file
    // to spend: with none, nothing on a timer is ever eligible to tick.
    final connected =
        activePath != null &&
        ref.watch(forgeTokenProvider(activePath)).valueOrNull != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.forgeAccountTitle,
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.forgeRateBenefit,
          style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
        ),
        if (rateLimit != null) ...[
          const SizedBox(height: 4),
          Text(
            l.forgeRateRemaining(rateLimit.remaining, rateLimit.limit),
            style: TextStyle(color: t.textFaint, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _field,
                obscureText: true,
                enabled: !_busy,
                decoration: InputDecoration(labelText: l.forgeTokenLabel),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(l.forgeConnect),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy ? null : _disconnect,
              child: Text(l.forgeDisconnect),
            ),
          ],
        ),
        // Belongs here, not on the General tab: unlike auto-fetch (which
        // works with no token at all) this timer is inert without one, so
        // it is only ever meaningful right beside the token that gates it.
        if (connected) ...[
          const SizedBox(height: 12),
          _RefreshIntervalRow(
            seconds: ref.watch(
              settingsProvider.select((s) => s.forgeRefreshIntervalSeconds),
            ),
            onChanged: ref
                .read(settingsProvider.notifier)
                .setForgeRefreshInterval,
          ),
        ],
      ],
    );
  }
}

/// How often the pull-request panel refreshes on its own, offered only once
/// a token makes the timer eligible to run at all.
class _RefreshIntervalRow extends StatelessWidget {
  static const _options = [120, 300, 600, 1800];

  final int seconds;
  final ValueChanged<int> onChanged;
  const _RefreshIntervalRow({required this.seconds, required this.onChanged});

  static String _label(int s) => switch (s) {
    120 => '2m',
    300 => '5m',
    1800 => '30m',
    _ => '10m',
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Row(
      children: [
        Expanded(
          child: Text(
            l.forgeRefreshInterval,
            style: TextStyle(color: t.textPrimary, fontSize: 13),
          ),
        ),
        for (final o in _options)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text(_label(o), style: const TextStyle(fontSize: 12)),
              selected: seconds == o,
              onSelected: (_) => onChanged(o),
            ),
          ),
      ],
    );
  }
}
