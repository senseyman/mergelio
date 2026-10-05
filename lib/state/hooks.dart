import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/hooks.dart';

/// Whether the next commit in a repository skips its hooks. Armed by hand for
/// one commit at a time: a successful commit disarms it, and so does the
/// composer going away — switching tabs, closing the repository — so hooks
/// are never found off long after the choice was made. Never saved.
final skipHooksOnceProvider = StateProvider.autoDispose.family<bool, String>(
  (_, _) => false,
);

/// The hooks git would run for a repository. Reads the filesystem, so widget
/// tests override it.
///
/// While something watches it, the hooks directory is watched too, so a hook
/// added, edited or re-moded from a terminal shows up without reopening the
/// panel. It is auto-disposed, so the watch ends when the panel closes.
final hookInventoryProvider = FutureProvider.autoDispose
    .family<HookInventory, String>((ref, repoPath) async {
      final inv = await readHookInventory(
        ref.watch(gitServiceProvider),
        repoPath,
      );
      final dir = Directory(inv.dir);
      if (await dir.exists()) {
        try {
          final sub = dir.watch().listen(
            (_) => ref.invalidateSelf(),
            // A watch the platform cannot keep only loses live updates.
            onError: (Object e) =>
                appLog.warn('hooks watch error: $e', scope: repoPath),
          );
          ref.onDispose(sub.cancel);
        } on Object catch (e) {
          appLog.warn('hooks watch unavailable: $e', scope: repoPath);
        }
      }
      return inv;
    });

/// Changes made to hook files from the hooks panel. These are single-file
/// writes rather than git operations, so they take no repository lock. Each
/// returns why it failed, or null when it landed; reporting it is the
/// caller's, which has the words for it.
class HookActions {
  final Ref _ref;
  final String repoPath;
  HookActions(this._ref, this.repoPath);

  Future<HookWriteException?> setEnabled(
    String dir,
    String name, {
    required bool enabled,
  }) => _write(
    name,
    () => setHookEnabled(dir, name, enabled: enabled, repoPath: repoPath),
  );

  Future<HookWriteException?> save(String dir, String name, String text) =>
      _write(name, () => writeHook(dir, name, text, repoPath: repoPath));

  Future<HookWriteException?> useSample(String dir, String name) =>
      _write(name, () => installSample(dir, name, repoPath: repoPath));

  Future<HookWriteException?> _write(
    String name,
    Future<void> Function() run,
  ) async {
    try {
      await run();
      return null;
    } on HookWriteException catch (e) {
      appLog.warn('Changing the $name hook failed: $e', scope: repoPath);
      return e;
    } finally {
      _ref.invalidate(hookInventoryProvider(repoPath));
    }
  }
}

final hookActionsProvider = Provider.family<HookActions, String>(
  (ref, repoPath) => HookActions(ref, repoPath),
);
