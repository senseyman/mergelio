import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// A [GitService] whose `git credential` calls always exit non-zero, so the
/// helper never actually stores or forgets anything.
class _FailingGit implements GitService {
  final calls = <List<String>>[];

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
    return const GitResult(1, '', 'credential helper unavailable');
  }
}

/// A [GitService] whose `git credential` calls record themselves and then
/// hang until [gate] completes, so a test can prove a second call did or did
/// not happen while the first was still in flight.
class _GatedGit implements GitService {
  final Completer<void> gate;
  final calls = <List<String>>[];

  _GatedGit(this.gate);

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
    await gate.future;
    return const GitResult(0, '', '');
  }
}

/// A [GitService] that behaves like a credential helper with a memory: what
/// `credential approve` writes is what the next `credential fill` reads back,
/// and `credential reject` empties it again. No real git, no keychain.
class _StoringCredentialGit implements GitService {
  String? stored;
  int fills = 0;

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
    if (args.length >= 2 && args[0] == 'credential') {
      switch (args[1]) {
        case 'fill':
          fills++;
          final held = stored;
          return GitResult(
            0,
            held == null
                ? 'protocol=https\nhost=github.com\n'
                : 'username=x-access-token\npassword=$held\n',
            '',
          );
        case 'approve':
          stored = parseCredentialReply(stdin ?? '')['password'];
          return const GitResult(0, '', '');
        case 'reject':
          stored = null;
          return const GitResult(0, '', '');
      }
    }
    return const GitResult(1, '', 'unsupported in this stub');
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
      'disconnecting reports failure rather than a false success when the '
      'helper refuses the erase request',
      (tester) async {
        final git = _FailingGit();
        final container = await _pump(
          tester,
          overrides: [gitServiceProvider.overrideWithValue(git)],
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
        // A false from reject must not be reported as the token being gone —
        // that is the silent-failure shape this row must not repeat.
        expect(
          container.read(toastProvider).last.title,
          isNot('Token removed.'),
        );
        // The wording matters: a failed erase must say the token may still be
        // stored, not merely that something went wrong.
        expect(
          container.read(toastProvider).last.title,
          "Could not remove the token. It may still be stored by git's "
          'credential helper.',
        );
        expect(container.read(toastProvider).last.kind, ToastKind.error);
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'connecting makes the next forge read carry the new token, without a '
      'restart',
      (tester) async {
        // Driven through the real provider graph on purpose: the token is
        // unreadable once it is inside the transport, so the only honest
        // proof it was picked up is the request that goes out. Storing it in
        // the helper is not enough — a cached "no token" answer would keep
        // every later read anonymous until the app was restarted.
        final git = _StoringCredentialGit();
        final pullAuths = <String?>[];
        final container = await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            originRemoteUrlProvider.overrideWith(
              (ref, path) async => 'https://github.com/o/r.git',
            ),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((req) async {
                if (req.url.path == '/repos/o/r/pulls') {
                  pullAuths.add(req.headers['authorization']);
                  return http.Response('[]', 200);
                }
                return http.Response('{"login":"me"}', 200);
              }),
            ),
          ],
        );

        await container.read(pullRequestPanelProvider('/repo').future);
        expect(pullAuths, [
          null,
        ], reason: 'nothing is stored yet, so the first read is anonymous');

        await tester.enterText(find.byType(TextField), 'ghp_new');
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        await container.read(pullRequestPanelProvider('/repo').future);

        expect(pullAuths.length, greaterThan(1));
        expect(pullAuths.last, 'Bearer ghp_new');
        expect(
          git.fills,
          greaterThan(1),
          reason: 'the helper must be asked again after the token changed',
        );
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'disconnecting makes the next forge read stop carrying the token',
      (tester) async {
        final git = _StoringCredentialGit()..stored = 'ghp_old';
        final pullAuths = <String?>[];
        final container = await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            originRemoteUrlProvider.overrideWith(
              (ref, path) async => 'https://github.com/o/r.git',
            ),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((req) async {
                if (req.url.path == '/repos/o/r/pulls') {
                  pullAuths.add(req.headers['authorization']);
                  return http.Response('[]', 200);
                }
                return http.Response('{"login":"me"}', 200);
              }),
            ),
          ],
        );

        await container.read(pullRequestPanelProvider('/repo').future);
        expect(pullAuths, ['Bearer ghp_old']);

        await tester.tap(find.text('Disconnect'));
        await tester.pump();
        await tester.pump();

        await container.read(pullRequestPanelProvider('/repo').future);

        expect(pullAuths.length, greaterThan(1));
        expect(
          pullAuths.last,
          isNull,
          reason: 'a forgotten token must not keep being sent',
        );
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets('the typed token never reaches a diagnostics dump', (
      tester,
    ) async {
      // TextEditingController.toString() prints its value in full, and the
      // controller is dumped as a property of both TextField and
      // EditableText — so the token lands in the widget inspector and in
      // every tree dump an unrelated error produces.
      const secret = 'ghp_supersecretvalue';
      await _pump(
        tester,
        overrides: [gitServiceProvider.overrideWithValue(_RecordingGit())],
      );

      await tester.enterText(find.byType(TextField), secret);
      await tester.pump();

      expect(
        tester.element(find.byType(ForgeAccountRow)).toStringDeep(),
        isNot(contains(secret)),
      );
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      expect(controller.text, secret, reason: 'the field still holds it');
      expect(controller.toString(), isNot(contains(secret)));
      expect(
        DiagnosticsProperty<TextEditingController>(
          'controller',
          controller,
        ).toString(),
        isNot(contains(secret)),
      );
    });

    testWidgets(
      'tapping Connect twice before a frame renders validates only once',
      (tester) async {
        final git = _RecordingGit();
        var requests = 0;
        // Held open until after both taps land, so the first request is
        // provably still in flight when the second tap's handler runs —
        // not just "usually still in flight", which a timing-dependent test
        // could pass or fail on depending on how many microtask turns
        // MockClient happens to take.
        final gate = Completer<void>();
        final container = await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((_) async {
                requests++;
                await gate.future;
                return http.Response('{"login":"me"}', 200);
              }),
            ),
          ],
        );

        await tester.enterText(find.byType(TextField), 'ghp_new');
        // Two taps, no pump in between: setState from the first tap has not
        // yet produced a rebuild, so a button-enabled check alone would not
        // catch this — the guard must be in the handler itself.
        await tester.tap(find.text('Connect'));
        await tester.tap(find.text('Connect'));
        gate.complete();
        await tester.pump();
        await tester.pump();

        expect(requests, 1);
        expect(container.read(toastProvider).isNotEmpty, isTrue);
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'tapping Disconnect twice before a frame renders erases only once',
      (tester) async {
        // Held open the same way as the Connect gate above, so the first
        // reject call is provably still in flight for the second tap.
        final gate = Completer<void>();
        final git = _GatedGit(gate);
        final container = await _pump(
          tester,
          overrides: [gitServiceProvider.overrideWithValue(git)],
        );

        await tester.tap(find.text('Disconnect'));
        await tester.tap(find.text('Disconnect'));
        gate.complete();
        await tester.pump();
        await tester.pump();

        expect(
          git.calls
              .where(
                (c) =>
                    c.length >= 2 && c[0] == 'credential' && c[1] == 'reject',
              )
              .length,
          1,
        );
        expect(container.read(toastProvider).isNotEmpty, isTrue);
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
