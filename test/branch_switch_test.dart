import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/workspace/branch_switch.dart';

class _FakeGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls.add(args);
    // 'status --porcelain' looks clean so the switch path stays linear.
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';

  @override
  Future<bool> isRepository(String path) async => true;
}

ProviderContainer _container(
  _FakeGit git,
  RepoData data, {
  bool confirm = false,
}) => ProviderContainer(
  overrides: [
    gitServiceProvider.overrideWithValue(git),
    settingsProvider.overrideWith(
      (ref) => SettingsController(
        InMemorySettingsRepository(),
        AppSettings(confirmDestructive: confirm),
      ),
    ),
    repoDataProvider('/r').overrideWith((ref) async => data),
  ],
);

void main() {
  group('remoteSwitchIsDestructive', () {
    const rb = RemoteBranch(
      remote: 'origin',
      branch: 'main',
      hasLocal: true,
      tip: 'bbb',
    );

    test('false when there is no local branch', () {
      expect(
        remoteSwitchIsDestructive(
          const RemoteBranch(remote: 'origin', branch: 'main', tip: 'bbb'),
          const [],
        ),
        isFalse,
      );
    });

    test('false when the local tip equals the remote tip', () {
      expect(
        remoteSwitchIsDestructive(rb, const [Branch(name: 'main', tip: 'bbb')]),
        isFalse,
      );
    });

    test('true when the local tip differs from the remote tip', () {
      expect(
        remoteSwitchIsDestructive(rb, const [Branch(name: 'main', tip: 'aaa')]),
        isTrue,
      );
    });
  });

  group('resolveBranchChip', () {
    const remotes = [
      RemoteBranch(remote: 'origin', branch: 'main', hasLocal: true, tip: 'x'),
    ];

    test('a remote label resolves to the remote branch', () {
      final r = resolveBranchChip('origin/main', remotes);
      expect(r.remote, remotes.first);
      expect(r.local, isNull);
    });

    test('a non-remote label resolves to a local target', () {
      final r = resolveBranchChip('main', remotes);
      expect(r.local, 'main');
      expect(r.remote, isNull);
    });
  });

  group('activateBranch', () {
    Future<List<List<String>>> run(
      WidgetTester tester,
      RepoData data, {
      String? local,
      RemoteBranch? remote,
      bool confirm = false,
      bool tapConfirm = false,
      bool tapCancel = false,
    }) async {
      final git = _FakeGit();
      final c = _container(git, data, confirm: confirm);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppTokens.dark()]),
            home: Consumer(
              builder: (ctx, ref, _) => TextButton(
                onPressed: () => activateBranch(
                  ref,
                  ctx,
                  '/r',
                  localBranch: local,
                  remote: remote,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      if (tapConfirm) {
        await tester.pump();
        await tester.tap(find.text('Reset & switch'));
      }
      if (tapCancel) {
        await tester.pump();
        await tester.tap(find.text('Cancel'));
      }
      await tester.pumpAndSettle();
      return git.calls;
    }

    testWidgets('diverged remote, confirm on, cancelled → no reset', (
      tester,
    ) async {
      final calls = await run(
        tester,
        const RepoData(
          branches: [Branch(name: 'main', tip: 'aaa')],
        ),
        remote: const RemoteBranch(
          remote: 'origin',
          branch: 'main',
          hasLocal: true,
          tip: 'bbb',
        ),
        confirm: true,
        tapCancel: true,
      );
      expect(calls.any((a) => a.contains('--hard')), isFalse);
    });

    testWidgets('local target → checkout', (tester) async {
      final calls = await run(tester, const RepoData(), local: 'dev');
      expect(
        calls.any((a) => a.first == 'checkout' && a.contains('dev')),
        isTrue,
      );
    });

    testWidgets('remote with no local → tracking checkout', (tester) async {
      final calls = await run(
        tester,
        const RepoData(),
        remote: const RemoteBranch(remote: 'origin', branch: 'feat', tip: 'x'),
      );
      expect(calls.any((a) => a.contains('--track')), isTrue);
    });

    testWidgets('remote with equal local tip → plain checkout, no reset', (
      tester,
    ) async {
      final calls = await run(
        tester,
        const RepoData(
          branches: [Branch(name: 'main', tip: 'x')],
        ),
        remote: const RemoteBranch(
          remote: 'origin',
          branch: 'main',
          hasLocal: true,
          tip: 'x',
        ),
      );
      expect(
        calls.any((a) => a.first == 'checkout' && a.contains('main')),
        isTrue,
      );
      expect(calls.any((a) => a.contains('--hard')), isFalse);
    });

    testWidgets('diverged remote, confirm off → resets to remote', (
      tester,
    ) async {
      final calls = await run(
        tester,
        const RepoData(
          branches: [Branch(name: 'main', tip: 'aaa')],
        ),
        remote: const RemoteBranch(
          remote: 'origin',
          branch: 'main',
          hasLocal: true,
          tip: 'bbb',
        ),
        confirm: false,
      );
      expect(
        calls.any((a) => a.contains('--hard') && a.contains('origin/main')),
        isTrue,
      );
    });

    testWidgets('diverged remote, confirm on → dialog, confirm resets', (
      tester,
    ) async {
      final calls = await run(
        tester,
        const RepoData(
          branches: [Branch(name: 'main', tip: 'aaa')],
        ),
        remote: const RemoteBranch(
          remote: 'origin',
          branch: 'main',
          hasLocal: true,
          tip: 'bbb',
        ),
        confirm: true,
        tapConfirm: true,
      );
      expect(calls.any((a) => a.contains('--hard')), isTrue);
    });
  });
}
