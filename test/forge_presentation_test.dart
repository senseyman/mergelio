import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  group('checkBadgeFor', () {
    test('a repository with no CI shows no badge', () {
      expect(checkBadgeFor(null), CheckBadge.none);
      expect(
        checkBadgeFor(const ChecksSummary(overall: ChecksOverall.none)),
        CheckBadge.none,
      );
    });

    test('maps each outcome to its own badge', () {
      CheckBadge of(ChecksOverall o) =>
          checkBadgeFor(ChecksSummary(overall: o));
      expect(of(ChecksOverall.running), CheckBadge.running);
      expect(of(ChecksOverall.success), CheckBadge.success);
      expect(of(ChecksOverall.failure), CheckBadge.failure);
      expect(of(ChecksOverall.mixed), CheckBadge.mixed);
    });

    test('only an all-green summary reads as success', () {
      // A state this version cannot name must never be painted green.
      for (final o in ChecksOverall.values) {
        if (o == ChecksOverall.success) continue;
        expect(
          checkBadgeFor(ChecksSummary(overall: o)),
          isNot(CheckBadge.success),
        );
      }
    });
  });

  group('forgePanelMessage', () {
    late AppLocalizations l;
    setUp(() async => l = await _en());

    test('names each failure the user can act on', () {
      expect(
        forgePanelMessage(const ForgeUnauthenticated(), l, ForgeKind.github),
        contains('token'),
      );
      expect(
        forgePanelMessage(const ForgeNotVisible(), l, ForgeKind.github),
        contains('visible'),
      );
      expect(
        forgePanelMessage(const ForgeOffline('x'), l, ForgeKind.github),
        contains('reach'),
      );
      expect(
        forgePanelMessage(const ForgeServerFault(503), l, ForgeKind.github),
        contains('503'),
      );
      expect(
        forgePanelMessage(const ForgeMalformed('x'), l, ForgeKind.github),
        contains('could not read'),
      );
    });

    test('a rate limit with a known reset says when', () {
      final at = DateTime.utc(2026, 9, 17, 14, 30);
      expect(
        forgePanelMessage(ForgeRateLimited(at), l, ForgeKind.github),
        contains('resets at'),
      );
    });

    test('a rate limit with no reset still reads as a limit', () {
      expect(
        forgePanelMessage(const ForgeRateLimited(null), l, ForgeKind.github),
        contains('limit reached'),
      );
    });

    test('never leaks a detail string that could carry a secret', () {
      // ForgeOffline and ForgeMalformed carry a detail field. The panel must
      // show its own words, not echo whatever was put in there.
      final msg = forgePanelMessage(
        const ForgeOffline('token=abc123'),
        l,
        ForgeKind.github,
      );
      expect(msg, isNot(contains('abc123')));
    });

    test('an unexpected error still produces something showable', () {
      expect(
        forgePanelMessage(StateError('boom'), l, ForgeKind.github),
        isNotEmpty,
      );
      expect(
        forgePanelMessage(StateError('boom'), l, ForgeKind.github),
        isNot(contains('boom')),
      );
    });

    test('error messages name the forge that answered', () async {
      expect(
        forgePanelMessage(const ForgeUnauthenticated(), l, ForgeKind.gitlab),
        contains('GitLab'),
      );
      expect(
        forgePanelMessage(const ForgeUnauthenticated(), l, ForgeKind.github),
        contains('GitHub'),
      );
    });
  });

  group('issueWebUrl', () {
    const host = ForgeHost(
      kind: ForgeKind.github,
      host: 'github.com',
      owner: 'senseyman',
      repo: 'mergelio',
    );
    const gitlab = ForgeHost(
      kind: ForgeKind.gitlab,
      host: 'gitlab.com',
      owner: 'group/sub',
      repo: 'app',
    );

    test('addresses the issue on the web UI', () {
      expect(
        issueWebUrl(host, 12).toString(),
        'https://github.com/senseyman/mergelio/issues/12',
      );
    });

    test('does not borrow the pull request path', () {
      // GitHub serves /pull/<n> and /issues/<n> from different numbering;
      // sending an issue to the pull path lands on someone else's page.
      expect(issueWebUrl(host, 12).path, isNot(contains('/pull/')));
    });

    test('is always https, whatever the remote used', () {
      expect(issueWebUrl(host, 1).scheme, 'https');
    });

    test('a gitlab issue opens at its own path', () {
      expect(
        issueWebUrl(gitlab, 7).toString(),
        'https://gitlab.com/group/sub/app/-/issues/7',
      );
    });

    test('a gitlab issue never lands on the merge request path', () {
      expect(issueWebUrl(gitlab, 7).path, isNot(contains('merge_requests')));
    });
  });

  group('pullRequestWebUrl', () {
    const host = ForgeHost(
      kind: ForgeKind.github,
      host: 'github.com',
      owner: 'senseyman',
      repo: 'mergelio',
    );

    test('addresses the request on the web UI', () {
      expect(
        pullRequestWebUrl(host, 42).toString(),
        'https://github.com/senseyman/mergelio/pull/42',
      );
    });

    test('is always https, whatever the remote used', () {
      expect(pullRequestWebUrl(host, 1).scheme, 'https');
    });

    test('honours the host it was given, rather than assuming github.com', () {
      // Replacing host.host with a literal passes every other test here,
      // because they all use github.com. ForgeHost already models other
      // hosts, so a hardcoded one would only surface against the first
      // enterprise or self-hosted remote anyone tried.
      const enterprise = ForgeHost(
        kind: ForgeKind.github,
        host: 'github.example.test',
        owner: 'o',
        repo: 'r',
      );
      expect(
        pullRequestWebUrl(enterprise, 7).toString(),
        'https://github.example.test/o/r/pull/7',
      );
    });

    test('is built from coordinates, never forge-supplied text', () {
      // Owner and repo come from the remote, which a person controls, and the
      // number is an int. Nothing the API returns can steer the browser.
      const odd = ForgeHost(
        kind: ForgeKind.github,
        host: 'github.com',
        owner: 'a b',
        repo: 'c/d',
      );
      final url = pullRequestWebUrl(odd, 7);
      expect(url.host, 'github.com');
      expect(url.toString(), startsWith('https://github.com/'));
    });

    test('a gitlab merge request opens at its own path', () {
      const gitlab = ForgeHost(
        kind: ForgeKind.gitlab,
        host: 'gitlab.com',
        owner: 'group/sub',
        repo: 'app',
      );
      expect(
        pullRequestWebUrl(gitlab, 42).toString(),
        'https://gitlab.com/group/sub/app/-/merge_requests/42',
      );
    });
  });
}
