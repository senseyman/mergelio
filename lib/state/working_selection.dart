import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two lists of the Changes panel. A partially staged file sits in both,
/// so a selection names its side rather than just its paths.
enum WorkingSide { unstaged, staged }

/// Files picked in one side of the Changes panel, plus the anchor a
/// Shift-click extends from. Immutable: every gesture returns a new value.
///
/// Paths are not pruned when files leave the list — [within] intersects with
/// what is on screen at the moment of use, so a stale entry never acts.
class WorkingSelection {
  final WorkingSide? side;
  final Set<String> paths;
  final String? anchor;

  const WorkingSelection._({this.side, this.paths = const {}, this.anchor});

  static const none = WorkingSelection._();

  bool get isEmpty => paths.isEmpty;

  bool contains(WorkingSide s, String path) =>
      side == s && paths.contains(path);

  /// A plain click: only [path], anchored on it.
  WorkingSelection select(WorkingSide s, String path) =>
      WorkingSelection._(side: s, paths: {path}, anchor: path);

  /// Cmd/Ctrl-click: [path] in or out. A click in the other side starts over
  /// there, since one action cannot both stage and unstage.
  WorkingSelection toggle(WorkingSide s, String path) {
    if (side != s) return select(s, path);
    final next = {...paths};
    if (!next.remove(path)) next.add(path);
    if (next.isEmpty) return none;
    return WorkingSelection._(side: s, paths: next, anchor: path);
  }

  /// Shift-click: the run of [order] from the anchor to [path], replacing what
  /// was picked. With no usable anchor it is a plain pick of [path].
  WorkingSelection extend(WorkingSide s, String path, List<String> order) {
    final from = side == s && anchor != null ? order.indexOf(anchor!) : -1;
    final to = order.indexOf(path);
    if (from < 0 || to < 0) return select(s, path);
    final (lo, hi) = from <= to ? (from, to) : (to, from);
    return WorkingSelection._(
      side: s,
      paths: order.sublist(lo, hi + 1).toSet(),
      anchor: anchor,
    );
  }

  /// The picked paths of side [s] still present in [order], in its order.
  List<String> within(WorkingSide s, List<String> order) => side != s
      ? const []
      : [
          for (final p in order)
            if (paths.contains(p)) p,
        ];
}

/// The Changes panel's selection, per repository.
final workingSelectionProvider = StateProvider.family<WorkingSelection, String>(
  (_, _) => WorkingSelection.none,
);
