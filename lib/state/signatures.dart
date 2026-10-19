import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging.dart';
import '../domain/git/git_providers.dart';
import '../domain/git/git_reader.dart';
import '../domain/git/git_service.dart';
import '../domain/git/signature.dart';
import '../domain/git/tag_info.dart';

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

/// The tags on one commit, with tagger and message. Asked for only when the
/// commit carries a tag ref, so an untagged commit costs no git process.
/// [names] is the commit's tag refs as the graph last read them: a tag added
/// to or removed from the commit on screen changes the key, so it is read
/// again rather than served from the earlier answer.
final tagInfosProvider = FutureProvider.family
    .autoDispose<List<TagInfo>, ({String repo, String sha, String names})>((
      ref,
      key,
    ) async {
      try {
        return await GitReader(
          ref.watch(gitServiceProvider),
          key.repo,
        ).tagInfos(key.sha);
      } catch (e) {
        appLog.warn('reading tags on ${key.sha} failed: $e', scope: 'tags');
        rethrow;
      }
    });

/// The repository's signing key and default, read when the create-tag dialog
/// opens.
final tagSigningProvider = FutureProvider.family
    .autoDispose<TagSigning, String>((ref, repo) async {
      return GitReader(ref.watch(gitServiceProvider), repo).tagSigning();
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
