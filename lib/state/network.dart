import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_network_overrides.dart';
import '../domain/git/git_providers.dart';
import '../domain/net/proxy.dart';
import 'settings_controller.dart';

/// The process environment the proxy variables are read from. A seam so a
/// test can set them without touching the real one.
///
/// An app launched from Finder or the Dock has no shell profile behind it,
/// so variables exported there are absent; git's `http.proxy` is the setting
/// that reaches every launch.
final proxyEnvironmentProvider = Provider<Map<String, String>>(
  (ref) => Platform.environment,
);

/// git's `http.proxy` from global config, else system config: null when
/// unset, empty when set to turn the proxy off. Both scopes are named so
/// the answer never depends on which directory the app was started in — a
/// repository's own setting applies to that repository, not to the app.
/// Read once per session; Preferences invalidates it so an edit made outside
/// the app shows up there.
final gitHttpProxyProvider = FutureProvider<String?>((ref) async {
  final git = ref.watch(gitServiceProvider);
  try {
    for (final scope in const ['--global', '--system']) {
      final r = await git.run(['config', scope, '--get', 'http.proxy']);
      if (r.ok) return r.out;
    }
    return null;
  } on Object {
    // No git means no git config to honour, not a broken network.
    return null;
  }
});

/// How Mergelio's own requests are routed right now.
final proxyPolicyProvider = FutureProvider<ProxyPolicy>((ref) async {
  final mode = ref.watch(settingsProvider.select((s) => s.proxyMode));
  final url = ref.watch(settingsProvider.select((s) => s.proxyUrl));
  return ProxyPolicy(
    mode: ProxyMode.parse(mode),
    manualUrl: url,
    gitProxy: await ref.watch(gitHttpProxyProvider.future),
    env: ref.watch(proxyEnvironmentProvider),
  );
});

/// What git's network commands are told about the proxy, from the settings.
/// The app hands this to [gitNetworkOverridesProvider].
final gitProxyOverridesProvider = Provider<GitNetworkOverrides>((ref) {
  final (mode, url, forGit) = ref.watch(
    settingsProvider.select((s) => (s.proxyMode, s.proxyUrl, s.proxyForGit)),
  );
  return gitProxyOverrides(ProxyMode.parse(mode), url, forGit: forGit);
});
