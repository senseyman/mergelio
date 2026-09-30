import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/lfs.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/ui/common/change_file_row.dart';
import 'package:mergelio/ui/common/lfs_lock_chip.dart';
import 'package:mergelio/ui/workspace/working_tree_panel.dart';

class _Git implements GitService {
  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async => const GitResult(0, '', '');
  @override
  Future<String> version() async => 'git version 2.45.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        gitServiceProvider.overrideWithValue(_Git()),
        settingsProvider.overrideWith(
          (ref) => SettingsController(
            InMemorySettingsRepository(),
            const AppSettings(filesAsTree: false),
          ),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppTokens.dark()]),
        home: Scaffold(body: child),
      ),
    );

const _mine = LfsLock(id: '1', path: 'art.psd', owner: 'me');
final _theirs = LfsLock(
  id: '2',
  path: 'art.psd',
  owner: 'alice',
  lockedAt: DateTime.now().subtract(const Duration(days: 2)),
);

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  final tokens = AppTokens.dark();

  testWidgets('own lock reads "You" in the muted colour', (tester) async {
    await tester.pumpWidget(_app(LfsLockChip(lock: _mine, ours: true)));
    expect(find.text('You'), findsOneWidget);
    expect(find.text('me'), findsNothing);
    expect(_textColor(tester, 'You'), tokens.textMuted);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    // No lock time known: no dangling separator.
    expect(find.byTooltip('Locked by me'), findsOneWidget);
  });

  testWidgets("someone else's lock names the owner in the warning colour", (
    tester,
  ) async {
    await tester.pumpWidget(_app(LfsLockChip(lock: _theirs, ours: false)));
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('You'), findsNothing);
    expect(_textColor(tester, 'alice'), tokens.warning);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Tooltip && (w.message ?? '').startsWith('Locked by alice · '),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a row without a lock has no lock chip', (tester) async {
    const f = CommitFileChange(path: 'art.psd', change: GitChange.modified);
    await tester.pumpWidget(
      _app(ChangeFileRow(file: f, repoPath: '/r', onTap: () {}, lfs: true)),
    );
    expect(find.byType(LfsLockChip), findsNothing);
  });

  testWidgets('a locked LFS row shows the chip, an unlocked kind does not', (
    tester,
  ) async {
    const f = CommitFileChange(path: 'art.psd', change: GitChange.modified);
    await tester.pumpWidget(
      _app(
        ChangeFileRow(
          file: f,
          repoPath: '/r',
          onTap: () {},
          lfs: true,
          lock: _theirs,
        ),
      ),
    );
    expect(find.text('alice'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        ChangeFileRow(
          file: f,
          repoPath: '/r',
          onTap: () {},
          lfs: false,
          lock: _theirs,
        ),
      ),
    );
    expect(find.byType(LfsLockChip), findsNothing);
  });

  testWidgets('working tree marks only the locked path', (tester) async {
    await tester.pumpWidget(
      _app(
        const WorkingTreePanel(
          repoPath: '/r',
          data: RepoData(
            working: [
              WorkingFile(path: 'art.psd', worktree: GitChange.modified),
              WorkingFile(path: 'other.psd', worktree: GitChange.modified),
            ],
          ),
        ),
        overrides: [
          lfsPathsProvider.overrideWith((ref, q) async => q.paths.toSet()),
          lfsRepoProvider.overrideWith((ref, s) async => false),
          lfsLocksProvider.overrideWith(
            (ref, p) async => LfsLockState(
              ours: const [],
              theirs: [_theirs],
              available: true,
              stale: false,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LfsLockChip), findsOneWidget);
    final row = find.ancestor(
      of: find.byType(LfsLockChip),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: row, matching: find.text('art.psd')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('other.psd')),
      findsNothing,
    );
  });

  testWidgets('a locked path LFS does not manage gets no lock chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const WorkingTreePanel(
          repoPath: '/r',
          data: RepoData(
            working: [
              WorkingFile(path: 'art.psd', worktree: GitChange.modified),
            ],
          ),
        ),
        overrides: [
          lfsPathsProvider.overrideWith((ref, q) async => const <String>{}),
          lfsRepoProvider.overrideWith((ref, s) async => false),
          lfsLocksProvider.overrideWith(
            (ref, p) async => LfsLockState(
              ours: const [],
              theirs: [_theirs],
              available: true,
              stale: false,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LfsLockChip), findsNothing);
  });

  testWidgets('own lock in the working tree reads "You"', (tester) async {
    await tester.pumpWidget(
      _app(
        const WorkingTreePanel(
          repoPath: '/r',
          data: RepoData(
            working: [
              WorkingFile(path: 'art.psd', worktree: GitChange.modified),
            ],
          ),
        ),
        overrides: [
          lfsPathsProvider.overrideWith((ref, q) async => q.paths.toSet()),
          lfsRepoProvider.overrideWith((ref, s) async => false),
          lfsLocksProvider.overrideWith(
            (ref, p) async => const LfsLockState(
              ours: [_mine],
              theirs: [],
              available: true,
              stale: false,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('the panel reads the locks once however many rows', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      _app(
        WorkingTreePanel(
          repoPath: '/r',
          data: RepoData(
            working: [
              for (var i = 0; i < 6; i++)
                WorkingFile(path: 'f$i.psd', worktree: GitChange.modified),
            ],
          ),
        ),
        overrides: [
          lfsPathsProvider.overrideWith((ref, q) async => q.paths.toSet()),
          lfsRepoProvider.overrideWith((ref, s) async => false),
          lfsLocksProvider.overrideWith((ref, p) async {
            reads++;
            return LfsLockState.none;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1);
  });

  for (final width in [336.0, 480.0, 800.0]) {
    testWidgets('a 40 character owner does not overflow at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final owner = 'o' * 40;
      await tester.pumpWidget(
        _app(
          const WorkingTreePanel(
            repoPath: '/r',
            data: RepoData(
              working: [
                WorkingFile(path: 'art.psd', worktree: GitChange.modified),
              ],
            ),
          ),
          overrides: [
            lfsPathsProvider.overrideWith((ref, q) async => q.paths.toSet()),
            lfsRepoProvider.overrideWith((ref, s) async => false),
            lfsLocksProvider.overrideWith(
              (ref, p) async => LfsLockState(
                ours: const [],
                theirs: [LfsLock(id: '3', path: 'art.psd', owner: owner)],
                available: true,
                stale: false,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LfsLockChip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
