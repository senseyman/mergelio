import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/concurrency.dart';

/// A GUI app on macOS gets 256 file descriptors (`launchctl limit maxfiles`),
/// and every git subprocess costs several. The gate is what keeps a repo with
/// hundreds of branches from exhausting them, so its accounting has to hold up
/// under failure as well as success.
void main() {
  test('runs straight away while below the limit', () async {
    final gate = ConcurrencyGate(2);

    expect(await gate.run(() async => 'done'), 'done');
  });

  test('never lets more than the limit run at once', () async {
    final gate = ConcurrencyGate(3);
    var running = 0;
    var peak = 0;
    final completers = <Completer<void>>[];

    final tasks = [
      for (var i = 0; i < 10; i++)
        gate.run(() async {
          running++;
          peak = running > peak ? running : peak;
          final c = Completer<void>();
          completers.add(c);
          await c.future;
          running--;
        }),
    ];

    // Release the queue in waves, so the gate has to hand slots on.
    while (completers.length < 10 || completers.any((c) => !c.isCompleted)) {
      for (final c in [...completers]) {
        if (!c.isCompleted) c.complete();
      }
      await Future<void>.delayed(Duration.zero);
    }
    await Future.wait(tasks);

    expect(peak, 3);
  });

  test('frees the slot when a task throws', () async {
    final gate = ConcurrencyGate(1);

    await expectLater(
      gate.run(() async => throw StateError('boom')),
      throwsStateError,
    );

    expect(await gate.run(() async => 'after'), 'after');
    expect(gate.inFlight, 0);
  });

  test('admits queued tasks in the order they arrived', () async {
    final gate = ConcurrencyGate(1);
    final order = <int>[];
    final blocker = Completer<void>();

    final first = gate.run(() async {
      order.add(0);
      await blocker.future;
    });
    final rest = [
      for (var i = 1; i <= 3; i++) gate.run(() async => order.add(i)),
    ];

    blocker.complete();
    await Future.wait([first, ...rest]);

    expect(order, [0, 1, 2, 3]);
  });
}
