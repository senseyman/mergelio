import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/issue_view.dart';
import 'package:mergelio/state/review.dart';
import 'package:mergelio/ui/workspace/workspace_view.dart';

const _review = ReviewTarget(repoPath: '/repo', base: 'main', head: 'feature');
const IssueTarget _issue = (repoPath: '/repo', number: 3);

Future<ProviderContainer> _pumpGuard(WidgetTester tester) async {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const LastOpenedWins(child: SizedBox()),
    ),
  );
  return c;
}

void main() {
  group('centerPaneFor', () {
    test('nothing open shows the graph', () {
      expect(
        centerPaneFor(path: '/repo', review: null, issue: null),
        CenterPane.graph,
      );
    });

    test('an issue for this repository replaces the graph', () {
      expect(
        centerPaneFor(path: '/repo', review: null, issue: _issue),
        CenterPane.issue,
      );
    });

    test("an issue from another tab's repository is not shown", () {
      expect(
        centerPaneFor(path: '/other', review: null, issue: _issue),
        CenterPane.graph,
      );
    });

    test('another repository still shows its own review', () {
      const other = ReviewTarget(repoPath: '/other', base: 'a', head: 'b');
      expect(
        centerPaneFor(path: '/other', review: other, issue: _issue),
        CenterPane.review,
      );
    });

    test('a review for this repository shows the review', () {
      expect(
        centerPaneFor(path: '/repo', review: _review, issue: null),
        CenterPane.review,
      );
    });
  });

  testWidgets('opening a review puts an open issue away', (tester) async {
    final c = await _pumpGuard(tester);
    c.read(issueTargetProvider.notifier).state = _issue;
    await tester.pump();

    c.read(reviewTargetProvider.notifier).state = _review;
    await tester.pump();

    expect(c.read(issueTargetProvider), isNull);
    expect(c.read(reviewTargetProvider), _review);
  });

  testWidgets('opening an issue puts an open review away', (tester) async {
    final c = await _pumpGuard(tester);
    c.read(reviewTargetProvider.notifier).state = _review;
    await tester.pump();

    c.read(issueTargetProvider.notifier).state = _issue;
    await tester.pump();

    expect(c.read(reviewTargetProvider), isNull);
    expect(c.read(issueTargetProvider), _issue);
  });

  testWidgets('closing one leaves the other closed', (tester) async {
    final c = await _pumpGuard(tester);
    c.read(issueTargetProvider.notifier).state = _issue;
    await tester.pump();

    c.read(issueTargetProvider.notifier).state = null;
    await tester.pump();

    expect(c.read(reviewTargetProvider), isNull);
    expect(c.read(issueTargetProvider), isNull);
  });
}
