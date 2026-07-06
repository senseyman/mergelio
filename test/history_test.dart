import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/history.dart';

void main() {
  group('History (undo/redo)', () {
    test('push records snapshots and clears redo', () {
      final h = History<int>();
      expect(h.canUndo, false);
      h.push(1);
      h.push(2);
      expect(h.undoDepth, 2);
      expect(h.canRedo, false);
    });

    test('undo/redo restore neighbouring snapshots', () {
      final h = History<int>();
      h.push(1);
      h.push(2); // states seen: 1, 2 before current 3
      expect(h.undo(3), 2); // past=[1], future=[3]
      expect(h.undo(2), 1); // past=[], future=[2,3]
      expect(h.canUndo, false);
      expect(h.undo(1), null); // nothing to undo
      expect(h.redo(1), 2); // past=[1], future=[3]
      expect(h.redo(2), 3); // past=[1,2], future=[]
      expect(h.canRedo, false);
    });

    test('a new push clears the redo stack', () {
      final h = History<int>();
      h.push(1);
      h.undo(2); // future=[2]
      expect(h.canRedo, true);
      h.push(5);
      expect(h.canRedo, false);
    });

    test('cap bounds the past stack', () {
      final h = History<int>(cap: 3);
      for (var i = 0; i < 10; i++) {
        h.push(i);
      }
      expect(h.undoDepth, 3);
    });
  });
}
