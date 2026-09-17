import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../data/forge/forge_credentials.dart';
import '../../data/forge/forge_http.dart';
import '../../domain/git/git_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
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

/// Connect, inspect or disconnect the token used for github.com.
class ForgeAccountRow extends ConsumerStatefulWidget {
  const ForgeAccountRow({super.key});

  @override
  ConsumerState<ForgeAccountRow> createState() => _ForgeAccountRowState();
}

class _ForgeAccountRowState extends ConsumerState<ForgeAccountRow> {
  final _field = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  ForgeCredentials get _credentials =>
      ForgeCredentials(ref.read(gitServiceProvider));

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
    await _credentials.approve(_githubHost, 'x-access-token', token);
    // A body fetched without a token must not be served as though it were
    // fetched with one, and one fetched under a token that just changed must
    // not be served under the one that replaced it.
    ref.read(etagCacheProvider).clear();
    if (!mounted) return;
    _field.clear();
    setState(() => _busy = false);
    ref
        .read(toastProvider.notifier)
        .show(l.forgeTokenSaved, kind: ToastKind.success);
  }

  Future<void> _disconnect() async {
    // See _connect's guard: build() is the only other place _busy is read,
    // so a second tap ahead of the next frame must be caught here instead.
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    // An empty password field is an ordinary, well-formed credential body —
    // nothing in the write path treats it specially — and the helpers this
    // app targets (osxkeychain, credential-store) key erase on host and
    // username, not on the password offered, so there is no stored token to
    // look up first.
    final forgotten = await _credentials.reject(
      _githubHost,
      const ForgeToken(''),
    );
    ref.read(etagCacheProvider).clear();
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
      ],
    );
  }
}
