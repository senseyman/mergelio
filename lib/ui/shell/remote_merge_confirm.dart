import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../domain/git/remote_ref.dart';
import '../../state/repo_actions.dart';
import '../../state/repo_data.dart';
import '../common/dialogs.dart';

/// What to do about a merge whose source is a remote-tracking ref.
enum _RemoteMergeChoice { cancel, mergeAsIs, fetchThenMerge }

/// Gate in front of any merge: when [source] is a remote-tracking ref, asks
/// whether to fetch that remote first (and does it), because the local
/// remote-tracking ref is only as fresh as the last fetch. Returns false when
/// the user cancelled. A local source passes straight through without a prompt.
Future<bool> confirmRemoteSource(
  BuildContext context,
  WidgetRef ref, {
  required String repoPath,
  required String source,
}) async {
  // Awaited rather than read: a snapshot taken before the repository has
  // loaded would report no remotes and skip the prompt entirely.
  List<String> remotes;
  try {
    remotes = (await ref.read(repoDataProvider(repoPath).future)).remotes;
  } on Object catch (_) {
    remotes = const [];
  }
  final split = splitRemoteRef(source, remotes);
  if (split == null) return true;
  final (remote, _) = split;

  if (!context.mounted) return false;
  final choice = await _ask(
    context,
    source: source,
    remote: remote,
    repoPath: repoPath,
  );
  if (choice != _RemoteMergeChoice.fetchThenMerge) {
    return choice == _RemoteMergeChoice.mergeAsIs;
  }
  await ref.read(repoActionsProvider(repoPath)).fetch(remote: remote);
  return true;
}

/// How long ago this repository last fetched, from the mtime of FETCH_HEAD, or
/// null when it has never fetched (or the file cannot be read).
Future<Duration?> _lastFetchAge(String repoPath) async {
  final stat = await FileStat.stat('$repoPath/.git/FETCH_HEAD');
  if (stat.type == FileSystemEntityType.notFound) return null;
  final age = DateTime.now().difference(stat.modified);
  return age.isNegative ? Duration.zero : age;
}

String _ageLabel(Duration d) {
  if (d.inMinutes < 1) return 'moments ago';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// Best-effort "last fetched" line. Loaded inside the dialog rather than
/// before it, so a slow or unreadable .git never delays the prompt.
class _LastFetchLine extends StatelessWidget {
  final String repoPath;
  const _LastFetchLine({required this.repoPath});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return FutureBuilder<Duration?>(
      future: _lastFetchAge(repoPath),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(height: 15);
        }
        return Text(
          snap.data == null
              ? 'This repository has not fetched yet.'
              : 'Last fetched ${_ageLabel(snap.data!)}.',
          style: TextStyle(color: t.textFaint, fontSize: 12),
        );
      },
    );
  }
}

Future<_RemoteMergeChoice> _ask(
  BuildContext context, {
  required String source,
  required String remote,
  required String repoPath,
}) async {
  final t = context.tokens;
  final result = await showAppModal<_RemoteMergeChoice>(
    context: context,
    title: 'Merge from $remote?',
    icon: Icons.cloud_download_outlined,
    width: 520,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$source is a remote-tracking branch. It is only as current as the '
          'last fetch from $remote.',
          style: TextStyle(color: t.textMuted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 8),
        _LastFetchLine(repoPath: repoPath),
      ],
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(_RemoteMergeChoice.cancel),
          child: const Text('Cancel'),
        ),
      ),
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).pop(_RemoteMergeChoice.mergeAsIs),
          child: const Text('Merge as-is'),
        ),
      ),
      Builder(
        builder: (ctx) => FilledButton(
          onPressed: () =>
              Navigator.of(ctx).pop(_RemoteMergeChoice.fetchThenMerge),
          child: const Text('Fetch and merge'),
        ),
      ),
    ],
  );
  return result ?? _RemoteMergeChoice.cancel;
}
