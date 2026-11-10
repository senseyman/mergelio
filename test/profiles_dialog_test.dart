import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/profiles.dart';
import 'package:mergelio/ui/profiles/profiles_dialog.dart';

/// The profiles manager: listing, choosing the active identity, and adding,
/// editing and deleting profiles through it.
void main() {
  const work = Profile(
    id: 'work',
    label: 'Work',
    name: 'Wendy Worker',
    email: 'wendy@corp.example',
    colorValue: 0xFF112233,
  );
  const home = Profile(
    id: 'home',
    label: 'Home',
    name: 'Wendy',
    email: 'wendy@home.example',
    colorValue: 0xFF445566,
  );

  late ProviderContainer c;

  Future<void> open(
    WidgetTester tester, [
    ProfilesState initial = const ProfilesState(),
  ]) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    c = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(
          (ref) => ProfilesController(InMemoryKeyValueStore(), initial),
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
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showProfilesDialog(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  ProfilesState state() => c.read(profilesProvider);

  Finder rowOf(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(ListTile));

  Future<void> fillForm(
    WidgetTester tester, {
    required String label,
    required String name,
    required String email,
  }) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), label);
    await tester.enterText(fields.at(1), name);
    await tester.enterText(fields.at(2), email);
    await tester.pump();
  }

  testWidgets('says so when there are no profiles', (tester) async {
    await open(tester);
    expect(
      find.text('No profiles yet. Add one to set your commit identity.'),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('lists each profile with its identity, marking the active one', (
    tester,
  ) async {
    await open(
      tester,
      const ProfilesState(profiles: [work, home], activeId: 'work'),
    );
    expect(find.text('Wendy Worker · wendy@corp.example'), findsOneWidget);
    expect(find.text('Wendy · wendy@home.example'), findsOneWidget);
    expect(
      find.descendant(
        of: rowOf('Work'),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rowOf('Work'), matching: find.text('Use')),
      findsNothing,
    );
    expect(
      find.descendant(of: rowOf('Home'), matching: find.text('Use')),
      findsOneWidget,
    );
  });

  testWidgets('Use makes a profile active', (tester) async {
    await open(
      tester,
      const ProfilesState(profiles: [work, home], activeId: 'work'),
    );
    await tester.tap(
      find.descendant(of: rowOf('Home'), matching: find.text('Use')),
    );
    await tester.pumpAndSettle();
    expect(state().activeId, 'home');
    expect(
      find.descendant(
        of: rowOf('Home'),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
  });

  testWidgets('adding the first profile makes it active', (tester) async {
    await open(tester);
    await tester.tap(find.text('Add profile'));
    await tester.pumpAndSettle();
    await fillForm(
      tester,
      label: 'Work',
      name: 'Wendy Worker',
      email: 'wendy@corp.example',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final added = state().profiles.single;
    expect(added.label, 'Work');
    expect(added.name, 'Wendy Worker');
    expect(added.email, 'wendy@corp.example');
    expect(state().activeId, added.id);
    expect(find.text('Wendy Worker · wendy@corp.example'), findsOneWidget);
  });

  testWidgets('each new profile gets the next colour', (tester) async {
    await open(tester, const ProfilesState(profiles: [work], activeId: 'work'));
    await tester.tap(find.text('Add profile'));
    await tester.pumpAndSettle();
    await fillForm(tester, label: 'Second', name: 'S', email: 's@x.example');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(state().profiles, hasLength(2));
    // One profile existed, so the second palette colour is used.
    expect(state().profiles.last.colorValue, 0xFF3DD68C);
    expect(state().activeId, 'work');
  });

  testWidgets('cancelling the add form adds nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Add profile'));
    await tester.pumpAndSettle();
    await fillForm(tester, label: 'X', name: 'X', email: 'x@x.example');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state().profiles, isEmpty);
  });

  testWidgets('editing keeps the id and colour, changing the identity', (
    tester,
  ) async {
    await open(
      tester,
      const ProfilesState(profiles: [work, home], activeId: 'work'),
    );
    await tester.tap(
      find.descendant(
        of: rowOf('Home'),
        matching: find.byIcon(Icons.edit_outlined),
      ),
    );
    await tester.pumpAndSettle();

    // The form opens filled in with the profile being edited.
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'Home');
    expect(
      tester.widget<TextField>(fields.at(2)).controller!.text,
      'wendy@home.example',
    );

    await fillForm(
      tester,
      label: 'Personal',
      name: 'W. Personal',
      email: 'me@home.example',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final edited = state().profiles.firstWhere((p) => p.id == 'home');
    expect(edited.label, 'Personal');
    expect(edited.name, 'W. Personal');
    expect(edited.email, 'me@home.example');
    expect(edited.colorValue, home.colorValue);
    expect(state().profiles, hasLength(2));
    expect(state().activeId, 'work');
  });

  testWidgets('delete asks first and removes on confirm', (tester) async {
    await open(
      tester,
      const ProfilesState(profiles: [work, home], activeId: 'work'),
    );
    await tester.tap(
      find.descendant(
        of: rowOf('Home'),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete profile Home?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(state().profiles.map((p) => p.id), ['work']);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('declining the delete keeps the profile', (tester) async {
    await open(
      tester,
      const ProfilesState(profiles: [work, home], activeId: 'work'),
    );
    await tester.tap(
      find.descendant(
        of: rowOf('Home'),
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(state().profiles, hasLength(2));
  });
}
