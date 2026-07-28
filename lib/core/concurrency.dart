import 'dart:async';
import 'dart:collection';

/// Caps how many asynchronous tasks run at once, admitting waiters in arrival
/// order.
///
/// Used to bound git subprocesses: a GUI process on macOS is given 256 file
/// descriptors and each child consumes several, so a repository with hundreds
/// of branches can otherwise exhaust them and fail with "Too many open files".
class ConcurrencyGate {
  final int limit;

  final Queue<Completer<void>> _waiting = Queue();
  int _inFlight = 0;

  ConcurrencyGate(this.limit) : assert(limit > 0);

  /// How many tasks hold a slot right now.
  int get inFlight => _inFlight;

  /// Runs [task] once a slot is free. The slot is released whether the task
  /// completes or throws, so one failure cannot shrink the pool.
  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_inFlight < limit) {
      _inFlight++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _inFlight--;
    } else {
      // Hand the slot straight to the next waiter rather than dropping the
      // count and re-taking it, which would let a newcomer jump the queue.
      _waiting.removeFirst().complete();
    }
  }
}

/// Debounces a burst of triggers into one refresh, and holds that refresh back
/// while the previous one is still running.
///
/// The second part matters as much as the first: a repository read can easily
/// outlast the burst that scheduled it, and starting another read on top of the
/// ones already in flight makes every one of them slower.
class RefreshCoalescer {
  /// How long the triggers must stay quiet before the refresh runs.
  final Duration settle;

  /// Whether the previous refresh is still in progress.
  final bool Function() busy;

  final void Function() onRefresh;

  Timer? _timer;

  RefreshCoalescer({
    required this.settle,
    required this.busy,
    required this.onRefresh,
  });

  /// Notes that something changed. Restarts the settle window.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(settle, _fire);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _fire() {
    if (busy()) {
      // Try again once the in-flight refresh has had time to finish, instead
      // of queueing a second one behind it.
      _timer = Timer(settle, _fire);
      return;
    }
    _timer = null;
    onRefresh();
  }
}
