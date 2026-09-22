@Tags(['live'])
library;

// Proof that the mocked tests still resemble the real GitLab API.
//
// Every parser elsewhere is tested against hand-written JSON, which proves it
// self-consistent, not correct. A field GitLab renames would turn into a
// silently empty list — the one failure this layer's error model exists to
// prevent. These tests read the real API and assert on shapes rather than on
// contents, so they stay green while the data underneath keeps moving.
//
// By default they run unauthenticated against a public project. Point them
// at your own, or at a private one, with:
//
//   MERGELIO_LIVE_OWNER=me MERGELIO_LIVE_REPO=secret \
//   MERGELIO_GITLAB_TOKEN=glpat-... flutter test --run-skipped --tags live

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/forge/etag_cache.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/data/forge/gitlab_forge.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';

/// A project busy enough that every list below is non-empty. Override it
/// when you want to point these at your own work.
final _owner = Platform.environment['MERGELIO_LIVE_OWNER'] ?? 'gitlab-org';
final _repo = Platform.environment['MERGELIO_LIVE_REPO'] ?? 'gitlab';

/// Optional: raises the rate limit and reaches private projects. Never
/// printed — [ForgeToken] hides itself, and nothing here logs a header.
ForgeToken? get _token {
  final raw = Platform.environment['MERGELIO_GITLAB_TOKEN'];
  return raw == null || raw.isEmpty ? null : ForgeToken(raw);
}

ForgeHost get _host => ForgeHost(
  kind: ForgeKind.gitlab,
  host: 'gitlab.com',
  owner: _owner,
  repo: _repo,
);

GitlabForge _forge({EtagCache? cache, int maxPages = 1}) => GitlabForge(
  host: _host,
  http: ForgeHttp(kind: ForgeKind.gitlab, token: _token),
  cache: cache,
  maxPages: maxPages,
);

/// Turns the two failures that are about the environment rather than the code
/// into a readable message, so a spent rate limit never reads as a parser bug.
Future<T> _reporting<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on ForgeRateLimited catch (e) {
    fail(
      'GitLab rate limit reached (resets ${e.resetAt ?? "shortly"}). '
      'Unauthenticated callers get a shared quota; set '
      'MERGELIO_GITLAB_TOKEN to raise it. This is not a code failure.',
    );
  } on ForgeOffline {
    fail('Could not reach gitlab.com. This is not a code failure.');
  }
}

const _slow = Timeout(Duration(seconds: 90));

void main() {
  test('reads merge requests, with every field the UI needs', () async {
    final prs = await _reporting(() => _forge().pullRequests(limit: 10));

    // An empty list is the failure mode this whole error model exists to
    // prevent, so it is asserted against rather than tolerated.
    expect(prs, isNotEmpty, reason: 'a busy project has open requests');
    for (final p in prs) {
      expect(p.title, isNotEmpty);
      expect(p.sourceBranch, isNotEmpty);
      expect(p.targetBranch, isNotEmpty);
      expect(p.headSha, isNotEmpty, reason: 'CI is keyed by this sha');
      expect(p.author.login, isNot('unknown'), reason: 'author.username moved');
      expect(p.updatedAt?.isUtc, isTrue);
    }
  }, timeout: _slow);

  test('reads issues, with every field the UI needs', () async {
    final issues = await _reporting(() => _forge().issues(limit: 20));

    expect(issues, isNotEmpty);
    for (final i in issues) {
      expect(i.title, isNotEmpty);
      expect(i.number, greaterThan(0));
      expect(i.author.login, isNot('unknown'));
    }
  }, timeout: _slow);

  test('reads CI for a real commit without meeting a state it cannot '
      'name', () async {
    final forge = _forge();
    final prs = await _reporting(() => forge.pullRequests(limit: 1));
    final summary = await _reporting(
      () => forge.checksForRef(prs.first.headSha),
    );

    for (final r in summary.runs) {
      expect(r.name, isNotEmpty);
    }
    // An unrecognised status is safe by design — it becomes unknown and
    // never reads as green — but meeting one here means GitLab has added a
    // value worth mapping deliberately.
    final unnamed = summary.runs
        .where((r) => r.state == CheckState.unknown)
        .map((r) => r.name)
        .toList();
    expect(
      unnamed,
      isEmpty,
      reason: 'GitLab sent a status this version does not map',
    );
  }, timeout: _slow);

  test('follows the Link header GitLab actually sends', () async {
    final prs = await _reporting(
      () => _forge(maxPages: 2).pullRequests(limit: 500),
    );

    expect(
      prs.map((p) => p.number).toSet(),
      hasLength(prs.length),
      reason: 'a page was fetched or concatenated twice',
    );
  }, timeout: _slow);

  test('revalidates a second read instead of refetching it', () async {
    final cache = EtagCache();
    final forge = _forge(cache: cache);

    final first = await _reporting(() => forge.issues(limit: 5));
    expect(cache.length, greaterThan(0), reason: 'no etag was stored');
    final second = await _reporting(() => forge.issues(limit: 5));

    expect(second.map((i) => i.number), first.map((i) => i.number));
  }, timeout: _slow);

  test('reports a project it cannot see, rather than an empty list', () async {
    final missing = GitlabForge(
      host: ForgeHost(
        kind: ForgeKind.gitlab,
        host: 'gitlab.com',
        owner: _owner,
        repo: 'definitely-not-a-real-project-9z8x7c',
      ),
      http: ForgeHttp(kind: ForgeKind.gitlab, token: _token),
    );

    await expectLater(missing.pullRequests(), throwsA(isA<ForgeNotVisible>()));
  }, timeout: _slow);
}
