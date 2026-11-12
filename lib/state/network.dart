import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// git's `http.proxy` from global and system config: null when unset, empty
/// when set to turn the proxy off. Read once per session; Preferences
/// invalidates it so an edit made outside the app shows up there.
final gitHttpProxyProvider = FutureProvider<String?>((ref) async {
  try {
    final r = await ref.watch(gitServiceProvider).run([
      'config',
      '--get',
      'http.proxy',
    ]);
    return r.ok ? r.out : null;
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
