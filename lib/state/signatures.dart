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

/// One tag verified, on demand. The details panel asks only for the tags
/// already decorating the shown commit, so a commit without tags costs no git
/// process at all; a lightweight or unsigned tag comes back unsigned.
final tagSignatureProvider = FutureProvider.family
    .autoDispose<SignatureVerdict, ({String repo, String name})>((
      ref,
      key,
    ) async {
      return GitReader(
        ref.watch(gitServiceProvider),
        key.repo,
      ).verifyTag(key.name);
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
