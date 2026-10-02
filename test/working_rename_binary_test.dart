import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blob.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/binary_diff.dart';
import 'package:mergelio/state/diff_document.dart';
import 'package:mergelio/state/diff_target.dart';

/// Integration: a staged rename of an image in a real repository, read back
/// through the diff document, the side mapping, the blob reader and the codec.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory repo;
  const svc = SystemGitService();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );
  // Data after IEND is ignored by decoders; it gives git enough content to
  // pair a renamed and edited file by similarity.
  final tail = [for (var i = 0; i < 4000; i++) (i * 7) % 251];
  final before = [...png, ...tail];
  final after = [...png, ...tail.sublist(0, 3990), ...List.filled(10, 0)];

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: repo.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('mergelio_rename_bin_');
    await g(['init', '-q']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await g(['config', 'commit.gpgsign', 'false']);
    await File('${repo.path}/old.png').writeAsBytes(before);
    await g(['add', '.']);
    await g(['commit', '-q', '-m', 'base']);
    await g(['mv', 'old.png', 'new.png']);
  });

  DiffTarget target() => DiffTarget(
    repoPath: repo.path,
    path: 'new.png',
    origPath: 'old.png',
    staged: true,
  );

  test(
    'a pure staged rename is reported as a rename, not as a new file',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final doc = await c.read(diffDocumentProvider(target()).future);
      expect(doc.staged, isTrue);
      final file = doc.files.single;
      expect(file.status, GitChange.renamed);
      expect(file.oldPath, 'old.png');
    },
  );

  tearDown(() => repo.delete(recursive: true));

  test('asking for the unstaged side of a rename that is only staged falls '
      'back to the staged rename', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final doc = await c.read(
      diffDocumentProvider(
        DiffTarget(repoPath: repo.path, path: 'new.png', origPath: 'old.png'),
      ).future,
    );
    expect(doc.staged, isTrue);
    expect(doc.files.single.status, GitChange.renamed);
  });

  test('a renamed and edited image previews both sides, decoded', () async {
    await File('${repo.path}/new.png').writeAsBytes(after);
    await g(['add', 'new.png']);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final doc = await c.read(diffDocumentProvider(target()).future);
    final file = doc.files.single;
    expect(file.status, GitChange.renamed);
    expect(file.oldPath, 'old.png');

    expect(file.binary, isTrue);
    final sides = binarySidesFor(target(), file, staged: doc.staged);
    expect(sides.before, const RevisionBlob('HEAD', 'old.png'));
    expect(sides.after, const IndexBlob('new.png'));

    final reader = BlobReader(git: svc, bytes: svc, repoPath: repo.path);
    for (final (side, bytes) in [
      (sides.before!, before),
      (sides.after!, after),
    ]) {
      final load = await reader.read(side);
      expect(load!.bytes, bytes);
      final codec = await ui.instantiateImageCodec(load.bytes!);
      final frame = await codec.getNextFrame();
      expect((frame.image.width, frame.image.height), (1, 1));
      frame.image.dispose();
      codec.dispose();
    }
  });
}
