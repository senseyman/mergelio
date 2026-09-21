import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/state/forge.dart';

const _host = ForgeHost(
  kind: ForgeKind.github,
  host: 'github.com',
  owner: 'o',
  repo: 'r',
);

PullRequest _pr(int n) => _prWithSha(n, 'sha$n');

PullRequest _prWithSha(int n, String sha) => PullRequest(
  number: n,
  title: 'pr $n',
  state: PullRequestState.open,
  author: const ForgeUser(login: 'me'),
  sourceBranch: 'b$n',
  targetBranch: 'main',
  headSha: sha,
);

class _FakeForge implements Forge {
  @override
  final ForgeHost host = _host;

  final int prCount;
  final ForgeError? failWith;
  final Duration delay;

  int sawLimit = 0;
  int checkCalls = 0;
  int _liveChecks = 0;
  int peakChecks = 0;

  _FakeForge({this.prCount = 3, this.failWith, this.delay = Duration.zero});

  @override
  Future<List<PullRequest>> pullRequests({int limit = 50}) async {
    sawLimit = limit;
    if (failWith != null) throw failWith!;
    return List.generate(prCount, _pr);
  }

  @override
  Future<ChecksSummary> checksForRef(String ref) async {
    checkCalls++;
    _liveChecks++;
    peakChecks = _liveChecks > peakChecks ? _liveChecks : peakChecks;
    await Future<void>.delayed(delay);
    _liveChecks--;
    return const ChecksSummary(overall: ChecksOverall.success);
  }

  @override
  Future<List<PullRequest>> pullRequestsForBranch(
    String branch, {
    int limit = 50,
  }) async => [];

  @override
  Future<List<Issue>> issues({int limit = 50}) async => [];
}

class _CiFailingForge extends _FakeForge {
  _CiFailingForge() : super(prCount: 2);

  @override
  Future<ChecksSummary> checksForRef(String ref) async =>
      throw const ForgeServerFault(500);
}

/// Returns a fixed list of requests instead of generating one from
/// [prCount], so a test can put more than one on the same head sha.
class _FixedForge extends _FakeForge {
  final List<PullRequest> _prs;
  _FixedForge(this._prs);

  @override
  Future<List<PullRequest>> pullRequests({int limit = 50}) async {
    sawLimit = limit;
    return _prs;
  }
}

ProviderContainer _containerFor(Forge? forge) {
  final c = ProviderContainer(
    overrides: [githubForgeProvider.overrideWith((ref, path) async => forge)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('fetchWithLimit', () {
    test('never runs more than the cap at once', () async {
      var live = 0;
      var peak = 0;
      await fetchWithLimit<int, int>([1, 2, 3, 4, 5, 6, 7, 8], 3, (k) async {
        live++;
        peak = live > peak ? live : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        live--;
        return k;
      });
      expect(peak, lessThanOrEqualTo(3));
    });

    test('keeps every result, keyed by input', () async {
      final out = await fetchWithLimit<int, String>(
        [1, 2, 3],
        2,
        (k) async => 'v$k',
      );
      expect(out, {1: 'v1', 2: 'v2', 3: 'v3'});
    });

    test('a null result is left out rather than stored', () async {
      final out = await fetchWithLimit<int, String>(
        [1, 2],
        2,
        (k) async => k == 1 ? 'v1' : null,
      );
      expect(out, {1: 'v1'});
    });
  });

  group('pullRequestPanelProvider', () {
    test('returns an empty panel when repo is not on a forge', () async {
      final panel = await _containerFor(null)
          .read(pullRequestPanelProvider('/repo').future);
      expect(panel.pullRequests, isEmpty);
      expect(panel.checksBySha, isEmpty);
    });

    test('asks for exactly the budgeted number of requests', () async {
      final forge = _FakeForge();
      await _containerFor(forge).read(pullRequestPanelProvider('/repo').future);
      expect(forge.sawLimit, kPullRequestLimit);
      expect(kPullRequestLimit, 10);
    });

    test('fetches CI for every returned request', () async {
      final forge = _FakeForge(prCount: 5);
      final panel = await _containerFor(forge)
          .read(pullRequestPanelProvider('/repo').future);
      expect(forge.checkCalls, 5);
      expect(
        panel.checksBySha.keys.toSet(),
        List.generate(5, _pr).map((p) => p.headSha).toSet(),
      );
    });

    test('never reads more than kChecksConcurrency checks at once', () async {
      final forge = _FakeForge(
        prCount: 10,
        delay: const Duration(milliseconds: 10),
      );
      await _containerFor(forge).read(pullRequestPanelProvider('/repo').future);
      expect(forge.peakChecks, lessThanOrEqualTo(kChecksConcurrency));
    });

    test('a failed read reaches the caller, never an empty list', () async {
      final forge = _FakeForge(failWith: const ForgeUnauthenticated());
      await expectLater(
        _containerFor(forge).read(pullRequestPanelProvider('/repo').future),
        throwsA(isA<ForgeUnauthenticated>()),
      );
    });

    test('a request whose CI cannot be read is still listed', () async {
      // checksForRef throwing must cost the badge, not the row.
      final forge = _CiFailingForge();
      final panel = await _containerFor(forge)
          .read(pullRequestPanelProvider('/repo').future);
      expect(panel.pullRequests, hasLength(2));
      expect(panel.checksBySha, isEmpty);
    });

    test('two requests sharing a head sha cost one check, not two', () async {
      // The Forge contract allows one branch to back more than one
      // request; asking twice for the same sha's CI wastes a concurrent
      // slot the etag cache cannot absorb, since both requests land at
      // once.
      final forge = _FixedForge([
        _prWithSha(1, 'shared'),
        _prWithSha(2, 'shared'),
      ]);
      final panel = await _containerFor(forge)
          .read(pullRequestPanelProvider('/repo').future);

      expect(forge.checkCalls, 1);
      expect(panel.pullRequests, hasLength(2));
      // Both rows key their badge off the same sha, so one entry serves
      // both.
      expect(panel.checksBySha['shared']?.overall, ChecksOverall.success);
    });
  });
}
