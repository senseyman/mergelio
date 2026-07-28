import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/concurrency.dart';

/// Disk events arrive in bursts, and a repository read can outlast the burst
/// that triggered it. Without coalescing, each event starts another read on top
/// of the ones already running — twelve concurrent walks of the same repository
/// take far longer than one, which is how a refresh loop turns into a timeout.
void main() {
  const settle = Duration(milliseconds: 20);
  Future<void> tick([int times = 4]) => Future<void>.delayed(settle * times);

  test('collapses a burst of events into a single refresh', () async {
    var refreshes = 0;
    final c = RefreshCoalescer(
      settle: settle,
      busy: () => false,
      onRefresh: () => refreshes++,
    );

    for (var i = 0; i < 10; i++) {
      c.schedule();
    }
    await tick();

    expect(refreshes, 1);
  });

  test('waits while a read is still running rather than piling on', () async {
    var refreshes = 0;
    var busy = true;
    final c = RefreshCoalescer(
      settle: settle,
      busy: () => busy,
      onRefresh: () => refreshes++,
    );

    c.schedule();
    await tick();
    expect(refreshes, 0, reason: 'must not refresh while a read is in flight');

    busy = false;
    await tick();
    expect(refreshes, 1);
  });

  test('refreshes again for a burst that arrives after the last one', () async {
    var refreshes = 0;
    final c = RefreshCoalescer(
      settle: settle,
      busy: () => false,
      onRefresh: () => refreshes++,
    );

    c.schedule();
    await tick();
    c.schedule();
    await tick();

    expect(refreshes, 2);
  });

  test('cancel drops a refresh that has not fired yet', () async {
    var refreshes = 0;
    final c = RefreshCoalescer(
      settle: settle,
      busy: () => false,
      onRefresh: () => refreshes++,
    );

    c.schedule();
    c.cancel();
    await tick();

    expect(refreshes, 0);
  });
}
