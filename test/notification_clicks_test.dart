import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/logging.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/notify/desktop_notifier.dart';
import 'package:mergelio/state/desktop_notifier.dart';
import 'package:mergelio/state/notification_clicks.dart';
import 'package:mergelio/state/open_review.dart';
import 'package:mergelio/state/review.dart';
import 'package:mergelio/state/workspace.dart';

import 'support/fake_desktop_notifier.dart';

class _RecordingSink implements LogSink {
  final lines = <String>[];
  @override
  void write(String line) => lines.add(line);
}

class _Harness {
  final fake = FakeDesktopNotifier();
  int raised = 0;
  late final ProviderContainer c;
  late final int a;
  late final int b;

  _Harness({
    ({String base, String head})? result = (base: 'B', head: 'H'),
    bool raiseFails = false,
  }) {
    c = ProviderContainer(
      overrides: [
        desktopNotifierProvider.overrideWithValue(fake),
        windowRaiseProvider.overrideWithValue(() async {
          raised++;
          if (raiseFails) throw StateError('no window');
        }),
        forgeFetchPullRequestForReviewProvider.overrideWithValue(
          (repoPath, kind, number, targetBranch) async => result,
        ),
      ],
    );
    final ws = c.read(workspaceProvider.notifier);
    a = ws.openRepo('/repo/a').id;
    b = ws.openRepo('/repo/b').id;
    ws.setActive(a);
    c.read(notificationClickRouterProvider);
  }

  int? get active => c.read(workspaceProvider).activeTabId;
  ReviewTarget? get review => c.read(reviewTargetProvider);

  Future<void> click(NotificationTarget t) async {
    fake.click(t);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a pull request click selects the tab and opens its review', () async {
    final h = _Harness();
    addTearDown(h.c.dispose);
    await h.click(
      const NotificationTarget(
        repoPath: '/repo/b',
        kind: ForgeKind.github,
        prNumber: 7,
        targetBranch: 'main',
      ),
    );
    expect(h.raised, 1);
    expect(h.active, h.b);
    expect(h.review?.repoPath, '/repo/b');
    expect(h.review?.pullRequest?.number, 7);
    expect(h.review?.base, 'B');
    expect(h.review?.head, 'H');
  });

  test('a repo-only click selects the tab and leaves the review', () async {
    final h = _Harness();
    addTearDown(h.c.dispose);
    await h.click(const NotificationTarget(repoPath: '/repo/b'));
    expect(h.active, h.b);
    expect(h.review, isNull);
  });

  test('a click on a repo with no tab only raises the window', () async {
    final h = _Harness();
    addTearDown(h.c.dispose);
    await h.click(
      const NotificationTarget(
        repoPath: '/repo/gone',
        kind: ForgeKind.github,
        prNumber: 7,
        targetBranch: 'main',
      ),
    );
    expect(h.raised, 1);
    expect(h.active, h.a);
    expect(h.review, isNull);
  });

  test('a failed fetch still selects the tab but opens no review', () async {
    final h = _Harness(result: null);
    addTearDown(h.c.dispose);
    await h.click(
      const NotificationTarget(
        repoPath: '/repo/b',
        kind: ForgeKind.github,
        prNumber: 7,
        targetBranch: 'main',
      ),
    );
    expect(h.active, h.b);
    expect(h.review, isNull);
  });

  test('a click on a tab outside the shown group reveals it', () async {
    final h = _Harness();
    addTearDown(h.c.dispose);
    final ws = h.c.read(workspaceProvider.notifier);
    final g = ws.createGroup('front');
    ws.moveToGroup(h.a, g.id);
    ws.setActiveGroup(g.id);
    expect(h.active, h.a);

    await h.click(const NotificationTarget(repoPath: '/repo/b'));

    final state = h.c.read(workspaceProvider);
    expect(h.active, h.b);
    expect(state.hasRepo, isTrue);
    expect(state.visibleTabs.map((t) => t.id), contains(h.b));
  });

  test('a click on a tab in another group switches to that group', () async {
    final h = _Harness();
    addTearDown(h.c.dispose);
    final ws = h.c.read(workspaceProvider.notifier);
    final front = ws.createGroup('front');
    final back = ws.createGroup('back');
    ws.moveToGroup(h.a, front.id);
    ws.moveToGroup(h.b, back.id);
    ws.setActiveGroup(front.id);

    await h.click(const NotificationTarget(repoPath: '/repo/b'));

    final state = h.c.read(workspaceProvider);
    expect(h.active, h.b);
    expect(state.activeGroupId, back.id);
    expect(state.hasRepo, isTrue);
  });

  test('a click that fails is logged, not thrown', () async {
    final sink = _RecordingSink();
    final previous = appLog;
    appLog = AppLogger(sink: sink);
    addTearDown(() => appLog = previous);
    final h = _Harness(raiseFails: true);
    addTearDown(h.c.dispose);

    await h.click(const NotificationTarget(repoPath: '/repo/b'));

    expect(sink.lines.join('\n'), contains('notification click failed'));
    expect(h.active, h.a);
  });
}
