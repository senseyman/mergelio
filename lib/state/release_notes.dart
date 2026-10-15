import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pub_semver/pub_semver.dart';

import '../data/kv_store.dart';
import '../data/update/host_info.dart';
import '../domain/release_notes/release_notes.dart';
import '../domain/update/app_version.dart';
import 'operation_journal.dart' show kvStoreProvider;

/// Store key holding the last version whose launch was handled.
const releaseNotesSeenKey = 'releaseNotes.lastSeen';

/// Decides which notes this launch of [current] shows, and records [current]
/// as seen before returning — a quit or crash with the tab still open does not
/// bring the notes back. A downgrade lowers the marker, so upgrading again
/// shows the notes again.
Future<List<Version>> releaseNotesOnLaunch({
  required KeyValueStore store,
  required Version current,
  required Iterable<Version> available,
}) async {
  final raw = await store.get(releaseNotesSeenKey);
  final lastSeen = raw == null ? null : AppVersion.tryParse(raw)?.semver;
  await store.put(releaseNotesSeenKey, current.toString());
  return versionsToShow(
    lastSeen: lastSeen,
    current: current,
    available: available,
  );
}

/// Versions with bundled notes, and the languages each has them in.
final releaseNotesAssetsProvider = FutureProvider<Map<Version, Set<String>>>((
  ref,
) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return parseNotesAssets(manifest.listAssets());
});

/// The running build's version without its build number — notes are per
/// release, not per build.
final currentReleaseProvider = FutureProvider<Version>(
  (ref) async => (await currentAppVersion()).semver,
);

/// This run's launch decision. Any failure (no package info, no asset
/// manifest, a store error) means no tab rather than a broken launch.
final releaseNotesLaunchProvider = FutureProvider<List<Version>>((ref) async {
  try {
    final current = await ref.watch(currentReleaseProvider.future);
    final available = await ref.watch(releaseNotesAssetsProvider.future);
    return await releaseNotesOnLaunch(
      store: ref.read(kvStoreProvider),
      current: current,
      available: available.keys,
    );
  } catch (_) {
    return const [];
  }
});

/// Markdown text of one bundled notes file, by asset key.
final releaseNotesTextProvider = FutureProvider.family<String, String>(
  (ref, key) => rootBundle.loadString(key),
);
