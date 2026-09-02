import '../../domain/git/models.dart';
import '../../l10n/gen/app_localizations.dart';

/// The toggleable graph meta columns, id → display label. Shared by the graph
/// header "Columns" menu and Preferences so both stay in sync. A function
/// rather than a constant map: the labels are localised, so they cannot be
/// resolved until there is a context to resolve them against.
Map<String, String> graphColumnLabels(AppLocalizations l) => {
  'branch': l.ccBranch,
  'author': l.cdAuthor,
  'date': l.cdDate,
  'sha': l.cdSha,
};

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _p2(int n) => n.toString().padLeft(2, '0');

/// `+02:00` / `-05:30` — how a UTC offset is spelled beside a time.
String _zoneLabel(Duration o) {
  final a = o.abs();
  return '${o.isNegative ? '-' : '+'}${_p2(a.inHours)}:${_p2(a.inMinutes % 60)}';
}

/// Formats [d] per [format]: 'medium' (Jul 2, 2026), 'iso' (2026-07-02) or
/// 'short' (07/02/26). With [withTime] a clock is appended, as HH:mm or, when
/// [clock] is '12h', as h:mm AM/PM.
///
/// [d] is an instant, not a wall clock. Given an [offset] it is rendered in
/// that zone and tagged with it — the time the commit was authored, where it
/// was authored. Without one it falls back to the viewer's local zone. Either
/// way the date and the clock agree, so a commit made near midnight does not
/// show one zone's day beside another zone's hour.
String formatCommitDate(
  DateTime d, {
  String format = 'medium',
  bool withTime = false,
  String clock = '24h',
  Duration? offset,
}) {
  final l = offset == null ? d.toLocal() : d.toUtc().add(offset);
  final date = switch (format) {
    'iso' => '${l.year}-${_p2(l.month)}-${_p2(l.day)}',
    'short' => '${_p2(l.month)}/${_p2(l.day)}/${_p2(l.year % 100)}',
    _ => '${_months[l.month - 1]} ${l.day}, ${l.year}',
  };
  if (!withTime) return date;
  final time = clock == '12h'
      ? '${l.hour % 12 == 0 ? 12 : l.hour % 12}:${_p2(l.minute)} '
            '${l.hour < 12 ? 'AM' : 'PM'}'
      : '${_p2(l.hour)}:${_p2(l.minute)}';
  return offset == null ? '$date $time' : '$date $time ${_zoneLabel(offset)}';
}

/// Branch refs that name a commit: all of its local branches, or — when it has
/// no local branch — its remote-tracking branches (kept with their `remote/`
/// prefix so the gutter tells a remote-only branch apart). A local ref
/// represents any remote at the same commit, so remotes are suppressed there to
/// avoid showing `main` and `origin/main` twice. Tags are excluded.
List<String> _ownRefs(Commit c) {
  final locals = <String>[];
  final remotes = <String>[];
  for (final r in c.refs) {
    if (r.kind == RefKind.local) {
      locals.add(r.name);
    } else if (r.kind == RefKind.remote) {
      remotes.add(r.name);
    }
  }
  return locals.isNotEmpty ? locals : remotes;
}

/// Branch column labels per commit sha. A commit is named by *all* of its own
/// branch refs (so several branches sitting on one commit are each shown), else
/// it inherits the single branch of its nearest first-parent descendant — so
/// shared history stays on the base branch instead of being claimed by a newer
/// branch that also contains it.
///
/// [commits] must be newest-first topological order (a child before its
/// parents), as produced by `git log --topo-order`.
Map<String, List<String>> deriveBranchLabels(List<Commit> commits) {
  final display = <String, List<String>>{};
  // The single primary label that flows down a first-parent segment.
  final segment = <String, String>{};
  for (final c in commits) {
    final own = _ownRefs(c);
    final List<String> labels;
    if (own.isNotEmpty) {
      // Own refs always win over a label a descendant propagated down.
      labels = own;
    } else {
      final inherited = segment[c.sha];
      if (inherited == null) continue;
      labels = [inherited];
    }
    display[c.sha] = labels;
    if (c.parents.isNotEmpty) {
      // Only the primary (first) ref propagates; the nearest descendant claims
      // the first parent and a later (older) path does not overwrite it.
      segment.putIfAbsent(c.parents.first, () => labels.first);
    }
  }
  return display;
}

/// One chip in a row's left branch column: a branch name, or the HEAD marker.
class BranchChip {
  final String name;
  final bool isHead;
  const BranchChip({required this.name, required this.isHead});

  @override
  bool operator ==(Object other) =>
      other is BranchChip && other.name == name && other.isHead == isHead;

  @override
  int get hashCode => Object.hash(name, isHead);

  @override
  String toString() => 'BranchChip($name, isHead: $isHead)';
}

/// Chips shown in the left branch column for [c]: the HEAD marker first (when
/// this commit is HEAD, including a detached HEAD), then its [branchLabels].
/// Branch labels only appear on the segment top ([showBranchLabel]); HEAD marks
/// its exact commit regardless.
List<BranchChip> branchColumnChips(
  Commit c,
  List<String> branchLabels, {
  required bool showBranchLabel,
}) {
  final chips = <BranchChip>[];
  if (c.refs.any((r) => r.kind == RefKind.head)) {
    chips.add(const BranchChip(name: 'HEAD', isHead: true));
  }
  if (showBranchLabel) {
    for (final name in branchLabels) {
      chips.add(BranchChip(name: name, isHead: false));
    }
  }
  return chips;
}
