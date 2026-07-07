import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/undo_stack.dart';

void main() {
  group('UndoController', () {
    late List<String> log;
    late UndoController c;

    UndoEntry entry(String name) => UndoEntry(
      name,
      undo: () async => log.add('undo:$name'),
      redo: () async => log.add('redo:$name'),
    );

    setUp(() {
      log = [];
      c = UndoController();
    });

    test('records and reports availability', () {
      expect(c.state.canUndo, isFalse);
      c.record(entry('checkout'));
      expect(c.state.canUndo, isTrue);
      expect(c.state.canRedo, isFalse);
      expect(c.state.undoLabel, 'checkout');
    });

    test('undo runs the entry and moves it to the redo future', () async {
      c.record(entry('a'));
      await c.undo();
      expect(log, ['undo:a']);
      expect(c.state.canUndo, isFalse);
      expect(c.state.canRedo, isTrue);
      expect(c.state.redoLabel, 'a');
    });

    test('redo re-applies and moves it back to past', () async {
      c.record(entry('a'));
      await c.undo();
      await c.redo();
      expect(log, ['undo:a', 'redo:a']);
      expect(c.state.canUndo, isTrue);
      expect(c.state.canRedo, isFalse);
    });

    test('recording a new action clears the redo future', () async {
      c.record(entry('a'));
      await c.undo();
      expect(c.state.canRedo, isTrue);
      c.record(entry('b'));
      expect(c.state.canRedo, isFalse);
      expect(c.state.undoLabel, 'b');
    });

    test('undo/redo are no-ops on empty stacks', () async {
      await c.undo();
      await c.redo();
      expect(log, isEmpty);
    });

    test('a re-entrant undo is ignored while one is in flight', () async {
      final gate = Completer<void>();
      c.record(
        UndoEntry(
          'slow',
          undo: () async {
            log.add('undo:slow');
            await gate.future;
          },
          redo: () async {},
        ),
      );

      final first = c.undo(); // starts, awaits the gate
      await c.undo(); // re-entrant: must be ignored, not double-run
      gate.complete();
      await first;

      expect(log, ['undo:slow']); // ran exactly once
      expect(c.state.canUndo, isFalse);
    });

    test('history is capped at 40 entries', () {
      for (var i = 0; i < 45; i++) {
        c.record(entry('e$i'));
      }
      expect(c.state.past.length, 40);
      expect(c.state.past.first.label, 'e5'); // oldest 5 dropped
    });
  });
}
