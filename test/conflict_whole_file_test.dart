import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/conflict.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/merge_session.dart';

/// Conflicts git leaves without `<<<<<<<` markers — a delete/modify pair, or
/// binary content — are resolved by keeping one whole side or dropping the
/// path, not hunk by hunk.
void main() {
  group('isBinaryContent', () {
    test('text without NUL bytes is not binary', () {
      expect(isBinaryContent('hello\nworld\n'.codeUnits), isFalse);
    });

    test('a NUL byte marks the content binary', () {
      expect(isBinaryContent([0x89, 0x50, 0x00, 0x4e]), isTrue);
    });

    test('empty content is not binary', () {
      expect(isBinaryContent(const []), isFalse);
    });

    test('a NUL past the sniffed prefix is ignored', () {
      expect(isBinaryContent([...List.filled(9000, 0x61), 0]), isFalse);
    });
  });

  group('ConflictFile', () {
    test('a two-sided text conflict stays hunk by hunk', () {
      final f = ConflictFile(
        path: 'a.txt',
        parts: parseConflicts(
          '<<<<<<< HEAD\nmine\n=======\ntheirs\n>>>>>>> x\n',
        ),
      );
      expect(f.wholeFile, isFalse);
      expect(f.total, 1);
      expect(f.resolved, isFalse);
    });

    test('binary content is resolved as a whole file', () {
      const f = ConflictFile(path: 'logo.png', parts: [], binary: true);
      expect(f.wholeFile, isTrue);
      expect(f.total, 1);
      expect(f.resolvedCount, 0);
      expect(f.resolved, isFalse);
    });

    test('a side that no longer exists makes it a whole-file conflict', () {
      const f = ConflictFile(
        path: 'a.txt',
        parts: [],
        kind: ConflictKind.deletedByThem,
      );
      expect(f.wholeFile, isTrue);
      expect(f.fileOptions, [FileResolution.ours, FileResolution.delete]);
    });

    test('a deleted-by-us conflict cannot keep our side', () {
      const f = ConflictFile(
        path: 'a.txt',
        parts: [],
        kind: ConflictKind.deletedByUs,
      );
      expect(f.fileOptions, [FileResolution.theirs, FileResolution.delete]);
    });

    test('a binary conflict offers both sides and delete', () {
      const f = ConflictFile(path: 'logo.png', parts: [], binary: true);
      expect(f.fileOptions, [
        FileResolution.ours,
        FileResolution.theirs,
        FileResolution.delete,
      ]);
    });

    test('both sides deleted leaves only delete', () {
      const f = ConflictFile(
        path: 'a.txt',
        parts: [],
        kind: ConflictKind.bothDeleted,
      );
      expect(f.fileOptions, [FileResolution.delete]);
    });

    test('a submodule conflict is resolved as a whole file', () {
      // There is no text to merge in a gitlink — only which commit to point at.
      const f = ConflictFile(path: 'sub', parts: [], submodule: true);
      expect(f.wholeFile, isTrue);
      expect(f.fileOptions, [
        FileResolution.ours,
        FileResolution.theirs,
        FileResolution.delete,
      ]);
    });

    test('choosing a side resolves the file', () {
      const f = ConflictFile(path: 'logo.png', parts: [], binary: true);
      final chosen = f.withFileChoice(FileResolution.theirs);
      expect(chosen.fileChoice, FileResolution.theirs);
      expect(chosen.resolvedCount, 1);
      expect(chosen.resolved, isTrue);
    });

    test('a markerless text file with both sides present stays resolved', () {
      // The user edited the markers away by hand: nothing left to pick.
      final f = ConflictFile(path: 'a.txt', parts: parseConflicts('done\n'));
      expect(f.wholeFile, isFalse);
      expect(f.resolved, isTrue);
    });
  });
}
