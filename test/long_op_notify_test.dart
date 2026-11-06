// A fetch, pull, push or clone that ran long enough for the user to look away
// says so when it ends, through the notification gate.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/app_database.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/desktop_notifier.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/notification_gate.dart';
import 'package:mergelio/state/op_clock.dart';
import 'package:mergelio/state/operation_journal.dart';
import 'package:mergelio/state/recents.dart';
import 'package:mergelio/state/repo_actions.dart';
import 'package:mergelio/state/repo_bootstrap.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/window_focus.dart';

import 'support/fake_desktop_notifier.dart';

const _repo = '/work/widgets';

class _MemoryRecents implements RecentsRepository {
  @override
  AppDatabase get db => throw UnimplementedError();
  @override
  Future<List<RecentRepo>> load() async => const [];
  @override
  Future<void> save(List<RecentRepo> items) async {}
}

class _FakeGit implements GitService {
  _FakeGit(this.now);
  final DateTime Function() now;
  final List<List<String>> calls = [];

  /// How much of the test clock the next network command consumes.
  Duration take = Duration.zero;
  Duration? cloneTake;
  GitResult? pushResult;
  GitResult? cloneResult;
  void Function(GitCancel cancel)? onNetwork;
  void Function()? advance;

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args);
    final isNet = {'fetch', 'pull', 'push', 'clone'}.contains(args.first);
    if (!isNet) return const GitResult(0, '', '');
    advance?.call();
    if (cancel != null) onNetwork?.call(cancel);
    if (cancel?.isCancelled ?? false) {
      throw GitCancelledException('cancelled');
    }
    if (args.first == 'clone') {
      Directory(args.last).createSync(recursive: true);
      return cloneResult ?? const GitResult(0, '', '');
    }
    if (args.first == 'push' && pushResult != null) return pushResult!;
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  late DateTime clock;
  late _FakeGit git;
  late FakeDesktopNotifier fake;
  late ProviderContainer c;

  void setUpHarness({
    bool focused = false,
    bool longOps = true,
    bool brokenGate = false,
  }) {
    clock = DateTime(2026, 1, 1);
    git = _FakeGit(() => clock);
    fake = FakeDesktopNotifier();
    c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        recentsProvider.overrideWith(
          (ref) => RecentsController(_MemoryRecents(), const []),
        ),
        desktopNotifierProvider.overrideWithValue(fake),
        if (brokenGate)
          notificationGateProvider.overrideWith(
            (ref) => throw StateError('gate unavailable'),
          ),
        kvStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        opClockProvider.overrideWithValue(() => clock),
        windowFocusedProvider.overrideWith((ref) => focused),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            AppSettings(
              notificationsEnabled: true,
              notifyLongOps: longOps,
              notifyLongOpSeconds: 10,
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
  }

  /// Makes the next network command take [seconds] of test time.
  void takes(int seconds) =>
      git.advance = () => clock = clock.add(Duration(seconds: seconds));

  RepoActions actions() {
    final a = c.read(repoActionsProvider(_repo));
    return a;
  }

  setUp(setUpHarness);

  test('a push taking 11 s notifies once', () async {
    takes(11);
    await actions().push();
    await pumpEventQueue();

    expect(fake.shown, hasLength(1));
    final n = fake.shown.single;
    expect(n.title, 'widgets');
    expect(n.body, 'Push finished');
    expect(n.target.repoPath, _repo);
    expect(n.target.prNumber, isNull);
  });

  test('a notification failure leaves a successful push successful', () async {
    setUpHarness(brokenGate: true);
    takes(11);
    final pushed = await actions().push();
    await pumpEventQueue();

    expect(pushed, isTrue);
    final toasts = c.read(toastProvider);
    expect(toasts.map((t) => t.kind), isNot(contains(ToastKind.error)));
    expect(toasts.map((t) => t.kind), contains(ToastKind.success));
  });

  test('a push taking 9 s stays quiet', () async {
    takes(9);
    await actions().push();
    await pumpEventQueue();
    expect(fake.shown, isEmpty);
  });

  test('exactly the threshold notifies', () async {
    takes(10);
    await actions().push();
    await pumpEventQueue();
    expect(fake.shown, hasLength(1));
  });

  test('a long pull and a long fetch notify', () async {
    takes(11);
    await actions().pull();
    await actions().fetch();
    await pumpEventQueue();
    expect(fake.shown.map((n) => n.body), ['Pull finished', 'Fetch finished']);
  });

  test('a failed long push reports the first stderr line only', () async {
    git.pushResult = const GitResult(
      1,
      '',
      '! [rejected] main -> main\nhint: updates were rejected',
    );
    takes(11);
    await actions().push();
    await pumpEventQueue();

    expect(fake.shown, hasLength(1));
    expect(fake.shown.single.body, 'Push failed: ! [rejected] main -> main');
  });

  test('a cancelled long push never notifies', () async {
    takes(11);
    git.onNetwork = (cancel) => cancel.cancel();
    await actions().push();
    await pumpEventQueue();
    expect(fake.shown, isEmpty);
  });

  test('a silent fetch never notifies, however long', () async {
    takes(60);
    await actions().fetch(silent: true);
    await pumpEventQueue();
    expect(fake.shown, isEmpty);
  });

  test('a busy-lane skip never notifies', () async {
    takes(11);
    c.read(busyProvider.notifier).state = const BusyState('Other');
    await actions().push();
    await pumpEventQueue();
    expect(fake.shown, isEmpty);
  });

  test('a focused window never notifies', () async {
    setUpHarness(focused: true);
    takes(11);
    await actions().push();
    await pumpEventQueue();
    expect(fake.shown, isEmpty);
  });

  group('clone', () {
    late Directory work;
    setUp(() async {
      work = await Directory.systemTemp.createTemp('mergelio_ntf_clone_');
    });
    tearDown(() async {
      if (await work.exists()) await work.delete(recursive: true);
    });

    test('a long clone notifies with the cloned path', () async {
      takes(11);
      final path = await c
          .read(repoBootstrapProvider)
          .clone(url: 'git@host:acme/repo.git', parentDir: work.path);
      await pumpEventQueue();

      expect(fake.shown, hasLength(1));
      expect(fake.shown.single.title, 'repo');
      expect(fake.shown.single.body, 'Clone finished');
      expect(fake.shown.single.target.repoPath, path);
    });

    test('a notification failure still opens the cloned repo', () async {
      setUpHarness(brokenGate: true);
      takes(11);
      final path = await c
          .read(repoBootstrapProvider)
          .clone(url: 'git@host:acme/repo.git', parentDir: work.path);
      await pumpEventQueue();

      expect(path, '${work.path}/repo');
      expect(c.read(toastProvider), isEmpty);
    });

    test('a short clone stays quiet', () async {
      takes(3);
      await c
          .read(repoBootstrapProvider)
          .clone(url: 'git@host:acme/repo.git', parentDir: work.path);
      await pumpEventQueue();
      expect(fake.shown, isEmpty);
    });

    test('a failed long clone reports the error', () async {
      git.cloneResult = const GitResult(128, '', 'fatal: repository not found');
      takes(11);
      await c
          .read(repoBootstrapProvider)
          .clone(url: 'git@host:acme/repo.git', parentDir: work.path);
      await pumpEventQueue();

      expect(fake.shown, hasLength(1));
      expect(
        fake.shown.single.body,
        'Clone failed: fatal: repository not found',
      );
    });
  });
}
