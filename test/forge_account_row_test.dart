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
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/models.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/preferences/forge_account_row.dart';

/// A [GitService] that records every `git credential` invocation and answers
/// success for all of them, without touching a real git binary.
class _RecordingGit implements GitService {
  final calls = <List<String>>[];
  final stdins = <String?>[];
  final repoPaths = <String?>[];

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
    repoPaths.add(repoPath);
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

  /// The stdin body of the most recent `credential` invocation, so a test
  /// can see exactly which host and username a write or an erase named.
  String? lastRequest;

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
      lastRequest = stdin;
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

/// A [GitService] that models a credential helper which is not actually
/// configured: `credential approve` still exits zero (git accepted the
/// request and handed it to *some* helper) but every `credential fill`
/// comes back with nothing stored, the way `git-credential-store` behaves
/// with no `credential.helper` set up at all.
class _SilentlyDecliningGit implements GitService {
  int approveCalls = 0;
  int fillCalls = 0;

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
        case 'approve':
          approveCalls++;
          return const GitResult(0, '', '');
        case 'fill':
          fillCalls++;
          return const GitResult(0, 'protocol=https\nhost=github.com\n', '');
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
  ForgeKind kind = ForgeKind.github,
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
        home: Scaffold(body: ForgeAccountRow(kind: kind)),
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
        kind: ForgeKind.github,
        httpFor: (token) => ForgeHttp(
          kind: ForgeKind.github,
          token: token,
          client: MockClient((_) async => http.Response('{"login":"me"}', 200)),
        ),
      );
      expect(ok, isTrue);
    });

    test('rejects a token GitHub refuses', () async {
      final ok = await validateForgeToken(
        const ForgeToken('bad'),
        kind: ForgeKind.github,
        httpFor: (token) => ForgeHttp(
          kind: ForgeKind.github,
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
        kind: ForgeKind.github,
        httpFor: (token) => ForgeHttp(
          kind: ForgeKind.github,
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
        kind: ForgeKind.github,
        httpFor: (token) => ForgeHttp(
          kind: ForgeKind.github,
          token: token,
          client: MockClient((_) async => throw const SocketExceptionStub()),
        ),
      );
      expect(ok, isFalse);
    });

    test(
      'closes its http client whether the token is accepted or not',
      () async {
        final accepted = _TrackingClient(
          MockClient((_) async => http.Response('{"login":"me"}', 200)),
        );
        await validateForgeToken(
          const ForgeToken('t'),
          kind: ForgeKind.github,
          httpFor: (token) =>
              ForgeHttp(kind: ForgeKind.github, token: token, client: accepted),
        );
        expect(accepted.closed, isTrue);

        final rejected = _TrackingClient(
          MockClient((_) async => http.Response('', 401)),
        );
        await validateForgeToken(
          const ForgeToken('t'),
          kind: ForgeKind.github,
          httpFor: (token) =>
              ForgeHttp(kind: ForgeKind.github, token: token, client: rejected),
        );
        expect(rejected.closed, isTrue);
      },
    );

    test('closes its http client even when the request throws', () async {
      final thrown = _TrackingClient(
        MockClient((_) async => throw const SocketExceptionStub()),
      );
      await validateForgeToken(
        const ForgeToken('t'),
        kind: ForgeKind.github,
        httpFor: (token) =>
            ForgeHttp(kind: ForgeKind.github, token: token, client: thrown),
      );
      expect(thrown.closed, isTrue);
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
      'connecting with a token GitHub accepts, and the helper actually '
      'keeps it, stores it and clears the etag cache',
      (tester) async {
        // A helper with a memory, not _RecordingGit: this row must now read
        // the token back after approving it, and a stub that answers every
        // call with a blank success would make that read-back always see
        // nothing, so the success path could never be exercised.
        final git = _StoringCredentialGit();
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
            // Connecting here succeeds and the helper reads the token back,
            // so the row renders as connected and reaches the
            // refresh-interval control, which needs this.
            settingsProvider.overrideWith(
              (ref) => SettingsController(
                InMemorySettingsRepository(),
                const AppSettings(),
              ),
            ),
          ],
        );

        await tester.enterText(find.byType(TextField), 'ghp_new');
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        expect(
          git.stored,
          'ghp_new',
          reason: 'a validated token must be handed to the credential helper',
        );
        expect(cache.length, 0);
        expect(
          container.read(toastProvider).last.title,
          'Connected to GitHub.',
        );
        expect(container.read(toastProvider).last.kind, ToastKind.success);
        // Flushes the toast's own dismissal timer so it does not outlive the
        // widget tree the test tears down.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'connecting reports a saved token only after approve reports success',
      (tester) async {
        // The helper refuses to run credential approve at all (a non-zero
        // exit), so approve's own return value must be what stops the
        // success toast — a row that ignored it would say "Connected" here
        // just as before.
        final git = _FailingGit();
        final container = await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
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
          container.read(toastProvider).last.title,
          isNot('Connected to GitHub.'),
        );
        expect(container.read(toastProvider).last.kind, ToastKind.error);
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'connecting reports the token was not kept when approve succeeds but '
      'the helper does not actually store it',
      (tester) async {
        // approve exits zero (git accepted the request) but a following
        // fill finds nothing — exactly the silent-decline shape approve's
        // own docstring warns about, and the one a bare exit-code check
        // cannot detect.
        final git = _SilentlyDecliningGit();
        final container = await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('{"login":"me"}', 200)),
            ),
          ],
        );

        await tester.enterText(find.byType(TextField), 'ghp_new');
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        expect(git.approveCalls, 1);
        expect(git.fillCalls, greaterThanOrEqualTo(1));
        expect(
          container.read(toastProvider).last.title,
          'GitHub accepted the token, but nothing on this system kept it. '
          'Set up a git credential helper and try again.',
        );
        expect(container.read(toastProvider).last.kind, ToastKind.error);
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

        // The status line's own read of the account (a plain `credential
        // fill`, to say whether one is already connected) happens on every
        // build regardless of this attempt, but a rejected token must never
        // reach approve or reject.
        expect(
          git.calls,
          everyElement(equals(['credential', 'fill'])),
          reason:
              'a rejected token must never reach the credential helper '
              'to store it',
        );
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
            // Connecting below leaves the helper holding a token, so the row
            // renders as connected and reaches the refresh-interval control.
            settingsProvider.overrideWith(
              (ref) => SettingsController(
                InMemorySettingsRepository(),
                const AppSettings(),
              ),
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
            // A token is already on file, so the row starts out connected
            // and reaches the refresh-interval control.
            settingsProvider.overrideWith(
              (ref) => SettingsController(
                InMemorySettingsRepository(),
                const AppSettings(),
              ),
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

    testWidgets(
      'writing a credential lands in the same repository scope the read '
      'side looks in',
      (tester) async {
        // forgeTokenProvider — the read side every other forge feature goes
        // through — scopes its git-credential calls to the active
        // repository. A write landing in a different scope (e.g. the
        // process's own working directory, unscoped) stores a token this
        // app can never read back through the same repository.
        final git = _RecordingGit();
        await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            workspaceProvider.overrideWith((ref) {
              final c = WorkspaceController();
              c.openRepo('/repo');
              return c;
            }),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('{"login":"me"}', 200)),
            ),
          ],
        );

        await tester.enterText(find.byType(TextField), 'ghp_new');
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        final credentialCallIndexes = [
          for (var i = 0; i < git.calls.length; i++)
            if (git.calls[i].isNotEmpty && git.calls[i].first == 'credential')
              i,
        ];
        expect(
          credentialCallIndexes,
          isNotEmpty,
          reason: 'connecting must actually invoke git credential',
        );
        for (final i in credentialCallIndexes) {
          expect(git.repoPaths[i], '/repo');
        }
        // Flushes the toast's own dismissal timer so it does not outlive the
        // widget tree this test tears down.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets(
      'writing a credential with no repository open falls back to the '
      'global configuration, not the process working directory',
      (tester) async {
        final git = _RecordingGit();
        await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(git),
            forgeHttpClientProvider.overrideWithValue(
              MockClient((_) async => http.Response('{"login":"me"}', 200)),
            ),
          ],
        );

        await tester.enterText(find.byType(TextField), 'ghp_new');
        await tester.tap(find.text('Connect'));
        await tester.pump();
        await tester.pump();

        final credentialCallIndexes = [
          for (var i = 0; i < git.calls.length; i++)
            if (git.calls[i].isNotEmpty && git.calls[i].first == 'credential')
              i,
        ];
        expect(credentialCallIndexes, isNotEmpty);
        for (final i in credentialCallIndexes) {
          expect(git.repoPaths[i], isNull);
        }
        // Flushes the toast's own dismissal timer so it does not outlive the
        // widget tree this test tears down.
        await tester.pump(const Duration(seconds: 4));
      },
    );

    testWidgets('says when the account is connected', (tester) async {
      await _pump(
        tester,
        overrides: [
          gitServiceProvider.overrideWithValue(_RecordingGit()),
          forgeAccountTokenProvider.overrideWith(
            (ref, path) async => const ForgeToken('ghp_x'),
          ),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
      );
      await tester.pump();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Not connected'), findsNothing);
    });

    testWidgets('says when the account is not connected', (tester) async {
      await _pump(
        tester,
        overrides: [gitServiceProvider.overrideWithValue(_RecordingGit())],
      );
      await tester.pump();

      expect(find.text('Not connected'), findsOneWidget);
    });

    testWidgets(
      'stays connected for a repository whose own remote is not on GitHub',
      (tester) async {
        // A GitLab (or local, or remote-less) repository being active must
        // not hide a github.com token that is actually on file: this row is
        // about the account, not about whichever repository happens to be
        // open.
        await _pump(
          tester,
          overrides: [
            gitServiceProvider.overrideWithValue(_RecordingGit()),
            workspaceProvider.overrideWith((ref) {
              final c = WorkspaceController();
              c.openRepo('/repo');
              return c;
            }),
            forgeHostProvider.overrideWith((ref, path) async => null),
            forgeAccountTokenProvider.overrideWith(
              (ref, path) async => const ForgeToken('ghp_x'),
            ),
            settingsProvider.overrideWith(
              (ref) => SettingsController(
                InMemorySettingsRepository(),
                const AppSettings(),
              ),
            ),
          ],
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Connected'), findsOneWidget);
      },
    );

    testWidgets('each row explains its own forge budget', (tester) async {
      // The two sentences are not interchangeable: GitHub's quotes the
      // published 60/5,000 hourly figures and what one open costs against
      // them, and GitLab publishes no such numbers. Showing either under
      // the other heading tells the reader something untrue about the
      // account they are about to connect.
      for (final kind in ForgeKind.values) {
        await _pump(
          tester,
          kind: kind,
          overrides: [gitServiceProvider.overrideWithValue(_RecordingGit())],
        );
        await tester.pump();

        final l = AppLocalizations.of(
          tester.element(find.byType(ForgeAccountRow)),
        );
        final own = kind == ForgeKind.github
            ? l.forgeRateBenefit
            : l.forgeRateBenefitGitlab;
        final other = kind == ForgeKind.github
            ? l.forgeRateBenefitGitlab
            : l.forgeRateBenefit;

        expect(find.text(own), findsOneWidget, reason: '$kind');
        expect(find.text(other), findsNothing, reason: '$kind');
      }
    });

    testWidgets('the github row shows what is left of the hourly budget', (
      tester,
    ) async {
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
            (ref, path) async => const ForgeRateLimit(remaining: 12, limit: 60),
          ),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
      );
      await tester.pump();
      await tester.pump();

      final l = AppLocalizations.of(
        tester.element(find.byType(ForgeAccountRow)),
      );
      expect(find.text(l.forgeRateRemaining(12, 60)), findsOneWidget);
    });

    testWidgets('the gitlab row never shows github figures', (tester) async {
      // forgeRateLimitProvider answers for whichever repository is active,
      // and only GitHub publishes a free budget endpoint. Watching it from
      // the GitLab row would print a GitHub repository's remaining requests
      // under a GitLab account's heading.
      await _pump(
        tester,
        kind: ForgeKind.gitlab,
        overrides: [
          gitServiceProvider.overrideWithValue(_RecordingGit()),
          workspaceProvider.overrideWith((ref) {
            final c = WorkspaceController();
            c.openRepo('/repo');
            return c;
          }),
          forgeRateLimitProvider.overrideWith(
            (ref, path) async => const ForgeRateLimit(remaining: 12, limit: 60),
          ),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
      );
      await tester.pump();
      await tester.pump();

      final l = AppLocalizations.of(
        tester.element(find.byType(ForgeAccountRow)),
      );
      expect(find.text(l.forgeRateRemaining(12, 60)), findsNothing);
    });

    testWidgets('the gitlab row validates against gitlab', (tester) async {
      late Uri called;
      final client = _TrackingClient(
        MockClient((req) async {
          called = req.url;
          return http.Response('{}', 200);
        }),
      );
      await _pump(
        tester,
        kind: ForgeKind.gitlab,
        overrides: [
          gitServiceProvider.overrideWithValue(_StoringCredentialGit()),
          forgeHttpClientProvider.overrideWithValue(client),
        ],
      );

      await tester.enterText(find.byType(TextField), 'token');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(called.toString(), 'https://gitlab.com/api/v4/user');
      // pumpAndSettle only waits out animations, not the toast's own
      // auto-dismiss Timer — left pending, it fails the next test's
      // "no timers survived" invariant check instead of this one's.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('the gitlab row stores its token under gitlab.com', (
      tester,
    ) async {
      final git = _StoringCredentialGit();
      await _pump(
        tester,
        kind: ForgeKind.gitlab,
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          forgeHttpClientProvider.overrideWithValue(
            _TrackingClient(MockClient((_) async => http.Response('{}', 200))),
          ),
        ],
      );

      await tester.enterText(find.byType(TextField), 'token');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // The credential body the helper was asked to store must name
      // gitlab.com and the app's own account name, not github.com or an
      // anonymous entry that would match the user's own push credential.
      expect(git.lastRequest, contains('host=gitlab.com'));
      expect(git.lastRequest, contains('username=x-access-token'));
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('disconnecting the gitlab row names only gitlab', (
      tester,
    ) async {
      // An erase that names the wrong host — or no host — takes a
      // credential the user still needs with it.
      final git = _StoringCredentialGit();
      await _pump(
        tester,
        kind: ForgeKind.gitlab,
        overrides: [gitServiceProvider.overrideWithValue(git)],
      );

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(git.lastRequest, contains('host=gitlab.com'));
      expect(git.lastRequest, isNot(contains('github.com')));
      await tester.pump(const Duration(seconds: 4));
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

/// Wraps [_inner] to record whether [close] was called, since neither
/// [http.Client] nor [MockClient] exposes that on its own.
class _TrackingClient extends http.BaseClient {
  final http.Client _inner;
  bool closed = false;

  _TrackingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}
