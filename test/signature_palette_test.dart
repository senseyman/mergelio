import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/signature.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/signatures.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/shell/global_actions.dart';
import 'package:mergelio/ui/workspace/signature_audit_panel.dart';

class _FakeGit implements GitService {
  final calls = <String>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(args.join(' '));
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  testWidgets('the palette opens the signature check from the upstream', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final git = _FakeGit();
    final asked = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitServiceProvider.overrideWithValue(git),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
          repoDataProvider.overrideWith(
            (ref, path) async => const RepoData(
              branches: [
                Branch(name: 'main', current: true, upstream: 'origin/main'),
              ],
            ),
          ),
          signatureAuditProvider.overrideWith((ref, key) async {
            asked.add(key.base);
            return const SignatureAudit(
              checked: 0,
              truncated: false,
              unverified: [],
            );
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: [AppTokens.dark()]),
          home: Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => openGlobalPalette(ctx, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
    );
    container.read(workspaceProvider.notifier).openRepo('/r');
    await container.read(repoDataProvider('/r').future);
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check signatures…'));
    await tester.pumpAndSettle();

    final panel = tester.widget<SignatureAuditPanel>(
      find.byType(SignatureAuditPanel),
    );
    expect(panel.repoPath, '/r');
    expect(panel.initialBase, 'origin/main');
    expect(asked, ['origin/main']);
    expect(find.text('Signature check'), findsOneWidget);
  });
}
