import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/ui/graph/squash_overlay.dart';

void main() {
  group('resolveSquashSegments', () {
    const index = {'tip': 1, 'landing': 4, 'other': 6};

    test('maps a link to the row indices of both endpoints', () {
      final segs = resolveSquashSegments(const [
        SquashLink(fromSha: 'tip', toSha: 'landing'),
      ], index);
      expect(segs, hasLength(1));
      expect(segs.single.fromIndex, 1);
      expect(segs.single.toIndex, 4);
    });

    test('drops links whose endpoints are not both present', () {
      final segs = resolveSquashSegments(const [
        SquashLink(fromSha: 'tip', toSha: 'missing'),
        SquashLink(fromSha: 'gone', toSha: 'landing'),
      ], index);
      expect(segs, isEmpty);
    });
  });
}
