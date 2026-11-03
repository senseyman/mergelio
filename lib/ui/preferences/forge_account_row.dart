import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../data/forge/forge_credentials.dart';
import '../../data/forge/forge_http.dart';
import '../../domain/forge/forge_host.dart';
import '../../domain/forge/forge_server.dart';
import '../../domain/git/git_providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/feedback.dart';
import '../../state/forge.dart';
import '../../state/settings_controller.dart';
import '../../state/workspace.dart';
import '../workspace/forge_presentation.dart';

/// Whether [server] accepts [token].
///
/// One request to the account the token belongs to, made before anything is
/// written to the keychain, so a mistyped token — or a token for a different
/// server — is reported while the person is still looking at the field
/// rather than as an empty panel an hour later. Anything other than a clean
/// answer counts as "not validated": an unreachable forge is not proof of a
/// bad token, and saving on that basis would be a guess — but so would
/// accepting it.
Future<bool> validateForgeToken(
  ForgeToken token, {
  required ForgeServer server,
  ForgeHttp Function(ForgeToken token)? httpFor,
}) async {
  final http = (httpFor ?? (t) => ForgeHttp(kind: server.kind, token: t))(
    token,
  );
  try {
    final response = await http.get(server.api('/user'));
    return response.status >= 200 && response.status < 300;
  } on Object {
    return false;
  } finally {
    http.close();
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

/// Scoped to [path]'s own git config, exactly as [forgeTokenProvider] and
/// [forgeAccountTokenProvider] read it — a write must land where the read
/// looks, or a repository whose local config overrides `credential.helper`
/// stores a token under one helper and reads it back through another. Null
/// falls back to the global configuration, for when no repository is open.
///
/// Everything below takes the [ProviderContainer] rather than a widget's
/// ref, captured before the first await: a credential write outlives the
/// dialog or tab that started it when the person closes either mid-write,
/// and a disposed widget's ref throws. The write has already been handed to
/// the helper by then, so the bookkeeping after it must still happen.
ForgeCredentials _credentialsFor(ProviderContainer c) => ForgeCredentials(
  c.read(gitServiceProvider),
  // The active tab even under the dashboard: its credential helper config
  // decides where the token lives, and that must not change just because
  // the dashboard is showing.
  repoPath: c.read(workspaceProvider).activeTab?.path,
);

/// Drops everything that was derived from a token that has just changed.
///
/// The stored token is read through providers that cache for the life of
/// the container, so without this a session that connects goes on sending
/// the answer it got before — which is to say no token at all — until the
/// app is restarted. The cached bodies go with it: a body fetched without a
/// token must not be served as though it were fetched with one, and one
/// fetched under a token that just changed must not be served under its
/// replacement.
void _forgetDerivedState(ProviderContainer c) {
  c.read(etagCacheProvider).clear();
  c.invalidate(forgeTokenProvider);
  c.invalidate(forgeAccountTokenProvider);
}

/// Erases this app's token for [server]. True when git accepted the request.
///
/// The helpers this app targets (osxkeychain, credential-store) key an erase
/// on host and username rather than on the password offered, so the stored
/// token does not have to be read back first. The username is not optional
/// in that arrangement: it is the whole of what distinguishes this app's
/// entry from the one the user pushes with.
Future<bool> _forget(ProviderContainer c, ForgeServer server) async {
  final forgotten = await _credentialsFor(c)
      .reject(server.credentialHost, forgeTokenUsername, const ForgeToken(''));
  _forgetDerivedState(c);
  return forgotten;
}

/// Opens the dialog that adds an account, or — given [server] — replaces the
/// token of an existing one.
Future<void> showForgeTokenDialog(
  BuildContext context, {
  ForgeServer? server,
}) => showDialog<void>(
  context: context,
  builder: (context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                server == null
                    ? l.forgeAddAccountTitle
                    : l.forgeTokenForTitle(forgeServerDisplayName(server)),
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ForgeTokenForm(server: server),
            ],
          ),
        ),
      ),
    );
  },
);

/// Collects a token — and, when no [server] is given, which forge and where
/// — then validates it, hands it to the credential helper and reads it back.
///
/// A self-hosted server is registered once its token has been validated, so
/// a typo in the address never leaves an entry behind.
class ForgeTokenForm extends ConsumerStatefulWidget {
  /// The server whose token this replaces, or null to ask for one.
  final ForgeServer? server;
  const ForgeTokenForm({super.key, this.server});

  @override
  ConsumerState<ForgeTokenForm> createState() => _ForgeTokenFormState();
}

class _ForgeTokenFormState extends ConsumerState<ForgeTokenForm> {
  final _token = _RedactedTextEditingController();
  final _url = TextEditingController();
  ForgeKind _kind = ForgeKind.github;
  bool _selfHosted = false;
  ForgeServerUrlProblem? _urlProblem;
  bool _busy = false;

  @override
  void dispose() {
    _token.dispose();
    _url.dispose();
    super.dispose();
  }

  /// The server this form is about, or null — with [_urlProblem] set — when
  /// the typed address is not usable.
  ForgeServer? _resolveServer() {
    final fixed = widget.server;
    if (fixed != null) return fixed;
    if (!_selfHosted) {
      return _kind == ForgeKind.github ? kGithubCloud : kGitlabCloud;
    }
    final parsed = parseForgeServerUrl(_url.text, _kind);
    setState(() => _urlProblem = parsed.problem);
    return parsed.server;
  }

  Future<void> _connect() async {
    // setState only takes effect on the next frame, and build() is the only
    // place _busy is otherwise consulted, so a second tap landing before
    // that frame would see the same not-yet-disabled button. Checking the
    // field itself, here, does not wait on a rebuild.
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final server = _resolveServer();
    if (server == null) return;
    final raw = _token.text.trim();
    if (raw.isEmpty) return;
    final name = forgeServerDisplayName(server);
    final c = ProviderScope.containerOf(context, listen: false);
    final toasts = c.read(toastProvider.notifier);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    final token = ForgeToken(raw);
    final ok = await validateForgeToken(
      token,
      server: server,
      httpFor: (t) => ForgeHttp(
        kind: server.kind,
        token: t,
        client: c.read(forgeHttpClientProvider),
      ),
    );
    // Closed while the server was still being asked: nothing has been
    // written yet, so that reads as a cancel.
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      toasts.show(l.forgeTokenRejected(name), kind: ToastKind.error);
      return;
    }
    // Entries this one replaces — the same host on another port — whose
    // tokens would otherwise stay in the helper under a key nothing lists.
    // Only a self-hosted server has entries; the clouds are never stored.
    final replaced = server.isCloud
        ? const <ForgeServer>[]
        : c
              .read(forgeServersProvider)
              .where((s) => s.host == server.host && s != server)
              .toList();
    // Registered before the helper is asked to keep the token: the server
    // answered for it, so its repositories should be recognised even if no
    // helper ends up storing anything.
    if (!server.isCloud) {
      c.read(settingsProvider.notifier).addForgeServer(server);
    }
    final credentials = _credentialsFor(c);
    for (final old in replaced) {
      await credentials.reject(
        old.credentialHost,
        forgeTokenUsername,
        const ForgeToken(''),
      );
    }
    final approved = await credentials.approve(
      server.credentialHost,
      forgeTokenUsername,
      token,
    );
    _forgetDerivedState(c);
    // approve's own contract warns it cannot promise this: a helper that
    // silently declines to store still exits zero, so the only honest proof
    // the token survived is reading it back through the same helper rather
    // than trusting the exit code that just asked it to keep one.
    final kept =
        approved &&
        await credentials.fill(server.credentialHost, forgeTokenUsername) !=
            null;
    if (kept) {
      toasts.show(l.forgeTokenSaved(name), kind: ToastKind.success);
    } else {
      toasts.show(l.forgeTokenNotKept(name), kind: ToastKind.error);
    }
    if (!mounted) return;
    _token.clear();
    setState(() => _busy = false);
    if (nav.canPop()) nav.pop();
  }

  String? _urlError(AppLocalizations l) => switch (_urlProblem) {
    null => null,
    ForgeServerUrlProblem.invalid => l.forgeUrlInvalid,
    ForgeServerUrlProblem.notHttps => l.forgeUrlNotHttps,
    ForgeServerUrlProblem.hasPath => l.forgeUrlHasPath,
    ForgeServerUrlProblem.isCloud => l.forgeUrlIsCloud,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final asking = widget.server == null;
    final github = _kind == ForgeKind.github;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (asking) ...[
          SegmentedButton<ForgeKind>(
            segments: const [
              ButtonSegment(value: ForgeKind.github, label: Text('GitHub')),
              ButtonSegment(value: ForgeKind.gitlab, label: Text('GitLab')),
            ],
            selected: {_kind},
            onSelectionChanged: _busy
                ? null
                : (v) => setState(() => _kind = v.single),
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(
                  github ? l.forgeWhereCloudGithub : l.forgeWhereCloudGitlab,
                ),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  github ? l.forgeWhereSelfGithub : l.forgeWhereSelfGitlab,
                ),
              ),
            ],
            selected: {_selfHosted},
            onSelectionChanged: _busy
                ? null
                : (v) => setState(() {
                    _selfHosted = v.single;
                    _urlProblem = null;
                  }),
          ),
          if (_selfHosted) ...[
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('forge-server-url'),
              controller: _url,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l.forgeServerUrlLabel,
                hintText: github
                    ? 'https://github.example.com'
                    : 'https://gitlab.example.com',
                errorText: _urlError(l),
                errorMaxLines: 3,
              ),
              onChanged: (_) {
                if (_urlProblem != null) setState(() => _urlProblem = null);
              },
            ),
          ],
          const SizedBox(height: 10),
        ],
        TextField(
          key: const ValueKey('forge-token'),
          controller: _token,
          obscureText: true,
          enabled: !_busy,
          autocorrect: false,
          decoration: InputDecoration(labelText: l.forgeTokenLabel),
          onSubmitted: (_) => _connect(),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (Navigator.of(context).canPop())
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(l.cancel),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: Text(l.forgeConnect),
            ),
          ],
        ),
      ],
    );
  }
}

/// One forge account: where it is, whether a token is on file, and what can
/// be done about it.
class ForgeAccountRow extends ConsumerStatefulWidget {
  final ForgeServer server;
  const ForgeAccountRow({super.key, required this.server});

  @override
  ConsumerState<ForgeAccountRow> createState() => _ForgeAccountRowState();
}

class _ForgeAccountRowState extends ConsumerState<ForgeAccountRow> {
  bool _busy = false;

  ForgeServer get _server => widget.server;

  Future<void> _disconnect() async {
    // A second tap ahead of the next frame must be caught here: build() is
    // the only other place _busy is read.
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final name = forgeServerDisplayName(_server);
    final c = ProviderScope.containerOf(context, listen: false);
    final toasts = c.read(toastProvider.notifier);
    setState(() => _busy = true);
    final forgotten = await _forget(c, _server);
    if (mounted) setState(() => _busy = false);
    // reject's true only means git accepted the request, not that the
    // helper had a credential to forget — but false means the request never
    // reached the helper at all (an unusable host, a failed git process, or
    // a non-zero exit), so the token is still on disk and saying otherwise
    // would be the silent-failure shape this guards against.
    if (forgotten) {
      toasts.show(l.forgeTokenForgotten(name), kind: ToastKind.success);
    } else {
      toasts.show(l.forgeTokenNotForgotten(name), kind: ToastKind.error);
    }
  }

  /// Forgets the server along with its token. The token goes first: a
  /// server removed while its token stayed in the helper would leave a
  /// secret behind that nothing in the app shows any more.
  Future<void> _remove() async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final name = forgeServerDisplayName(_server);
    final c = ProviderScope.containerOf(context, listen: false);
    final toasts = c.read(toastProvider.notifier);
    setState(() => _busy = true);
    final forgotten = await _forget(c, _server);
    if (mounted) setState(() => _busy = false);
    if (!forgotten) {
      toasts.show(l.forgeTokenNotForgotten(name), kind: ToastKind.error);
      return;
    }
    c.read(settingsProvider.notifier).removeForgeServer(_server);
    toasts.show(l.forgeServerRemoved(name), kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final activePath = ref.watch(workspaceProvider).activeTab?.path;
    // The budget is read for whichever repository is active, so it belongs
    // only on the row for that repository's own server — anywhere else it
    // would show one server's figures under another's heading. Only GitHub
    // publishes a budget that costs nothing to read.
    final activeServer = activePath == null
        ? null
        : ref.watch(forgeHostProvider(activePath)).valueOrNull?.server;
    final rateLimit =
        _server.kind != ForgeKind.github || activeServer != _server
        ? null
        : ref.watch(forgeRateLimitProvider(activePath!)).valueOrNull;
    // Independent of whatever repository is active — or whether one is open
    // at all: this row is about this server's own account, and a repository
    // elsewhere, or with no remote, must not make a token on file disappear
    // from view.
    final connected =
        ref
            .watch(
              forgeAccountTokenProvider((
                host: _server.credentialHost,
                path: activePath,
              )),
            )
            .valueOrNull !=
        null;
    final product = _server.isCloud
        ? forgeDisplayName(_server.kind)
        : forgeServerDisplayName(_server).split(' (').first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.forgeAccountTitle(product),
          style: TextStyle(
            color: t.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                _server.credentialHost,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.textMuted, fontSize: 12),
              ),
            ),
            Text(' · ', style: TextStyle(color: t.textFaint, fontSize: 12)),
            Text(
              connected ? l.forgeAccountConnected : l.forgeAccountNotConnected,
              style: TextStyle(
                color: connected ? t.success : t.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        // The published figures are the public services' own; a self-hosted
        // installation sets its limits itself, so quoting them there would
        // be a guess presented as fact.
        if (_server.isCloud) ...[
          const SizedBox(height: 8),
          Text(
            _server.kind == ForgeKind.github
                ? l.forgeRateBenefit
                : l.forgeRateBenefitGitlab,
            style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
          ),
        ],
        if (rateLimit != null) ...[
          const SizedBox(height: 4),
          Text(
            l.forgeRateRemaining(rateLimit.remaining, rateLimit.limit),
            style: TextStyle(color: t.textFaint, fontSize: 12),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => showForgeTokenDialog(context, server: _server),
              child: Text(
                connected ? l.forgeReplaceToken : l.forgeConnectAccount,
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _disconnect,
              child: Text(l.forgeDisconnect),
            ),
            if (!_server.isCloud)
              TextButton(
                onPressed: _busy ? null : _remove,
                style: TextButton.styleFrom(foregroundColor: t.danger),
                child: Text(l.forgeRemoveServer),
              ),
          ],
        ),
      ],
    );
  }
}

/// Every forge account, and the way to add one.
///
/// github.com and gitlab.com appear once a token for them is on file; a
/// self-hosted server appears from the moment it is added, token or not.
class ForgeAccountsSection extends ConsumerWidget {
  const ForgeAccountsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = context.tokens;
    final activePath = ref.watch(workspaceProvider).activeTab?.path;
    final accounts =
        ref.watch(forgeAccountListProvider(activePath)).valueOrNull ??
        const <ForgeServer>[];
    // The refresh interval is one setting shared by every forge, so it is
    // offered the moment any account has a token on file.
    final anyConnected = accounts.any(
      (s) =>
          ref
              .watch(
                forgeAccountTokenProvider((
                  host: s.credentialHost,
                  path: activePath,
                )),
              )
              .valueOrNull !=
          null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.forgeAccountsHeading,
                style: TextStyle(
                  color: t.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton.tonal(
              onPressed: () => showForgeTokenDialog(context),
              child: Text(l.forgeAddAccount),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          Text(
            l.forgeNoAccounts,
            style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
          ),
        for (final (i, server) in accounts.indexed) ...[
          if (i > 0) const SizedBox(height: 20),
          ForgeAccountRow(key: ValueKey(server.key), server: server),
        ],
        // Belongs here, not on the General tab: unlike auto-fetch (which
        // works with no token at all) this timer is inert without one, so
        // it is only ever meaningful right beside the accounts that gate it.
        if (anyConnected) ...[
          const SizedBox(height: 16),
          ForgeRefreshIntervalRow(
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
///
/// Public, and placed by the dialog rather than by [ForgeAccountRow]: the
/// interval is one setting shared by every forge, and rendering it inside
/// each account row would draw it once per row instead of once.
class ForgeRefreshIntervalRow extends StatelessWidget {
  static const _options = [120, 300, 600, 1800];

  final int seconds;
  final ValueChanged<int> onChanged;
  const ForgeRefreshIntervalRow({
    super.key,
    required this.seconds,
    required this.onChanged,
  });

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
