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
///
/// [held] adds a softer wait: the refresh also stays back while the work that
/// will ask for it again is still going — one operation of a gesture still
/// running when the previous one's settle window ran out. That wait gives way
/// after [maxHold], so a long operation cannot keep the view stale for its
/// whole run.
class RefreshCoalescer {
  /// How long the triggers must stay quiet before the refresh runs.
  final Duration settle;

  /// Whether the previous refresh is still in progress.
  final bool Function() busy;

  /// Whether work that will schedule again is still running.
  final bool Function()? held;

  /// The longest [held] may keep a due refresh back.
  final Duration maxHold;

  final void Function() onRefresh;

  Timer? _timer;

  /// When the refresh now waiting on [held] first came due; null when it is
  /// not waiting on it.
  DateTime? _heldSince;

  RefreshCoalescer({
    required this.settle,
    required this.busy,
    required this.onRefresh,
    this.held,
    this.maxHold = const Duration(seconds: 2),
  });

  /// Notes that something changed. Restarts the settle window.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(settle, _fire);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _heldSince = null;
  }

  void _fire() {
    if (busy()) {
      // Try again once the in-flight refresh has had time to finish, instead
      // of queueing a second one behind it.
      _timer = Timer(settle, _fire);
      return;
    }
    if (held?.call() ?? false) {
      final since = _heldSince ??= DateTime.now();
      if (DateTime.now().difference(since) < maxHold) {
        _timer = Timer(settle, _fire);
        return;
      }
    }
    _timer = null;
    _heldSince = null;
    onRefresh();
  }
}
