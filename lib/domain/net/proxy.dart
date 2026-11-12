import '../git/git_network_overrides.dart';

/// The name a route carries when it came from the proxy typed into
/// Preferences rather than from git or the environment.
const kManualProxySetting = 'manual';

/// How Mergelio's own requests — forge APIs and update checks — pick a proxy.
/// Git's commands are not covered: git reads its own configuration.
enum ProxyMode {
  /// Whatever git would use: `http.proxy`, then the proxy environment.
  auto,

  /// The url typed into Preferences, for every request.
  manual,

  /// Always direct.
  off;

  /// Reads what settings store. Anything unrecognised is [auto], which is
  /// also what a fresh install gets.
  static ProxyMode parse(String stored) => switch (stored) {
    'manual' => manual,
    'off' => off,
    _ => auto,
  };
}

/// Where one request goes. [setting] names whatever decided it — a git
/// config key, an environment variable, or [kManualProxySetting] — so
/// Preferences can say why, not only what.
sealed class ProxyRoute {
  final String? setting;
  const ProxyRoute(this.setting);
}

/// Straight to the server. [setting] is null when nothing was configured.
class ProxyDirect extends ProxyRoute {
  const ProxyDirect([super.setting]);
}

/// Through a plain-http proxy.
class ProxyVia extends ProxyRoute {
  final String host;
  final int port;
  final String? user;
  final String? password;
  const ProxyVia({
    required this.host,
    required this.port,
    required String setting,
    this.user,
    this.password,
  }) : super(setting);

  /// `host:port`, bracketing an IPv6 literal. Never includes credentials, so
  /// it is safe to show.
  String get address => host.contains(':') ? '[$host]:$port' : '$host:$port';

  /// Whether the credentials can go into a dart:io proxy directive. It splits
  /// the directive on `;` and the userinfo on the first `:`, needs both a
  /// user and a password, and its parse error quotes the whole directive,
  /// password and all, into a message that gets logged.
  bool get _credentialsSendable =>
      user != null &&
      password != null &&
      !user!.contains(':') &&
      !'$user$password'.contains(';');

  /// Credentials were configured but will not be sent, so an authenticating
  /// proxy will answer 407.
  bool get credentialsDropped =>
      (user != null || password != null) && !_credentialsSendable;
}

/// A proxy is configured but `dart:io` cannot speak it — SOCKS, or TLS to
/// the proxy itself. Requests go direct; Preferences says so.
class ProxyUnsupported extends ProxyRoute {
  final String value;
  const ProxyUnsupported({required this.value, required String setting})
    : super(setting);
}

/// Reads a proxy the way git does: `[scheme://][user[:password]@]host[:port]`,
/// with http assumed and port 1080 when none is given.
ProxyRoute parseProxy(String raw, String setting) {
  final value = raw.trim();
  final withScheme = value.contains('://') ? value : 'http://$value';
  final Uri uri;
  try {
    uri = Uri.parse(withScheme);
  } on FormatException {
    return ProxyUnsupported(value: value, setting: setting);
  }
  if (uri.scheme != 'http' || uri.host.isEmpty) {
    return ProxyUnsupported(value: value, setting: setting);
  }
  final info = uri.userInfo;
  final colon = info.indexOf(':');
  final user = Uri.decodeComponent(colon < 0 ? info : info.substring(0, colon));
  final password = colon < 0
      ? ''
      : Uri.decodeComponent(info.substring(colon + 1));
  return ProxyVia(
    host: uri.host,
    port: uri.hasPort ? uri.port : 1080,
    setting: setting,
    user: user.isEmpty ? null : user,
    password: password.isEmpty ? null : password,
  );
}

/// Whether [host] is exempt under a `no_proxy` list: comma separated, each
/// entry matching itself and its subdomains, `*` matching everything.
bool noProxyMatches(String host, String list) {
  final h = host.toLowerCase();
  for (final raw in list.split(',')) {
    var entry = raw.trim().toLowerCase();
    if (entry == '*') return true;
    // A port is only told apart from an IPv6 literal's last group when the
    // literal is bracketed or the entry has a single colon.
    if (entry.startsWith('[')) {
      entry = entry.replaceFirst(RegExp(r'\]:\d+$'), ']');
      entry = entry.substring(1, entry.length - (entry.endsWith(']') ? 1 : 0));
    } else if (':'.allMatches(entry).length == 1) {
      entry = entry.replaceFirst(RegExp(r':\d+$'), '');
    }
    if (entry.startsWith('.')) entry = entry.substring(1);
    if (entry.isEmpty) continue;
    if (h == entry || h.endsWith('.$entry')) return true;
  }
  return false;
}

/// Everything that decides how Mergelio's own requests are routed. Pure, so
/// the same answer is given to the http client and to Preferences.
class ProxyPolicy {
  final ProxyMode mode;
  final String manualUrl;

  /// git's `http.proxy`; null when unset, empty when set to turn it off.
  final String? gitProxy;
  final Map<String, String> env;

  const ProxyPolicy({
    this.mode = ProxyMode.auto,
    this.manualUrl = '',
    this.gitProxy,
    this.env = const {},
  });

  ProxyRoute routeFor(Uri target) {
    switch (mode) {
      case ProxyMode.off:
        return const ProxyDirect();
      case ProxyMode.manual:
        final typed = manualUrl.trim();
        return typed.isEmpty
            ? const ProxyDirect()
            : parseProxy(typed, kManualProxySetting);
      case ProxyMode.auto:
        return _likeGit(target);
    }
  }

  /// Git's own order: `http.proxy` first — empty meaning none — then the
  /// scheme's variable, then `all_proxy`. Where both spellings are set the
  /// lowercase one wins, and plain-http targets ignore `HTTP_PROXY`, which
  /// a CGI request header can set. `no_proxy` exempts hosts from all of it.
  ProxyRoute _likeGit(Uri target) {
    final noProxy = _first(['no_proxy', 'NO_PROXY']);
    if (noProxy != null && noProxyMatches(target.host, env[noProxy]!)) {
      return ProxyDirect(noProxy);
    }
    final configured = gitProxy;
    if (configured != null) {
      return configured.trim().isEmpty
          ? const ProxyDirect('http.proxy')
          : parseProxy(configured, 'http.proxy');
    }
    final name =
        _first(
          target.scheme == 'https'
              ? ['https_proxy', 'HTTPS_PROXY']
              : ['http_proxy'],
        ) ??
        _first(['all_proxy', 'ALL_PROXY']);
    return name == null ? const ProxyDirect() : parseProxy(env[name]!, name);
  }

  String? _first(List<String> names) {
    for (final n in names) {
      if ((env[n] ?? '').trim().isNotEmpty) return n;
    }
    return null;
  }

  /// [routeFor] in the form `HttpClient.findProxy` takes. A proxy that
  /// cannot be spoken goes direct: failing every request instead would
  /// break the app for someone whose git is set up for SOCKS.
  ///
  /// Credentials go in only when [ProxyVia.credentialsDropped] is false;
  /// left out, the proxy answers 407 rather than the password being logged.
  String findProxy(Uri target) => switch (routeFor(target)) {
    final ProxyVia via when via._credentialsSendable =>
      'PROXY ${via.user}:${via.password}@${via.address}',
    ProxyVia(:final address) => 'PROXY $address',
    ProxyDirect() || ProxyUnsupported() => 'DIRECT',
  };
}

/// What git's own network commands are told when the app's proxy setting is
/// meant to cover them too. Automatic leaves git alone: git already reads the
/// configuration that mode follows. Manual hands git the typed url — git
/// speaks SOCKS and https proxies even where the app cannot — and lifts
/// `no_proxy`, as manual does for the app. Off, or manual with nothing typed,
/// sets an empty `http.proxy`, which git takes as no proxy at all.
GitNetworkOverrides gitProxyOverrides(
  ProxyMode mode,
  String manualUrl, {
  required bool forGit,
}) {
  if (!forGit || mode == ProxyMode.auto) return GitNetworkOverrides.none;
  final url = mode == ProxyMode.manual ? manualUrl.trim() : '';
  if (url.isEmpty) {
    return const GitNetworkOverrides(config: {'http.proxy': ''});
  }
  return GitNetworkOverrides(
    config: {'http.proxy': url},
    env: const {'NO_PROXY': '', 'no_proxy': ''},
  );
}
