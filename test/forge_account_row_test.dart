import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/forge/etag_cache.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/forge/forge_http.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/preferences/forge_account_row.dart';

/// A [GitService] that records every `git credential` invocation and answers
/// success for all of them, without touching a real git binary.
class _RecordingGit implements GitService {
  final calls = <List<String>>[];
  final stdins = <String?>[];

  @override
  Future<String> version() async => 'git version 0.0.0';

  @override
  Future<bool> isRepository(String path) async => true;

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
    stdins.add(stdin);
    return const GitResult(0, '', '');
  }
}

/// Pumps [ForgeAccountRow] under an explicit container, so a test can both
/// drive the widget and read provider state (toasts included) afterwards.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: const Scaffold(body: ForgeAccountRow()),
      ),
    ),
  );
  return container;
}

void main() {
  group('validateForgeToken', () {
    test('accepts a token GitHub answers for', () async {
      final ok = await validateForgeToken(
        const ForgeToken('t'),
        httpFor: (token) => ForgeHttp(
          token: token,
          client: MockClient((_) async => http.Response('{"login":"me"}', 200)),
        ),
      );
      expect(ok, isTrue);
    });

    test('rejects a token GitHub refuses', () async {
      final ok = await validateForgeToken(
        const ForgeToken('bad'),
        httpFor: (token) => ForgeHttp(
          token: token,
          client: MockClient((_) async => http.Response('', 401)),
        ),
      );
      expect(ok, isFalse);
    });

    test('sends the token, so a valid one is not reported as bad', () async {
      String? sent;
      await validateForgeToken(
        const ForgeToken('secret'),
        httpFor: (token) => ForgeHttp(
          token: token,
          client: MockClient((req) async {
            sent = req.headers['authorization'];
            return http.Response('{}', 200);
          }),
        ),
      );
      expect(sent, 'Bearer secret');
    });

    test('a forge that cannot be reached is not a rejected token', () async {
      final ok = await validateForgeToken(
        const ForgeToken('t'),
        httpFor: (token) => ForgeHttp(
          token: token,
          client: MockClient((_) async => throw const SocketExceptionStub()),
        ),
      );
      expect(ok, isFalse);
    });
  });

  group('ForgeAccountRow', () {
    testWidgets('the token field obscures its text', (tester) async {
      await _pump(
        tester,
        overrides: [gitServiceProvider.overrideWithValue(_RecordingGit())],
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
    });

    testWidgets(
      'connecting with a token GitHub accepts stores it and clears the '
      'etag cache',
      (tester) async {
        final git = _RecordingGit();
        final cache = EtagCache()
          ..store(Uri.https('api.github.com', '/x'), 'etag-1', '{}');
        final container = await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            etagCacheProvider.overrideWithValue(cache),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('{"login":"me"}', 200)),
            ),
          ],
        );

        await tester.enterText(find.byType(TextField), 'ghp_new');
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        expect(
          git.calls.any(
            (c) => c.length >= 2 && c[0] == 'credential' && c[1] == 'approve',
          ),
          isTrue,
          reason: 'a validated token must be handed to the credential helper',
        );
        expect(git.stdins.last, contains('password=ghp_new'));
        expect(cache.length, 0);
        expect(
          container.read(toastProvider).last.title,
          'Token saved to the system keychain.',
        );
        // Flushes the toast's own dismissal timer so it does not outlive the
        // widget tree the test tears down.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'a token GitHub rejects is reported and never reaches the credential '
      'helper',
      (tester) async {
        final git = _RecordingGit();
        final container = await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('', 401)),
            ),
          ],
        );

        await tester.enterText(find.byType(TextField), 'bad-token');
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        expect(git.calls, isEmpty);
        expect(
          container.read(toastProvider).last.title,
          'GitHub rejected that token.',
        );
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'disconnecting forgets the credential and clears the etag cache',
      (tester) async {
        final git = _RecordingGit();
        final cache = EtagCache()
          ..store(Uri.https('api.github.com', '/x'), 'etag-1', '{}');
        final container = await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            etagCacheProvider.overrideWithValue(cache),
          ],
        );

        await tester.tap(find.text('Disconnect'));
        await tester.pump();
        await tester.pump();

        expect(
          git.calls.any(
            (c) => c.length >= 2 && c[0] == 'credential' && c[1] == 'reject',
          ),
          isTrue,
        );
        expect(cache.length, 0);
        expect(container.read(toastProvider).last.title, 'Token removed.');
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'shows nothing left of the budget when there is no active repository',
      (tester) async {
        await _pump(
          tester,
          overrides: [gitServiceProvider.overrideWithValue(_RecordingGit())],
        );
        await tester.pump();

        expect(find.textContaining('requests left this hour'), findsNothing);
      },
    );

    testWidgets(
      'shows what is left of the hourly budget for the active repository',
      (tester) async {
        await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(_RecordingGit()),
            workspaceProvider.overrideWith((ref) {
              final c = WorkspaceController();
              c.openRepo('/repo');
              return c;
            }),
            forgeRateLimitProvider.overrideWith(
              (ref, path) async =>
                  const ForgeRateLimit(remaining: 42, limit: 5000),
            ),
          ],
        );
        await tester.pump();

        expect(
          find.text('42 of 5000 requests left this hour.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows nothing rather than a wrong number when the budget cannot be '
      'read',
      (tester) async {
        await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(_RecordingGit()),
            workspaceProvider.overrideWith((ref) {
              final c = WorkspaceController();
              c.openRepo('/repo');
              return c;
            }),
            forgeRateLimitProvider.overrideWith((ref, path) async => null),
          ],
        );
        await tester.pump();

        expect(find.textContaining('requests left this hour'), findsNothing);
      },
    );
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
