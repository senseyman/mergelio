import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/git_service.dart';
import '../domain/git/signature.dart';

/// `gpg.ssh.allowedSignersFile` for a repository, null when unset. Read
/// alongside a verdict to explain why an SSH signature is only untrusted.
final allowedSignersFileProvider = FutureProvider.family
    .autoDispose<String?, String>((ref, repo) async {
      return GitReader(
        ref.watch(gitServiceProvider),
        repo,
      ).allowedSignersFile();
    });

/// A signed tag and what verifying it concluded.
typedef TagSignature = ({String name, SignatureVerdict verdict});

/// Signed tags pointing at one commit, each verified. On demand for the
/// commit shown in the details panel only, for the same reason commits are.
final tagSignaturesProvider = FutureProvider.family
    .autoDispose<List<TagSignature>, ({String repo, String sha})>((
      ref,
      key,
    ) async {
      final reader = GitReader(ref.watch(gitServiceProvider), key.repo);
      final names = await reader.signedTagsAt(key.sha);
      return [
        for (final name in names)
          (name: name, verdict: await reader.verifyTag(name)),
      ];
    });

/// Every commit in `base..HEAD` without a verified signature. Each signed
/// commit costs a gpg or ssh-keygen process, so the check is killed as soon
/// as nobody is waiting for it.
final signatureAuditProvider = FutureProvider.family
    .autoDispose<SignatureAudit, ({String repo, String base})>((
      ref,
      key,
    ) async {
      final cancel = GitCancel();
      ref.onDispose(cancel.cancel);
      return GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).signatureAudit(key.base, cancel: cancel);
    });
