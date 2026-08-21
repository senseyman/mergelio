import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/workspace/commit_details.dart';

Commit _commit({String body = 'Why it changed.\nSecond line.'}) => Commit(
  sha: 'abcdef1234567890',
  message: 'feat: something',
  body: body,
  author: 'Tester',
  authorEmail: 't@example.com',
  date: DateTime(2026, 7, 2, 14, 33),
  parents: const ['1111111aaaa'],
);

void main() {
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(WidgetTester tester, {Commit? commit}) async {
    final workspace = WorkspaceController()..openRepo('/repo');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith((ref) => workspace),
          commitFilesProvider.overrideWith((ref, key) async => const []),
          commitSignatureProvider.overrideWith((ref, key) async => 'N'),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(filesAsTree: false),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CommitDetails(
              repoPath: '/repo',
              commit: commit ?? _commit(),
              hasWip: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapTooltip(WidgetTester tester, String message) async {
    await tester.tap(find.byTooltip(message));
    await tester.pumpAndSettle();
  }

  testWidgets('copies the summary alone', (tester) async {
    await pump(tester);
    await tapTooltip(tester, 'Copy summary');
    expect(clipboard, 'feat: something');
  });

  testWidgets('copies the description alone', (tester) async {
    await pump(tester);
    await tapTooltip(tester, 'Copy description');
    expect(clipboard, 'Why it changed.\nSecond line.');
  });

  testWidgets('copies the full message with its blank separator line', (
    tester,
  ) async {
    await pump(tester);
    await tapTooltip(tester, 'Copy message');
    expect(clipboard, 'feat: something\n\nWhy it changed.\nSecond line.');
  });

  testWidgets('offers no description copy when the commit has no body', (
    tester,
  ) async {
    await pump(tester, commit: _commit(body: ''));

    expect(find.byTooltip('Copy summary'), findsOneWidget);
    expect(find.byTooltip('Copy description'), findsNothing);
    expect(find.byTooltip('Copy message'), findsNothing);
  });

  testWidgets('the edit button opens the message dialog pre-filled', (
    tester,
  ) async {
    await pump(tester);
    await tapTooltip(tester, 'Edit message…');

    expect(find.text('Edit commit message'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'feat: something'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Why it changed.\nSecond line.'),
      findsOneWidget,
    );
  });
}
