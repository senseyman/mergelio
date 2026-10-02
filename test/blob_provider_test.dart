import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blob.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/binary_diff.dart';

/// A git that can size blobs and stream their bytes.
class _BytesGit implements GitService, GitBytesRunner {
  final Map<String, Uint8List> blobs;
  _BytesGit(this.blobs);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    final blob = blobs[args.last];
    return blob == null
        ? const GitResult(128, '', 'fatal: not a valid object name')
        : GitResult(0, '${blob.length}\n', '');
  }

  @override
  Future<Uint8List?> runBytes(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    required int maxBytes,
  }) async => blobs[args.last];

  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

/// A git with no byte channel, like the fakes most tests use.
class _TextGit implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '3\n', '');
  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

ProviderContainer _c(GitService git) {
  final c = ProviderContainer(
    overrides: [gitServiceProvider.overrideWithValue(git)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('loads a side through the engine', () async {
    final git = _BytesGit({
      'HEAD:a.png': Uint8List.fromList([1, 2, 3]),
    });
    final load = await _c(git).read(
      blobProvider(
        const BlobRequest(repoPath: '/r', ref: RevisionBlob('HEAD', 'a.png')),
      ).future,
    );
    expect(load!.bytes, [1, 2, 3]);
  });

  test('an engine that cannot hand back bytes fails the load', () async {
    final c = _c(_TextGit());
    final req = blobProvider(
      const BlobRequest(repoPath: '/r', ref: RevisionBlob('HEAD', 'a.png')),
    );
    c.listen(req, (_, _) {});
    await expectLater(c.read(req.future), throwsUnsupportedError);
  });

  test('requests for the same side at the same version are one request', () {
    final v = Object();
    expect(
      BlobRequest(repoPath: '/r', ref: const IndexBlob('a'), version: v),
      BlobRequest(repoPath: '/r', ref: const IndexBlob('a'), version: v),
    );
    expect(
      BlobRequest(repoPath: '/r', ref: const IndexBlob('a'), version: v),
      isNot(
        BlobRequest(
          repoPath: '/r',
          ref: const IndexBlob('a'),
          version: Object(),
        ),
      ),
    );
  });
}
