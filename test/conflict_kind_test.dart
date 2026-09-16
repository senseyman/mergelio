import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';

/// A status v2 `u` record carries an XY code — UU, AA, DD, DU, UD — that says
/// which sides of the conflict still have content. Collapsing it to
/// "conflicted" throws away the only fact that decides whether a side can be
/// kept at all.
class _StubGit implements GitService {
  final String stdout;
  _StubGit(this.stdout);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => GitResult(0, stdout, '');

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  const nul = '\x00';
  const zero = '0000000000000000000000000000000000000000';

  String u(String xy, String path) =>
      'u $xy N... 100644 100644 100644 100644 $zero $zero $zero $path';

  Future<List<WorkingFile>> parse(String stdout) =>
      GitReader(_StubGit(stdout), '/r').status();

  test('an unmerged entry keeps its XY code as a conflict kind', () async {
    final files = await parse('${u('UU', 'a.txt')}$nul');
    expect(files.single.isConflicted, isTrue);
    expect(files.single.conflict, ConflictKind.bothModified);
  });

  test('every XY code maps to the kind it names', () async {
    final files = await parse(
      [
        u('UU', 'both_mod'),
        u('AA', 'both_add'),
        u('DD', 'both_del'),
        u('AU', 'added_us'),
        u('UA', 'added_them'),
        u('DU', 'deleted_us'),
        u('UD', 'deleted_them'),
        '',
      ].join(nul),
    );
    expect(
      {for (final f in files) f.path: f.conflict},
      {
        'both_mod': ConflictKind.bothModified,
        'both_add': ConflictKind.bothAdded,
        'both_del': ConflictKind.bothDeleted,
        'added_us': ConflictKind.addedByUs,
        'added_them': ConflictKind.addedByThem,
        'deleted_us': ConflictKind.deletedByUs,
        'deleted_them': ConflictKind.deletedByThem,
      },
    );
  });

  test('a kind says which sides still have content', () {
    expect(ConflictKind.bothModified.hasOurs, isTrue);
    expect(ConflictKind.bothModified.hasTheirs, isTrue);
    expect(ConflictKind.deletedByUs.hasOurs, isFalse);
    expect(ConflictKind.deletedByUs.hasTheirs, isTrue);
    expect(ConflictKind.deletedByThem.hasOurs, isTrue);
    expect(ConflictKind.deletedByThem.hasTheirs, isFalse);
    expect(ConflictKind.bothDeleted.hasOurs, isFalse);
    expect(ConflictKind.bothDeleted.hasTheirs, isFalse);
  });

  test('an unknown XY code falls back to a two-sided conflict', () async {
    final files = await parse('${u('ZZ', 'odd.txt')}$nul');
    expect(files.single.conflict, ConflictKind.bothModified);
  });

  test('a gitlink conflict is flagged as a submodule', () async {
    final files = await parse(
      'u UU S..U 160000 160000 160000 160000 $zero $zero $zero sub\x00',
    );
    expect(files.single.submodule, isTrue);
  });

  test('an ordinary file conflict is not a submodule', () async {
    final files = await parse('${u('UU', 'a.txt')}$nul');
    expect(files.single.submodule, isFalse);
  });

  test('unmergedFiles lists only the conflicted entries', () async {
    const tracked = '1 .M N... 100644 100644 100644 $zero $zero clean.txt';
    final files = await GitReader(
      _StubGit([tracked, u('DU', 'gone.txt'), ''].join(nul)),
      '/r',
    ).unmergedFiles();
    expect(files, hasLength(1));
    expect(files.single.path, 'gone.txt');
    expect(files.single.conflict, ConflictKind.deletedByUs);
  });
}
