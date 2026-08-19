import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Toast severity → left border colour in the UI.
enum ToastKind { info, success, warning, error }

class ToastAction {
  final String label;
  final void Function() onPressed;
  const ToastAction(this.label, this.onPressed);
}

class Toast {
  final int id;
  final String title;
  final String? description;
  final ToastKind kind;
  final ToastAction? action;
  const Toast({
    required this.id,
    required this.title,
    this.description,
    this.kind = ToastKind.info,
    this.action,
  });
}

class ToastController extends StateNotifier<List<Toast>> {
  ToastController() : super(const []);

  int _nextId = 1;
  final _timers = <int, Timer>{};

  void show(
    String title, {
    String? description,
    ToastKind kind = ToastKind.info,
    ToastAction? action,
  }) {
    final toast = Toast(
      id: _nextId++,
      title: title,
      description: description,
      kind: kind,
      action: action,
    );
    state = [...state, toast];
    // Actionable toasts stay longer so the user can react.
    _timers[toast.id] = Timer(
      Duration(milliseconds: action != null ? 6000 : 3400),
      () => dismiss(toast.id),
    );
  }

  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    // Check mounted before mutating state: a dispose() already cleared _timers
    // and calling state = after dispose throws.
    if (!mounted) return;
    state = state.where((t) => t.id != id).toList();
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

final toastProvider = StateNotifierProvider<ToastController, List<Toast>>(
  (ref) => ToastController(),
);

/// Long-running operation indicator (drives the top progress bar).
class BusyState {
  final String label;
  final double? progress; // 0..1, null = indeterminate

  /// Whether the running operation rewrites files in the working tree. A save
  /// from an editor has to wait for one that does; it has no reason to wait
  /// for a fetch, which only moves objects and refs.
  final bool touchesWorkingTree;

  /// Kills the git process behind the operation, for one that can stall on an
  /// unreachable remote. Null when there is nothing to abandon.
  final void Function()? onCancel;

  const BusyState(this.label, {this.progress, this.onCancel})
    : touchesWorkingTree = true;

  /// An operation that talks to a remote and leaves the working tree alone.
  const BusyState.network(this.label, {this.progress, this.onCancel})
    : touchesWorkingTree = false;
}

/// The operation holding the repository: anything that can rewrite the working
/// tree or move a local ref. One at a time, so nothing races on git's index
/// and ref locks.
final busyProvider = StateProvider<BusyState?>((ref) => null);

/// The running fetch, tracked apart from [busyProvider]. A fetch moves objects
/// and remote-tracking refs and can run for minutes; making a commit, a branch
/// create or a push wait that out — for an auto-fetch tick nobody asked for —
/// is the whole reason it gets a lane of its own.
final fetchBusyProvider = StateProvider<BusyState?>((ref) => null);
