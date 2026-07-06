import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/git/git_providers.dart';
import '../../state/feedback.dart';
import '../../state/recents.dart';
import '../../state/workspace.dart';

/// Native "open folder" dialog → validate it's a git repo → open a tab and
/// record it in recents. Surfaces a toast on any failure. No-op if cancelled.
Future<void> openRepositoryFlow(BuildContext context, WidgetRef ref) async {
  final path = await getDirectoryPath(confirmButtonText: 'Open');
  if (path == null) return;
  await openRepositoryPath(ref, path);
}

/// Opens an already-known [path] (used by Welcome recents and the flow above).
Future<void> openRepositoryPath(WidgetRef ref, String path) async {
  final toasts = ref.read(toastProvider.notifier);
  final isRepo = await ref.read(gitServiceProvider).isRepository(path);
  if (!isRepo) {
    toasts.show(
      'Not a git repository',
      description: path,
      kind: ToastKind.error,
    );
    return;
  }
  final tab = ref.read(workspaceProvider.notifier).openRepo(path);
  ref.read(recentsProvider.notifier).add(tab.name, path);
}
