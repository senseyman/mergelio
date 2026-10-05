import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/hooks.dart';
import 'feedback.dart';

/// Whether the next commit in a repository skips its hooks. Armed by hand for
/// one commit at a time: a successful commit disarms it, and it is never
/// saved, so a restart cannot leave hooks silently off.
final skipHooksOnceProvider = StateProvider.family<bool, String>(
  (_, _) => false,
);

/// The hooks git would run for a repository. Reads the filesystem, so widget
/// tests override it.
final hookInventoryProvider = FutureProvider.autoDispose
    .family<HookInventory, String>(
      (ref, repoPath) =>
          readHookInventory(ref.watch(gitServiceProvider), repoPath),
    );

/// Changes made to hook files from the hooks panel. These are single-file
/// writes rather than git operations, so they take no repository lock; each
/// reports whether it landed and toasts the reason when it did not.
class HookActions {
  final Ref _ref;
  final String repoPath;
  HookActions(this._ref, this.repoPath);

  Future<bool> setEnabled(String dir, String name, {required bool enabled}) =>
      _write(
        name,
        () => setHookEnabled(dir, name, enabled: enabled, repoPath: repoPath),
      );

  Future<bool> save(String dir, String name, String text) =>
      _write(name, () => writeHook(dir, name, text, repoPath: repoPath));

  Future<bool> useSample(String dir, String name) =>
      _write(name, () => installSample(dir, name, repoPath: repoPath));

  Future<bool> _write(String name, Future<void> Function() run) async {
    try {
      await run();
      return true;
    } on FileSystemException catch (e) {
      appLog.warn('Changing the $name hook failed: $e', scope: repoPath);
      _ref
          .read(toastProvider.notifier)
          .show(
            'Could not change the $name hook',
            description: e.osError?.message ?? e.message,
            kind: ToastKind.error,
          );
      return false;
    } finally {
      _ref.invalidate(hookInventoryProvider(repoPath));
    }
  }
}

final hookActionsProvider = Provider.family<HookActions, String>(
  (ref, repoPath) => HookActions(ref, repoPath),
);
