import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/project_ops.dart';

/// Filesystem operations for one repository, keyed by its path.
final projectOpsProvider = Provider.family<ProjectOps, String>(
  (ref, repoPath) => ProjectOps(repoPath),
);
