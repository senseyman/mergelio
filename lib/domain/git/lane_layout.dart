import 'models.dart';

/// Assigns graph layout to [commits] (newest-first, topological order as read
/// from `git log --topo-order`) and returns copies with [Commit.lane],
/// [Commit.ci], [Commit.through], [Commit.mergeFrom] and [Commit.branchStart]
/// populated for the render stage.
///
/// Model (walking newest→oldest, so a parent is always processed *after* its
/// children): each lane tracks the sha it expects next going downward. A commit
/// takes the leftmost lane expecting it (or a fresh lane if it is a tip). Its
/// first parent continues on that lane unless the parent is already tracked on
/// another lane — then this lane ends here ([branchStart]) and the branch joins
/// the older one. Extra parents are merges; the second parent's lane is
/// recorded as [mergeFrom]. A lane is drawn straight through a row only when it
/// is occupied both entering and leaving that row — that intersection is
/// [through].
List<Commit> assignLanes(List<Commit> commits) {
  final lanes = <String?>[]; // sha each lane expects next (null = free)
  final laneCi = <int>[]; // colour index per lane
  var nextCi = 0;
  final out = <Commit>[];

  int allocLane() {
    for (var i = 0; i < lanes.length; i++) {
      if (lanes[i] == null) return i;
    }
    lanes.add(null);
    laneCi.add(0);
    return lanes.length - 1;
  }

  Set<int> occupied() {
    final s = <int>{};
    for (var i = 0; i < lanes.length; i++) {
      if (lanes[i] != null) s.add(i);
    }
    return s;
  }

  for (final c in commits) {
    final before = occupied();

    // Lanes expecting this commit; the leftmost becomes its lane, the rest
    // (children merging back into it) are freed.
    final expecting = <int>[];
    for (var i = 0; i < lanes.length; i++) {
      if (lanes[i] == c.sha) expecting.add(i);
    }

    final int lane;
    final int ci;
    if (expecting.isEmpty) {
      lane = allocLane();
      ci = nextCi++ % 8;
      laneCi[lane] = ci;
    } else {
      lane = expecting.first;
      ci = laneCi[lane];
      for (final e in expecting.skip(1)) {
        lanes[e] = null;
      }
    }

    var branchStart = false;
    int? branchInto;
    int? mergeFrom;
    if (c.parents.isEmpty) {
      lanes[lane] = null; // root commit: lane ends here
    } else {
      final p0 = c.parents.first;
      var existing = -1;
      for (var i = 0; i < lanes.length; i++) {
        if (i != lane && lanes[i] == p0) {
          existing = i;
          break;
        }
      }
      if (existing >= 0) {
        lanes[lane] = null; // parent already tracked → this branch joins it
        branchStart = true;
        branchInto = existing;
      } else {
        lanes[lane] = p0;
      }
      for (var k = 1; k < c.parents.length; k++) {
        final pk = c.parents[k];
        var slot = -1;
        for (var i = 0; i < lanes.length; i++) {
          if (lanes[i] == pk) {
            slot = i;
            break;
          }
        }
        if (slot < 0) {
          slot = allocLane();
          lanes[slot] = pk;
          laneCi[slot] = nextCi++ % 8;
        }
        if (k == 1) mergeFrom = slot;
      }
    }

    final through = before.intersection(occupied()).toList()..sort();
    out.add(
      c.copyWith(
        lane: lane,
        ci: ci,
        through: through,
        mergeFrom: mergeFrom,
        branchStart: branchStart,
        branchInto: branchInto,
        tip: expecting.isEmpty,
      ),
    );
  }
  return out;
}

/// Colours each branch by the lane colour of the commit it points at, so the
/// sidebar dot matches the graph. Expects [commits] to have been through
/// [assignLanes]. A branch whose tip is not among [commits] keeps its existing
/// [Branch.ci].
List<Branch> assignBranchColors(List<Branch> branches, List<Commit> commits) {
  final ciByRef = <String, int>{};
  for (final c in commits) {
    for (final r in c.refs) {
      if (r.kind == RefKind.local) ciByRef[r.name] = c.ci;
    }
  }
  return [
    for (final b in branches)
      ciByRef.containsKey(b.name) ? b.copyWith(ci: ciByRef[b.name]!) : b,
  ];
}
