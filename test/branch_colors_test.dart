import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';

Commit _tip(String sha, int ci, List<GitRef> refs) => Commit(
  sha: sha,
  message: '',
  author: 'T',
  authorEmail: 't@e',
  date: DateTime(2026),
  ci: ci,
  refs: refs,
);

void main() {
  group('assignBranchColors', () {
    test('colours each branch by the lane of its tip commit', () {
      final commits = [
        _tip('a', 0, const [GitRef(kind: RefKind.local, name: 'main')]),
        _tip('b', 3, const [GitRef(kind: RefKind.local, name: 'feature/x')]),
      ];
      final out = assignBranchColors([
        const Branch(name: 'main'),
        const Branch(name: 'feature/x'),
      ], commits);

      expect(out.firstWhere((b) => b.name == 'main').ci, 0);
      expect(out.firstWhere((b) => b.name == 'feature/x').ci, 3);
    });

    test('keeps existing ci for a branch with no tip in the commit list', () {
      final out = assignBranchColors([
        const Branch(name: 'ghost', ci: 5),
      ], const []);
      expect(out.single.ci, 5);
    });

    test('only local refs drive the colour, not HEAD/remote/tag', () {
      final commits = [
        _tip('a', 2, const [
          GitRef(kind: RefKind.head, name: 'HEAD'),
          GitRef(kind: RefKind.remote, name: 'origin/main'),
          GitRef(kind: RefKind.local, name: 'main'),
        ]),
      ];
      final out = assignBranchColors([const Branch(name: 'main')], commits);
      expect(out.single.ci, 2);
    });
  });
}
