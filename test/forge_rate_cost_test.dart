// What opening a repository actually costs against the hourly budget, and
// whether the sentence shown in Preferences still tells the truth about it.
//
// The number in that sentence is the only thing a user has to plan around, so
// it is pinned to a measured request count rather than to someone's memory of
// how many endpoints a CI read touches.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/forge.dart';

String _pullsPage(int count) => jsonEncode([
  for (var i = 1; i <= count; i++)
    {
      'number': i,
      'title': 'pr $i',
      'state': 'open',
      'head': {'ref': 'b$i', 'sha': 'sha$i'},
      'base': {'ref': 'main'},
    },
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opening a repository costs a list request per section plus '
      'two per pull request row', () async {
    final paths = <String>[];
    final c = ProviderContainer(
      overrides: [
        originRemoteUrlProvider.overrideWith(
          (ref, path) async => 'https://github.com/o/r.git',
        ),
        forgeTokenProvider.overrideWith((ref, path) async => null),
        forgeHttpClientProvider.overrideWithValue(
          MockClient((req) async {
            paths.add(req.url.path);
            final path = req.url.path;
            return http.Response(
              path.endsWith('/pulls')
                  ? _pullsPage(kPullRequestLimit)
                  : path.endsWith('/issues')
                  ? '[]'
                  : '{}',
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(c.dispose);

    final panel = await c.read(pullRequestPanelProvider('/repo').future);

    expect(panel.pullRequests, hasLength(kPullRequestLimit));
    // One page of rows — the list must not page for a section this size —
    // then a combined-status and a check-runs read for each row.
    expect(paths.where((p) => p.endsWith('/pulls')), hasLength(1));
    expect(paths, hasLength(1 + 2 * kPullRequestLimit));

    // The issue section rides along on the same open, and costs a single
    // list read because its rows carry no CI.
    await c.read(issuePanelProvider('/repo').future);

    expect(paths.where((p) => p.endsWith('/issues')), hasLength(1));
    expect(paths, hasLength(kForgeRequestsPerOpen));
    expect(kForgeRequestsPerOpen, 1 + 2 * kPullRequestLimit + 1);
  });

  test('the budget copy quotes the cost the code actually pays', () async {
    // A sentence that understates the cost is worse than no sentence: it
    // tells someone on the anonymous budget they can open twice as many
    // repositories an hour as they can.
    for (final locale in AppLocalizations.supportedLocales) {
      final l = await AppLocalizations.delegate.load(locale);
      expect(
        l.forgeRateBenefit,
        contains('$kForgeRequestsPerOpen'),
        reason: 'the ${locale.languageCode} copy must quote the real cost',
      );
      expect(
        l.forgeRateBenefit,
        isNot(contains('${kPullRequestLimit + 1}')),
        reason: 'the ${locale.languageCode} copy must not quote the old cost',
      );
    }
  });
}
