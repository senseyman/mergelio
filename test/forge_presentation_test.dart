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
        forgePanelMessage(const ForgeUnauthenticated(), l),
        contains('token'),
      );
      expect(
        forgePanelMessage(const ForgeNotVisible(), l),
        contains('visible'),
      );
      expect(forgePanelMessage(const ForgeOffline('x'), l), contains('reach'));
      expect(
        forgePanelMessage(const ForgeServerFault(503), l),
        contains('503'),
      );
      expect(
        forgePanelMessage(const ForgeMalformed('x'), l),
        contains('could not read'),
      );
    });

    test('a rate limit with a known reset says when', () {
      final at = DateTime.utc(2026, 9, 17, 14, 30);
      expect(forgePanelMessage(ForgeRateLimited(at), l), contains('resets at'));
    });

    test('a rate limit with no reset still reads as a limit', () {
      expect(
        forgePanelMessage(const ForgeRateLimited(null), l),
        contains('limit reached'),
      );
    });

    test('never leaks a detail string that could carry a secret', () {
      // ForgeOffline and ForgeMalformed carry a detail field. The panel must
      // show its own words, not echo whatever was put in there.
      final msg = forgePanelMessage(const ForgeOffline('token=abc123'), l);
      expect(msg, isNot(contains('abc123')));
    });

    test('an unexpected error still produces something showable', () {
      expect(forgePanelMessage(StateError('boom'), l), isNotEmpty);
      expect(forgePanelMessage(StateError('boom'), l), isNot(contains('boom')));
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
  });
}
