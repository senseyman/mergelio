import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../domain/forge/forge.dart';
import '../domain/forge/forge_error.dart';
import '../domain/forge/forge_host.dart';
import '../domain/forge/forge_server.dart';
import '../domain/forge/models.dart';
import 'auto_fetch.dart' show autoFetchDelay;
import 'forge.dart';
import 'forge_notify_diff.dart';
import 'forge_refresh.dart';
import 'l10n.dart';
import 'notification_gate.dart';
import 'notification_prefs.dart';
import 'repo_data.dart';
import 'settings_controller.dart';
import 'window_focus.dart';
import 'workspace.dart';

/// How many open requests one read asks for. A single page on both forges,
/// and enough that a request dropping out of it almost always means it was
/// merged or closed rather than pushed off the end.
const kNotifyPrListLimit = 100;

/// Below this share of a host's request budget, the watcher stops reading
/// that host until the budget resets, leaving the rest for the user.
const kBudgetPauseFraction = 0.2;

/// The remote whose URL names the repo's forge project.
const kForgeRemote = 'origin';

/// Whether the watcher has anything to do for the repo at the given path:
/// its CI or pull-request notifications are on, and it sits on a forge with
/// a token on file. The forge lookup (which reads the repo's remote) only
/// happens once a notification wants it, so a user with notifications off
/// pays nothing.
final forgeNotifyEligibleProvider = Provider.family<bool, String>((ref, path) {
  final ci = ref.watch(notifyEnabledProvider((path, NotifyEvent.ci)));
  final prs = ref.watch(
    notifyEnabledProvider((path, NotifyEvent.pullRequests)),
  );
  if (!ci && !prs) return false;
  return ref.watch(forgeRefreshEligibleProvider(path)).valueOrNull ?? false;
});

/// Whether any open tab is [forgeNotifyEligibleProvider]-eligible, which is
/// what arming the watcher's timer depends on.
final forgeNotifyActiveProvider = Provider<bool>((ref) {
  final paths = ref.watch(
    workspaceProvider.select((w) => w.tabs.map((t) => t.path).join('\u0000')),
  );
  if (paths.isEmpty) return false;
  var any = false;
  for (final path in paths.split('\u0000').toSet()) {
    // Watch every path, not just up to the first hit, so a change on any of
    // them is noticed.
    if (ref.watch(forgeNotifyEligibleProvider(path))) any = true;
  }
  return any;
});

/// Watches the forge for CI results and pull-request changes on open repos
/// while nobody is looking at the window, and reports them as desktop
/// notifications.
///
/// The timer runs only while the window is unfocused and some open tab has
/// CI or pull-request notifications on; focus coming back cancels it, and
/// the first tick after losing focus waits a full interval. Losing focus
/// reads at once only the repos with nothing seen yet, recording them
/// silently so that first tick already reports what changed after the user
/// looked away. What each repo looked like is kept across short focus
/// changes, so the next unfocused stretch reports only what changed since.
/// A failed read backs the interval off the same way auto-fetch does, and
/// never surfaces as a toast or notification.
class ForgeNotifyWatcher {
  final Ref _ref;
  final DateTime Function() _now;

  final Map<String, ForgeSnapshot> _snapshots = {};
  // Hosts whose budget ran low, and when they may be read again.
  final Map<ForgeServer, DateTime> _pausedUntil = {};
  // Repos whose CI was read on their last successful tick. A repo missing
  // here had CI notifications off, so results that finished meanwhile are
  // old news when they come back on.
  final Set<String> _ciWatched = {};
  // Bumped whenever a repo's snapshot is dropped, so a read that was already
  // under way when it stopped being watched does not put the old view back.
  final Map<String, int> _epochs = {};
  // Per open repo: its eligibility and its CI setting, watched so a repo that
  // stops being watched loses its snapshot at once, not on a later tick that
  // may never come.
  final Map<String, List<ProviderSubscription<bool>>> _tracked = {};
  // When a seed on blur last tried each repo, so one whose read keeps failing
  // costs a read per interval at most, not one per switch away.
  final Map<String, DateTime> _seedTriedAt = {};
  // When the window last gained focus, or null while it is unfocused.
  DateTime? _focusedSince;

  Timer? _timer;
  Duration? _interval;
  Duration _base = kMinForgeRefreshDelay;
  int _failures = 0;
  bool _disposed = false;
  // The last pass queued, running or waiting its turn; passes never overlap.
  Future<void>? _inFlight;
  // The tick queued or running, which another tick joins instead of adding
  // a second one.
  Future<void>? _tickRun;

  ForgeNotifyWatcher(this._ref, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _ref.listen<int>(
      settingsProvider.select((s) => s.forgeRefreshIntervalSeconds),
      (_, seconds) {
        final wanted = Duration(seconds: seconds);
        _base = wanted < kMinForgeRefreshDelay ? kMinForgeRefreshDelay : wanted;
        _failures = 0;
        _arm();
      },
      fireImmediately: true,
    );
    _ref.listen<bool>(
      windowFocusedProvider,
      (was, focused) => _onFocus(was, focused),
      fireImmediately: true,
    );
    _ref.listen<String>(
      workspaceProvider.select((w) => w.tabs.map((t) => t.path).join('\u0000')),
      (_, joined) => _trackTabs(joined),
      fireImmediately: true,
    );
    _ref.listen<bool>(
      forgeNotifyActiveProvider,
      (_, _) => _arm(),
      fireImmediately: true,
    );
    _ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
      for (final subs in _tracked.values) {
        for (final sub in subs) {
          sub.close();
        }
      }
      _tracked.clear();
    });
  }

  /// Someone at the window for longer than one interval has had the panel in
  /// front of them; whatever changed meanwhile is old news, so the repos are
  /// looked at afresh the moment focus goes instead of reporting it. A glance
  /// shorter than that keeps what was seen before it.
  void _onFocus(bool? was, bool focused) {
    if (focused) {
      _focusedSince ??= _now();
    } else {
      final since = _focusedSince;
      _focusedSince = null;
      if (since != null && _now().difference(since) > _base) {
        for (final path in _snapshots.keys.toList()) {
          _drop(path);
        }
      }
    }
    _arm();
    // Only a real loss of focus: the watcher starting up while the window
    // already lacks it has no "before" to have missed. An armed timer means
    // the window is unfocused and some repo is watched.
    if (was == true && !focused && _timer != null) unawaited(_seedMissing());
  }

  void _trackTabs(String joined) {
    final paths = joined.isEmpty ? <String>{} : joined.split('\u0000').toSet();
    for (final path in _tracked.keys.toList()) {
      if (paths.contains(path)) continue;
      for (final sub in _tracked.remove(path)!) {
        sub.close();
      }
      _drop(path);
    }
    for (final path in paths) {
      if (_tracked.containsKey(path)) continue;
      _tracked[path] = [
        _ref.listen<bool>(forgeNotifyEligibleProvider(path), (_, eligible) {
          if (!eligible) _drop(path);
        }),
        _ref.listen<bool>(notifyEnabledProvider((path, NotifyEvent.ci)), (
          _,
          ci,
        ) {
          if (!ci) _ciWatched.remove(path);
        }),
      ];
    }
  }

  /// Forgets what the repo at [path] looked like, so the next read of it
  /// seeds silently.
  void _drop(String path) {
    _snapshots.remove(path);
    _ciWatched.remove(path);
    _seedTriedAt.remove(path);
    _epochs[path] = (_epochs[path] ?? 0) + 1;
  }

  /// The gap before the next tick, or null while nothing is scheduled.
  Duration? get scheduledInterval => _timer == null ? null : _interval;

  /// What each watched repo looked like at its last successful read.
  @visibleForTesting
  Map<String, ForgeSnapshot> get snapshots => Map.unmodifiable(_snapshots);

  void _arm() {
    _timer?.cancel();
    _timer = null;
    _interval = null;
    if (_disposed) return;
    if (_ref.read(windowFocusedProvider)) return;
    if (!_ref.read(forgeNotifyActiveProvider)) return;
    _interval = autoFetchDelay(_base, _failures);
    _timer = Timer(_interval!, () => unawaited(tick()));
  }

  /// One pass over every eligible repo, then the next timer. Never throws.
  Future<void> tick() {
    // A tick already queued covers this one; two at once would report the
    // same change twice. A seed running meanwhile is waited for, since it
    // reports nothing.
    return _tickRun ??= _serial(() => _tick())
        .whenComplete(() => _tickRun = null);
  }

  /// Reads, silently, every eligible repo that has no snapshot yet, so the
  /// first tick after it diffs against what things looked like when the
  /// user looked away rather than seeding then. Runs after any pass already
  /// under way, never alongside it. Leaves the backoff and the timer alone:
  /// a repo it fails to read simply gets seeded by the next tick instead,
  /// and a tick the timer fires meanwhile waits for it and rearms itself.
  Future<void> _seedMissing() => _serial(() => _tick(seedOnly: true));

  /// Runs [pass] once the pass already in flight, if any, has finished.
  Future<void> _serial(Future<void> Function() pass) {
    final before = _inFlight;
    late final Future<void> run;
    run = (before == null ? pass() : before.then((_) => pass())).whenComplete(
      () {
        if (identical(_inFlight, run)) _inFlight = null;
      },
    );
    return _inFlight = run;
  }

  Future<void> _tick({bool seedOnly = false}) async {
    if (_disposed) return;
    try {
      // Someone is looking at the window: the panel shows them the same
      // thing, and nothing would be shown anyway.
      if (_ref.read(windowFocusedProvider)) return;
      var paths = await _eligiblePaths();
      if (_disposed) return;
      // The listeners drop a repo the moment it stops being watched; this
      // catches one that fell out of the set some other way.
      for (final path in _snapshots.keys.toList()) {
        if (!paths.contains(path)) _drop(path);
      }
      if (seedOnly) {
        final now = _now();
        bool triedLately(String path) {
          final at = _seedTriedAt[path];
          return at != null && now.difference(at) < _base;
        }

        paths = {
          for (final path in paths)
            if (!_snapshots.containsKey(path) && !triedLately(path)) path,
        };
        for (final path in paths) {
          _seedTriedAt[path] = now;
        }
      }

      final byServer = <ForgeServer, List<(String, ForgeHost)>>{};
      for (final path in paths) {
        final ForgeHost? host;
        try {
          host = await _ref.read(forgeHostProvider(path).future);
        } on Object catch (e) {
          // One repo whose remote cannot be read must not cost the others
          // their tick.
          debugPrint('forge-notify host lookup failed for $path: $e');
          continue;
        }
        if (host == null) continue;
        (byServer[host.server] ??= []).add((path, host));
      }

      var anyRead = false, anyFailed = false;
      for (final MapEntry(key: server, value: repos) in byServer.entries) {
        final bool mayRead;
        try {
          mayRead = await _mayRead(server, repos.first.$1);
        } on Object catch (e) {
          // Without a budget reading there is no telling whether this host
          // can afford a read; skip it alone, not every host after it.
          debugPrint('forge-notify budget read failed for $server: $e');
          continue;
        }
        if (!mayRead) continue;
        for (final (path, host) in repos) {
          if (_disposed) return;
          final read = await _watchRepo(path, host.kind);
          if (read == _Read.skipped) continue;
          anyRead = true;
          if (read == _Read.ok) continue;
          anyFailed = true;
          // The host refused, not this repo: its other repos would only be
          // refused the same way.
          if (read == _Read.rateLimited) break;
        }
      }
      if (seedOnly) return;
      if (anyFailed) {
        _failures++;
      } else if (anyRead) {
        _failures = 0;
      }
    } on Object catch (e) {
      debugPrint('forge-notify tick failed: $e');
      if (!seedOnly) _failures++;
    } finally {
      // A seed leaves the timer armed on blur where it is.
      if (!seedOnly) _arm();
    }
  }

  /// Open tab paths, once each, whose CI or pull-request notifications are
  /// on and that have a forge account to read with.
  Future<Set<String>> _eligiblePaths() async {
    // With every notification off there is nothing to look up, not even a
    // repo's stored overrides.
    if (!_ref.read(settingsProvider).notificationsEnabled) return {};
    final tabs = {for (final t in _ref.read(workspaceProvider).tabs) t.path};
    final out = <String>{};
    for (final path in tabs) {
      // A repo's stored overrides load asynchronously; an override set to
      // off must not be missed just after the repo opens.
      await _ref.read(repoNotifyPrefsProvider(path).notifier).loaded;
      final wanted =
          _ref.read(notifyEnabledProvider((path, NotifyEvent.ci))) ||
          _ref.read(notifyEnabledProvider((path, NotifyEvent.pullRequests)));
      if (!wanted) continue;
      try {
        if (await _ref.read(forgeRefreshEligibleProvider(path).future)) {
          out.add(path);
        }
      } on Object catch (e) {
        debugPrint('forge-notify eligibility failed for $path: $e');
      }
    }
    return out;
  }

  /// Whether [server]'s budget allows reading it this tick. A budget below
  /// [kBudgetPauseFraction] pauses the host until the forge says it resets,
  /// or for one interval when it does not say; the first tick after a pause
  /// reads without asking again, since the window it measured is over.
  Future<bool> _mayRead(ForgeServer server, String path) async {
    final now = _now();
    final until = _pausedUntil[server];
    if (until != null) {
      // A second's slack, so a pause of one interval is not stretched to two
      // by a timer that fires a hair early.
      if (now.add(const Duration(seconds: 1)).isBefore(until)) return false;
      _pausedUntil.remove(server);
      return true;
    }
    // The budget provider caches its answer; a stale number would hide a
    // budget that has since run low.
    _ref.invalidate(forgeRateLimitProvider(path));
    final budget = await _ref.read(forgeRateLimitProvider(path).future);
    if (budget == null || budget.limit <= 0) return true;
    if (budget.remaining >= budget.limit * kBudgetPauseFraction) return true;
    _pausedUntil[server] = budget.resetAt ?? now.add(_base);
    return false;
  }

  /// Reads one repo and reports what changed.
  Future<_Read> _watchRepo(String path, ForgeKind kind) async {
    try {
      final forge = await _ref.read(forgeProvider(path).future);
      if (forge == null) return _Read.skipped;
      final prs = await forge.pullRequests(limit: kNotifyPrListLimit);
      final openPrs = {for (final pr in prs) pr.number: pr};
      final labels = await _shaLabels(path, openPrs);
      var prev = _snapshots[path];
      final epoch = _epochs[path];
      // CI costs a request per commit; a repo that does not want CI
      // notifications spends none of the budget on it.
      final wantCi = _ref.read(notifyEnabledProvider((path, NotifyEvent.ci)));
      final ciBySha = wantCi
          ? await _readCi(forge, labels.keys, prev)
          : <String, ChecksOverall>{};
      if (wantCi && prev != null && !_ciWatched.contains(path)) {
        // CI notifications just came back on: whatever already finished is
        // recorded, not reported, the same as a first look at the repo.
        prev = ForgeSnapshot(
          openPrs: prev.openPrs,
          ciBySha: prev.ciBySha,
          notifiedCi: {
            ...prev.notifiedCi,
            for (final e in ciBySha.entries)
              if (_isFinal(e.value)) '${e.key}:${e.value.name}',
          },
          maxPrNumber: prev.maxPrNumber,
        );
      }

      final diff = diffForgeSnapshots(
        prev: prev ?? const ForgeSnapshot.empty(),
        openPrs: openPrs,
        ciBySha: ciBySha,
        shaLabels: labels,
        seed: prev == null,
      );
      // Stopped being watched while this read was under way: what it saw
      // belongs to a view that was just thrown away.
      if (_epochs[path] != epoch) return _Read.ok;
      // Store before notifying: a notification that fails must not leave the
      // change to be reported again on the next tick.
      _snapshots[path] = ForgeSnapshot(
        openPrs: openPrs,
        ciBySha: ciBySha,
        notifiedCi: diff.notifiedCi,
        maxPrNumber: diff.maxPrNumber,
      );
      if (wantCi) {
        _ciWatched.add(path);
      } else {
        _ciWatched.remove(path);
      }
      await _report(path, kind, forge, diff.events);
      return _Read.ok;
    } on ForgeRateLimited catch (e) {
      debugPrint('forge-notify read rate-limited for $path: $e');
      return _Read.rateLimited;
    } on Object catch (e) {
      // The old snapshot stays, so the next good read diffs against it.
      debugPrint('forge-notify read failed for $path: $e');
      return _Read.failed;
    }
  }

  /// Every commit whose CI is worth reporting: each open request's head,
  /// plus the current branch's upstream tip when no request already covers
  /// it. The upstream counts only when it tracks `origin`, the remote the
  /// forge is resolved from: a branch tracking a fork lives on another
  /// project, which this forge cannot answer for.
  Future<Map<String, ({String branch, int? prNumber, String? targetBranch})>>
  _shaLabels(String path, Map<int, PullRequest> openPrs) async {
    final labels =
        <String, ({String branch, int? prNumber, String? targetBranch})>{
          for (final pr in openPrs.values)
            pr.headSha: (
              branch: pr.sourceBranch,
              prNumber: pr.number,
              targetBranch: pr.targetBranch,
            ),
        };
    final RepoData data;
    try {
      data = await _ref.read(repoDataProvider(path).future);
    } on Object {
      // Without the repo's branches there is no upstream to watch; the
      // requests are still worth watching.
      return labels;
    }
    for (final b in data.branches) {
      if (!b.current || b.upstream.isEmpty) continue;
      for (final r in data.remoteBranches) {
        if (r.remote != kForgeRemote) continue;
        if (r.name != b.upstream || r.tip.isEmpty) continue;
        labels.putIfAbsent(
          r.tip,
          () => (branch: b.name, prNumber: null, targetBranch: null),
        );
      }
    }
    return labels;
  }

  /// CI states for [shas]. A sha whose last known state is final keeps it
  /// without another read; only new or still-running ones cost a request.
  /// A sha whose read fails keeps what was known about it (or stays
  /// unknown), so one bad commit cannot hold back the rest of the repo.
  Future<Map<String, ChecksOverall>> _readCi(
    Forge forge,
    Iterable<String> shas,
    ForgeSnapshot? prev,
  ) async {
    final out = <String, ChecksOverall>{};
    for (final sha in shas) {
      final known = prev?.ciBySha[sha];
      if (known != null && _isFinal(known)) {
        out[sha] = known;
        continue;
      }
      try {
        out[sha] = (await forge.checksForRef(sha)).overall;
      } on ForgeRateLimited {
        // The whole host is refusing, not this commit: fail the repo's read
        // so the watcher backs off instead of retrying at full rate.
        rethrow;
      } on ForgeUnauthenticated {
        rethrow;
      } on Object catch (e) {
        debugPrint('forge-notify CI read failed for $sha: $e');
        if (known != null) out[sha] = known;
      }
    }
    return out;
  }

  Future<void> _report(
    String path,
    ForgeKind kind,
    Forge forge,
    List<ForgeEvent> events,
  ) async {
    final wantCi = _ref.read(notifyEnabledProvider((path, NotifyEvent.ci)));
    final wantPrs = _ref.read(
      notifyEnabledProvider((path, NotifyEvent.pullRequests)),
    );
    final resolved = <(ForgeEvent, PrGoneOutcome?)>[];
    for (final e in events) {
      switch (e) {
        case CiFinished():
          if (wantCi) resolved.add((e, null));
        case PrOpened():
          if (wantPrs) resolved.add((e, null));
        case PrGone(:final number):
          if (!wantPrs) continue;
          final outcome = await _goneOutcome(forge, number);
          // Still open: it only fell off the end of the list page.
          if (outcome != null) resolved.add((e, outcome));
      }
    }
    if (resolved.isEmpty) return;

    final rendered = renderForgeEvents(
      _ref.read(appL10nProvider),
      repoPath: path,
      repoName: p.basename(path),
      kind: kind,
      events: resolved,
    );
    final gate = _ref.read(notificationGateProvider);
    if (resolved.length > kForgeBatchThreshold) {
      final anyPr = resolved.any((r) => r.$1 is! CiFinished);
      for (final n in rendered) {
        await gate.notify(anyPr ? NotifyEvent.pullRequests : NotifyEvent.ci, n);
      }
      return;
    }
    for (var i = 0; i < rendered.length; i++) {
      final kindOf = resolved[i].$1 is CiFinished
          ? NotifyEvent.ci
          : NotifyEvent.pullRequests;
      await gate.notify(kindOf, rendered[i]);
    }
  }

  /// What became of a request that left the open list, or null when it is
  /// in fact still open.
  Future<PrGoneOutcome?> _goneOutcome(Forge forge, int number) async {
    try {
      final detail = await forge.pullRequest(number);
      return switch (detail.request.state) {
        PullRequestState.merged => PrGoneOutcome.merged,
        PullRequestState.closed => PrGoneOutcome.closed,
        PullRequestState.open || PullRequestState.draft => null,
      };
    } on Object {
      return PrGoneOutcome.unknown;
    }
  }
}

/// How one repo's read went: it had no forge to read, it was read, it failed,
/// or its host refused for running over its rate limit.
enum _Read { skipped, ok, failed, rateLimited }

bool _isFinal(ChecksOverall s) =>
    s == ChecksOverall.success ||
    s == ChecksOverall.failure ||
    s == ChecksOverall.mixed;

/// Instantiate once (watched by the app shell) to keep it alive.
final forgeNotifyWatcherProvider = Provider<ForgeNotifyWatcher>(
  (ref) => ForgeNotifyWatcher(ref),
);
