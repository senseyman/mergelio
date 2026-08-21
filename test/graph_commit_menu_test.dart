import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/lane_layout.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/workspace.dart';
import 'package:mergelio/ui/graph/graph_view.dart';

Commit _c(String sha, {String body = ''}) => Commit(
  sha: sha,
  message: 'msg $sha',
  body: body,
  author: 'Tester',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: const [],
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

  Future<void> openMenu(WidgetTester tester, {String body = 'the body'}) async {
    final workspace = WorkspaceController()..openRepo('/r');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workspaceProvider.overrideWith((ref) => workspace),
          settingsProvider.overrideWith(
            (ref) => SettingsController(
              InMemorySettingsRepository(),
              const AppSettings(),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppTokens.dark()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GraphList(
              data: RepoData(
                commits: assignLanes([_c('aaa', body: body)]),
                branches: const [Branch(name: 'main', current: true)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = tester.getCenter(find.text('msg aaa'));
    final gesture = await tester.startGesture(row, buttons: kSecondaryButton);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('the menu offers editing and copying the message', (
    tester,
  ) async {
    await openMenu(tester);

    expect(find.text('Edit message…'), findsOneWidget);
    expect(find.text('Copy summary'), findsOneWidget);
    expect(find.text('Copy description'), findsOneWidget);
    expect(find.text('Copy message'), findsOneWidget);
    expect(find.text('Copy SHA'), findsOneWidget);
  });

  testWidgets('copy summary puts the subject line on the clipboard', (
    tester,
  ) async {
    await openMenu(tester);

    await tester.tap(find.text('Copy summary'));
    await tester.pumpAndSettle();

    expect(clipboard, 'msg aaa');
  });

  testWidgets('copy message joins subject and body', (tester) async {
    await openMenu(tester);

    await tester.tap(find.text('Copy message'));
    await tester.pumpAndSettle();

    expect(clipboard, 'msg aaa\n\nthe body');
  });

  testWidgets('a commit with no body offers no description copy', (
    tester,
  ) async {
    await openMenu(tester, body: '');

    expect(find.text('Copy summary'), findsOneWidget);
    expect(find.text('Copy description'), findsNothing);
    expect(find.text('Copy message'), findsNothing);
  });
}
