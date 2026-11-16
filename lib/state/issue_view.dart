import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/forge/models.dart';
import 'forge.dart';

/// Which issue of which repository is open in the centre column.
typedef IssueTarget = ({String repoPath, int number});

/// The issue open in the centre column, or null for none. Like a review, it
/// belongs to the repository that opened it; another tab shows its own
/// centre column, and this comes back when that repository is active again.
final issueTargetProvider = StateProvider<IssueTarget?>((_) => null);

/// One issue with its description, or null when the repository no longer
/// resolves to a forge.
///
/// AutoDispose, and never invalidated by the action layer: it is read once
/// per opened issue, closing the view is what lets it go, and the view's own
/// refresh control is the only thing that reads it again.
final issueDetailProvider = FutureProvider.family
    .autoDispose<IssueDetail?, IssueTarget>((ref, target) async {
      final forge = await ref.watch(forgeProvider(target.repoPath).future);
      if (forge == null) return null;
      return forge.issue(target.number);
    });
