import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/search.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/ui/graph/graph_derived.dart';

/// Guards the 50k-commit NFR targets (open ≤ 3s, search ≤ 1s) at the domain
/// layer: lane layout, graph derivations and search must each stay well inside
/// their budget on a synthetic 50 000-commit history with periodic branching.
void main() {
  List<Commit> synthetic(int n) {
    final commits = <Commit>[];
    for (var i = 0; i < n; i++) {
      // Every 50th commit is a merge of a short-lived side branch.
      final isMerge = i % 50 == 0 && i + 60 < n;
      commits.add(
        Commit(
          sha: i.toRadixString(16).padLeft(40, '0'),
          message: 'commit $i ${i % 7 == 0 ? "feature" : "fix"} work',
          author: 'Author ${i % 9}',
          authorEmail: 'a${i % 9}@example.com',
          date: DateTime(2026).add(Duration(minutes: i)),
          parents: [
            if (i + 1 < n) (i + 1).toRadixString(16).padLeft(40, '0'),
            if (isMerge) (i + 55).toRadixString(16).padLeft(40, '0'),
          ],
        ),
      );
    }
    return commits;
  }

  test('lane layout handles 50k commits within budget', () {
    final commits = synthetic(50000);
    final sw = Stopwatch()..start();
    final laid = assignLanes(commits);
    sw.stop();
    expect(laid.length, 50000);
    // NFR: repo open ≤ 3s total; layout alone must be a fraction of that.
    expect(
      sw.elapsedMilliseconds,
      lessThan(2000),
      reason: 'lane layout took ${sw.elapsedMilliseconds}ms',
    );
  });

  test('graph derivations on 50k commits stay fast', () {
    final laid = assignLanes(synthetic(50000));
    final sw = Stopwatch()..start();
    final derived = computeGraphDerived(RepoData(commits: laid));
    sw.stop();
    expect(derived.rowIndex.length, 50000);
    expect(
      sw.elapsedMilliseconds,
      lessThan(1000),
      reason: 'derivations took ${sw.elapsedMilliseconds}ms',
    );
  });

  test('search across 50k commits meets the ≤1s target', () async {
    final commits = synthetic(50000);
    final sw = Stopwatch()..start();
    final matches = await computeMatchShas(
      commits,
      const CommitQuery(text: 'feature'),
    );
    sw.stop();
    expect(matches, isNotEmpty);
    expect(
      sw.elapsedMilliseconds,
      lessThan(1000),
      reason: 'search took ${sw.elapsedMilliseconds}ms',
    );
  });
}
