import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/forge/forge_credentials.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/forge/forge_host.dart';
import 'package:mergelio/domain/forge/forge_server.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/feedback.dart';
import 'package:mergelio/state/forge.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/preferences/forge_account_row.dart';

const _ghe = ForgeServer(kind: ForgeKind.github, host: 'ghe.corp', port: 8443);

/// A credential helper with a memory, per host: approve stores, fill reads
/// back, reject forgets. Every request body is kept so a test can see which
/// host it named.
class _Helper implements GitService {
  final stored = <String, String>{};
  final requests = <String>[];
  bool failErase = false;

  static String? _host(String body) =>
      RegExp(r'^host=(.*)$', multiLine: true).firstMatch(body)?.group(1);

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.length < 2 || args[0] != 'credential') {
      return const GitResult(1, '', 'unsupported');
    }
    final body = stdin ?? '';
    requests.add('${args[1]} $body');
    final host = _host(body);
    switch (args[1]) {
      case 'fill':
        final token = stored[host];
        return token == null
            ? const GitResult(1, '', '')
            : GitResult(0, 'password=$token\n\n', '');
      case 'approve':
        stored[host!] = parseCredentialReply(body)['password']!;
        return const GitResult(0, '', '');
      case 'reject':
        if (failErase) return const GitResult(1, '', 'refused');
        stored.remove(host);
        return const GitResult(0, '', '');
    }
    return const GitResult(1, '', 'unsupported');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

class _Harness {
  final ProviderContainer c;
  final _Helper helper;
  final List<http.Request> sent;
  _Harness(this.c, this.helper, this.sent);

  Map<String, String> get registered => c.read(settingsProvider).forgeServers;
  Toast get lastToast => c.read(toastProvider).last;
}

Future<_Harness> _pump(
  WidgetTester tester,
  Widget child, {
  int status = 200,
  AppSettings settings = const AppSettings(),
  _Helper? helper,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sent = <http.Request>[];
  final h = helper ?? _Helper();
  final c = ProviderContainer(
    overrides: [
      gitServiceProvider.overrideWithValue(h),
      settingsProvider.overrideWith(
        (ref) => SettingsController(InMemorySettingsRepository(), settings),
      ),
      forgeHttpClientProvider.overrideWithValue(
        MockClient((req) async {
          sent.add(req);
          return http.Response('{"login":"me"}', status);
        }),
      ),
    ],
  );
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: ListView(children: [child])),
      ),
    ),
  );
  await tester.pump();
  return _Harness(c, h, sent);
}

Future<void> _chooseSelfHosted(
  WidgetTester tester, {
  bool gitlab = false,
}) async {
  if (gitlab) {
    await tester.tap(find.text('GitLab'));
    await tester.pump();
  }
  await tester.tap(
    find.text(gitlab ? 'Self-managed GitLab' : 'GitHub Enterprise Server'),
  );
  await tester.pump();
}

Future<void> _submit(
  WidgetTester tester, {
  String? url,
  String token = 't',
}) async {
  if (url != null) {
    await tester.enterText(find.byKey(const ValueKey('forge-server-url')), url);
  }
  await tester.enterText(find.byKey(const ValueKey('forge-token')), token);
  await tester.tap(find.text('Connect'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  group('adding an account', () {
    testWidgets('github.com asks for no address', (tester) async {
      await _pump(tester, const ForgeTokenForm());

      expect(find.byKey(const ValueKey('forge-server-url')), findsNothing);
      await _chooseSelfHosted(tester);
      expect(find.byKey(const ValueKey('forge-server-url')), findsOneWidget);
    });

    testWidgets(
      'a github enterprise server is validated on its own api, then stored '
      'under host and port, and registered',
      (tester) async {
        final h = await _pump(tester, const ForgeTokenForm());
        await _chooseSelfHosted(tester);

        await _submit(tester, url: 'ghe.corp:8443', token: 'ghe-token');

        expect(
          h.sent.single.url.toString(),
          'https://ghe.corp:8443/api/v3/user',
        );
        expect(h.sent.single.headers['Authorization'], 'Bearer ghe-token');
        expect(h.helper.stored, {'ghe.corp:8443': 'ghe-token'});
        expect(h.registered, {'ghe.corp:8443': 'github'});
        expect(h.lastToast.kind, ToastKind.success);
        expect(h.lastToast.title, contains('ghe.corp:8443'));
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets('a self-managed gitlab uses its own /api/v4 and gitlab auth', (
      tester,
    ) async {
      final h = await _pump(tester, const ForgeTokenForm());
      await _chooseSelfHosted(tester, gitlab: true);

      await _submit(tester, url: 'https://git.corp/', token: 'glpat');

      expect(h.sent.single.url.toString(), 'https://git.corp/api/v4/user');
      expect(h.sent.single.headers['PRIVATE-TOKEN'], 'glpat');
      expect(h.sent.single.headers.containsKey('Authorization'), isFalse);
      expect(h.helper.stored, {'git.corp': 'glpat'});
      expect(h.registered, {'git.corp': 'gitlab'});
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('gitlab.com is stored under gitlab.com and never registered', (
      tester,
    ) async {
      final h = await _pump(tester, const ForgeTokenForm());
      await tester.tap(find.text('GitLab'));
      await tester.pump();

      await _submit(tester, token: 'glpat');

      expect(h.sent.single.url.toString(), 'https://gitlab.com/api/v4/user');
      expect(h.helper.stored, {'gitlab.com': 'glpat'});
      expect(h.registered, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('plain http is refused before the token goes anywhere', (
      tester,
    ) async {
      final h = await _pump(tester, const ForgeTokenForm());
      await _chooseSelfHosted(tester);

      await _submit(tester, url: 'http://ghe.corp');

      expect(find.textContaining('Only https is supported'), findsOneWidget);
      expect(h.sent, isEmpty);
      expect(h.helper.requests, isEmpty);
      expect(h.registered, isEmpty);
    });

    testWidgets('the public cloud typed as self-hosted is pointed back', (
      tester,
    ) async {
      final h = await _pump(tester, const ForgeTokenForm());
      await _chooseSelfHosted(tester);

      await _submit(tester, url: 'https://github.com');

      expect(find.textContaining('That is the public service'), findsOneWidget);
      expect(h.sent, isEmpty);
    });

    testWidgets('a sub-path install is refused with its own reason', (
      tester,
    ) async {
      final h = await _pump(tester, const ForgeTokenForm());
      await _chooseSelfHosted(tester, gitlab: true);

      await _submit(tester, url: 'https://corp.example/gitlab');

      expect(find.textContaining('sub-path'), findsOneWidget);
      expect(h.sent, isEmpty);
    });

    testWidgets('a token the server refuses is neither stored nor registers', (
      tester,
    ) async {
      final h = await _pump(tester, const ForgeTokenForm(), status: 401);
      await _chooseSelfHosted(tester);

      await _submit(tester, url: 'ghe.corp:8443');

      expect(h.helper.stored, isEmpty);
      expect(h.registered, isEmpty);
      expect(h.lastToast.kind, ToastKind.error);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('a self-hosted account row', () {
    const registered = AppSettings(forgeServers: {'ghe.corp:8443': 'github'});

    testWidgets('Remove forgets the token and the server', (tester) async {
      final helper = _Helper()..stored['ghe.corp:8443'] = 'x';
      final h = await _pump(
        tester,
        const ForgeAccountRow(server: _ghe),
        settings: registered,
        helper: helper,
      );

      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump();

      expect(h.helper.stored, isEmpty);
      expect(h.helper.requests.last, contains('host=ghe.corp:8443\n'));
      expect(h.registered, isEmpty);
      expect(h.lastToast.kind, ToastKind.success);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a Remove whose erase fails keeps the server listed', (
      tester,
    ) async {
      final helper = _Helper()
        ..stored['ghe.corp:8443'] = 'x'
        ..failErase = true;
      final h = await _pump(
        tester,
        const ForgeAccountRow(server: _ghe),
        settings: registered,
        helper: helper,
      );

      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump();

      // A server dropped while its token stayed in the helper would leave a
      // secret behind that nothing in the app shows any more.
      expect(h.registered, registered.forgeServers);
      expect(h.lastToast.kind, ToastKind.error);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Disconnect forgets the token but keeps the server', (
      tester,
    ) async {
      final helper = _Helper()..stored['ghe.corp:8443'] = 'x';
      final h = await _pump(
        tester,
        const ForgeAccountRow(server: _ghe),
        settings: registered,
        helper: helper,
      );

      await tester.tap(find.text('Disconnect'));
      await tester.pump();
      await tester.pump();

      expect(h.helper.stored, isEmpty);
      expect(h.registered, registered.forgeServers);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('says connected for a token on file under host and port', (
      tester,
    ) async {
      await _pump(
        tester,
        const ForgeAccountRow(server: _ghe),
        settings: registered,
        helper: _Helper()..stored['ghe.corp:8443'] = 'x',
      );
      await tester.pump();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Replace token…'), findsOneWidget);
      // A self-hosted server sets its own limits; the clouds' published
      // figures would be a guess here.
      expect(find.textContaining('60 requests an hour'), findsNothing);
    });
  });
}
