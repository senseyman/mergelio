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

Commit _c(String sha, {List<GitRef> refs = const []}) => Commit(
  sha: sha,
  message: 'msg $sha',
  body: '',
  author: 'Tester',
  authorEmail: 't@e',
  date: DateTime(2026, 7, 1),
  parents: const [],
  refs: refs,
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

  Future<void> pumpGraph(WidgetTester tester, List<Commit> commits) async {
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
                commits: assignLanes(commits),
                branches: const [Branch(name: 'main', current: true)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> rightClick(WidgetTester tester, Finder target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  final withBranch = [
    _c(
      'aaa',
      refs: const [GitRef(kind: RefKind.local, name: 'main')],
    ),
  ];

  testWidgets('the commit column menu also copies the row branch name', (
    tester,
  ) async {
    await pumpGraph(tester, withBranch);

    await rightClick(tester, find.text('msg aaa'));

    expect(find.text('Checkout this commit'), findsOneWidget);
    expect(find.text('Copy SHA'), findsOneWidget);
    expect(find.text('Copy «main»'), findsOneWidget);
  });

  testWidgets('the branch column opens the same menu as the commit column', (
    tester,
  ) async {
    await pumpGraph(tester, withBranch);

    await rightClick(tester, find.text('main'));

    expect(find.text('Checkout this commit'), findsOneWidget);
    expect(find.text('Copy SHA'), findsOneWidget);
    expect(find.text('Copy «main»'), findsOneWidget);
  });

  testWidgets('copying from the merged menu puts the branch name on the '
      'clipboard', (tester) async {
    await pumpGraph(tester, withBranch);

    await rightClick(tester, find.text('main'));
    await tester.tap(find.text('Copy «main»'));
    await tester.pumpAndSettle();

    expect(clipboard, 'main');
  });

  testWidgets('every branch on the row gets its own copy entry', (
    tester,
  ) async {
    await pumpGraph(tester, [
      _c(
        'aaa',
        refs: const [
          GitRef(kind: RefKind.local, name: 'main'),
          GitRef(kind: RefKind.local, name: 'release/1.7'),
        ],
      ),
    ]);

    await rightClick(tester, find.text('msg aaa'));

    expect(find.text('Copy «main»'), findsOneWidget);
    expect(find.text('Copy «release/1.7»'), findsOneWidget);
  });

  testWidgets('the branch copies lead the menu\'s copy group', (tester) async {
    await pumpGraph(tester, withBranch);

    await rightClick(tester, find.text('msg aaa'));

    expect(
      tester.getCenter(find.text('Copy «main»')).dy,
      lessThan(tester.getCenter(find.text('Copy summary')).dy),
    );
    expect(
      tester.getCenter(find.text('Copy «main»')).dy,
      greaterThan(tester.getCenter(find.text('Edit message…')).dy),
    );
  });

  testWidgets('the menu copies branches the overflow chip hides', (
    tester,
  ) async {
    // A row fits three chips, so four branches collapse the last two into +N.
    await pumpGraph(tester, [
      _c(
        'aaa',
        refs: const [
          GitRef(kind: RefKind.local, name: 'a'),
          GitRef(kind: RefKind.local, name: 'b'),
          GitRef(kind: RefKind.local, name: 'c'),
          GitRef(kind: RefKind.local, name: 'd'),
        ],
      ),
    ]);
    expect(find.text('+2'), findsOneWidget);

    await rightClick(tester, find.text('+2'));

    expect(find.text('Copy «a»'), findsOneWidget);
    expect(find.text('Copy «d»'), findsOneWidget);

    await tester.tap(find.text('Copy «d»'));
    await tester.pumpAndSettle();
    expect(clipboard, 'd');
  });

  testWidgets('a row with no branch label offers no branch copy entry', (
    tester,
  ) async {
    await pumpGraph(tester, [_c('aaa')]);

    await rightClick(tester, find.text('msg aaa'));

    expect(find.text('Copy SHA'), findsOneWidget);
    expect(find.textContaining('Copy «'), findsNothing);
  });
}
