import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/forge/forge_error.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/forge_server.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/models.dart';
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

    test('a self-hosted server is named by product and host', () {
      const ghe = ForgeServer(kind: ForgeKind.github, host: 'ghe.corp');
      expect(
        forgePanelMessage(const ForgeUnauthenticated(), l, ghe),
        contains('GitHub Enterprise (ghe.corp)'),
      );
    });

    test('names each failure the user can act on', () {
      expect(
        forgePanelMessage(const ForgeUnauthenticated(), l, kGithubCloud),
        contains('token'),
      );
      expect(
        forgePanelMessage(const ForgeNotVisible(), l, kGithubCloud),
        contains('visible'),
      );
      expect(
        forgePanelMessage(const ForgeOffline('x'), l, kGithubCloud),
        contains('reach'),
      );
      expect(
        forgePanelMessage(const ForgeServerFault(503), l, kGithubCloud),
        contains('503'),
      );
      expect(
        forgePanelMessage(const ForgeMalformed('x'), l, kGithubCloud),
        contains('could not read'),
      );
    });

    test('a rate limit with a known reset says when', () {
      final at = DateTime.utc(2026, 9, 17, 14, 30);
      expect(
        forgePanelMessage(ForgeRateLimited(at), l, kGithubCloud),
        contains('resets at'),
      );
    });

    test('a rate limit with no reset still reads as a limit', () {
      expect(
        forgePanelMessage(const ForgeRateLimited(null), l, kGithubCloud),
        contains('limit reached'),
      );
    });

    test('never leaks a detail string that could carry a secret', () {
      // ForgeOffline and ForgeMalformed carry a detail field. The panel must
      // show its own words, not echo whatever was put in there.
      final msg = forgePanelMessage(
        const ForgeOffline('token=abc123'),
        l,
        kGithubCloud,
      );
      expect(msg, isNot(contains('abc123')));
    });

    test('an unexpected error still produces something showable', () {
      expect(
        forgePanelMessage(StateError('boom'), l, kGithubCloud),
        isNotEmpty,
      );
      expect(
        forgePanelMessage(StateError('boom'), l, kGithubCloud),
        isNot(contains('boom')),
      );
    });

    test('error messages name the forge that answered', () async {
      expect(
        forgePanelMessage(const ForgeUnauthenticated(), l, kGitlabCloud),
        contains('GitLab'),
      );
      expect(
        forgePanelMessage(const ForgeUnauthenticated(), l, kGithubCloud),
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

  group('forgeSourceBranch', () {
    test('names the branch an origin upstream points at', () {
      expect(forgeSourceBranch('origin/main'), 'main');
      expect(forgeSourceBranch('origin/feature/nested'), 'feature/nested');
    });

    test('is null when the branch tracks nothing', () {
      expect(forgeSourceBranch(''), isNull);
    });

    test('is null when the upstream lives on another remote', () {
      // The forge is resolved from origin, so a branch pushed only to a fork
      // has nothing to propose on it.
      expect(forgeSourceBranch('upstream/main'), isNull);
      expect(forgeSourceBranch('originals/main'), isNull);
    });

    test('is null for a bare remote name', () {
      expect(forgeSourceBranch('origin/'), isNull);
      expect(forgeSourceBranch('origin'), isNull);
    });
  });

  group('newPullRequestWebUrl', () {
    const github = ForgeHost(
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

    test('opens the github compare page for the branch', () {
      expect(
        newPullRequestWebUrl(github, 'fix-1').toString(),
        'https://github.com/senseyman/mergelio/compare/fix-1?expand=1',
      );
    });

    test('keeps the slashes of a nested github branch literal', () {
      expect(
        newPullRequestWebUrl(github, 'feature/nested').toString(),
        'https://github.com/senseyman/mergelio/compare/feature/nested?expand=1',
      );
    });

    test('escapes characters git allows but a URL path does not', () {
      // `#` would end the path and `%41` would be read back as `A`.
      expect(
        newPullRequestWebUrl(github, 'a#b%41').toString(),
        'https://github.com/senseyman/mergelio/compare/a%23b%2541?expand=1',
      );
    });

    test('refuses a branch that would climb out of the repository', () {
      expect(newPullRequestWebUrl(github, '../../other/repo'), isNull);
      expect(newPullRequestWebUrl(github, 'a/./b'), isNull);
      expect(newPullRequestWebUrl(github, 'a//b'), isNull);
      expect(newPullRequestWebUrl(github, ''), isNull);
    });

    test('opens the gitlab new merge request page with the source set', () {
      final url = newPullRequestWebUrl(gitlab, 'feature/x')!;
      expect(url.scheme, 'https');
      expect(url.host, 'gitlab.com');
      expect(url.path, '/group/sub/app/-/merge_requests/new');
      expect(url.queryParameters, {
        'merge_request[source_branch]': 'feature/x',
      });
    });

    test('a gitlab branch travels in the query, so odd names stay intact', () {
      final url = newPullRequestWebUrl(gitlab, 'a#b&c=d')!;
      expect(url.path, '/group/sub/app/-/merge_requests/new');
      expect(url.queryParameters['merge_request[source_branch]'], 'a#b&c=d');
    });

    test('a gitlab branch name still cannot be empty', () {
      expect(newPullRequestWebUrl(gitlab, ''), isNull);
    });
  });

  group('pushedSourceBranch', () {
    const onOrigin = [
      RemoteBranch(remote: 'origin', branch: 'main'),
      RemoteBranch(remote: 'origin', branch: 'remote-name'),
      RemoteBranch(remote: 'origin', branch: 'pushed'),
      RemoteBranch(remote: 'fork', branch: 'forked'),
    ];

    test('uses the name origin has, not the local one', () {
      expect(
        pushedSourceBranch(
          const Branch(name: 'local-name', upstream: 'origin/remote-name'),
          onOrigin,
        ),
        'remote-name',
      );
    });

    test('is null when the upstream on origin is gone', () {
      expect(
        pushedSourceBranch(
          const Branch(name: 'merged', upstream: 'origin/merged'),
          onOrigin,
        ),
        isNull,
      );
    });

    test('a gone upstream does not fall back to a same-named branch', () {
      // `pushed` exists on origin, but this branch says it tracks something
      // else that is gone; guessing would propose the wrong commits.
      expect(
        pushedSourceBranch(
          const Branch(name: 'pushed', upstream: 'origin/old'),
          onOrigin,
        ),
        isNull,
      );
    });

    test(
      'a branch with no upstream uses origin\'s branch of the same name',
      () {
        // Pushed without -u: origin has it, git just never recorded the link.
        expect(
          pushedSourceBranch(const Branch(name: 'pushed'), onOrigin),
          'pushed',
        );
      },
    );

    test('a branch with no upstream and nothing on origin is unpushed', () {
      expect(pushedSourceBranch(const Branch(name: 'local'), onOrigin), isNull);
    });

    test('a branch tracking another remote is refused', () {
      expect(
        pushedSourceBranch(
          const Branch(name: 'main', upstream: 'fork/main'),
          onOrigin,
        ),
        isNull,
      );
    });

    test('another remote\'s same-named branch is not origin\'s', () {
      expect(
        pushedSourceBranch(const Branch(name: 'forked'), onOrigin),
        isNull,
      );
    });
  });

  group('forgeConnectHintFor', () {
    test(
      'each cloud quotes its own limits; a self-hosted server none',
      () async {
        final l = await _en();
        expect(forgeConnectHintFor(l, kGithubCloud), l.forgeConnectHint);
        expect(forgeConnectHintFor(l, kGitlabCloud), l.forgeConnectHintGitlab);
        for (final kind in ForgeKind.values) {
          final hint = forgeConnectHintFor(
            l,
            ForgeServer(kind: kind, host: 'self.corp'),
          );
          expect(hint, l.forgeConnectHintSelfHosted);
          expect(hint, isNot(contains('60')));
        }
      },
    );
  });
}
