import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/data/settings_repository.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/domain/git/signature.dart';
import 'package:mergelio/domain/git/tag_info.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/graph_selection.dart';
import 'package:mergelio/state/lfs.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/settings.dart';
import 'package:mergelio/state/settings_controller.dart';
import 'package:mergelio/state/signatures.dart';
import 'package:mergelio/ui/workspace/commit_details.dart';

final _commit = Commit(
  sha: 'abcdef1234567890',
  message: 'feat: something',
  author: 'Tester',
  authorEmail: 't@example.com',
  date: DateTime(2026, 7, 2, 14, 33),
  parents: const ['1111111aaaa'],
);

Widget _harness({
  List<CommitFileChange>? files,
  bool hasWip = false,
  Commit? commit,
  String sigStatus = 'G',
  Map<String, SignatureVerdict> tags = const {},
  List<String>? verifiedTags,
  List<String>? signersReads,
  // Defaults to every tag in [tags], lightweight, as git would list them.
  List<TagInfo>? tagInfos,
  bool tagInfosFail = false,
  List<String>? tagInfoReads,
  Future<Set<String>> Function(Ref ref, LfsQuery q)? lfsPaths,
  GitService? git,
}) => ProviderScope(
  overrides: [
    if (git != null) gitServiceProvider.overrideWithValue(git),
    commitFilesProvider.overrideWith(
      (ref, key) async =>
          files ??
          const [CommitFileChange(path: 'x', change: GitChange.modified)],
    ),
    commitSignatureProvider.overrideWith(
      (ref, key) async => parseSignatureVerdict(sigStatus),
    ),
    tagSignatureProvider.overrideWith((ref, key) async {
      verifiedTags?.add(key.name);
      return tags[key.name] ?? SignatureVerdict.unsigned;
    }),
    tagInfosProvider.overrideWith((ref, key) async {
      tagInfoReads?.add(key.sha);
      if (tagInfosFail) throw StateError('cannot lock ref');
      return tagInfos ??
          [for (final n in tags.keys) TagInfo(name: n, annotated: false)];
    }),
    allowedSignersFileProvider.overrideWith((ref, repo) async {
      signersReads?.add(repo);
      return null;
    }),
    lfsLocksProvider.overrideWith((ref, p) async => LfsLockState.none),
    lfsPathsProvider.overrideWith(
      lfsPaths ?? (ref, q) async => const <String>{},
    ),
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
        commit:
            commit ??
            _commit.copyWith(
              refs: [
                for (final name in tags.keys)
                  GitRef(kind: RefKind.tag, name: name),
              ],
            ),
        hasWip: hasWip,
      ),
    ),
  ),
);

/// Answers the tool config read with a diff tool and records what ran.
class _ToolGit implements GitService {
  final calls = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> a, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    calls.add(a);
    if (a.first == 'config') return const GitResult(0, 'diff.tool\nx\x00', '');
    if (a.first == 'rev-parse') return const GitResult(0, '1111111aaaa\n', '');
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2';
  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  testWidgets('a changed file opens in the diff tool against its parent', (
    tester,
  ) async {
    final git = _ToolGit();
    await tester.pumpWidget(
      _harness(
        git: git,
        files: const [
          CommitFileChange(
            path: 'lib/new.dart',
            change: GitChange.renamed,
            origPath: 'lib/old.dart',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('lib/old.dart → lib/new.dart'),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Open in editor'), findsOneWidget);
    await tester.tap(find.text('Open in diff tool'));
    await tester.pumpAndSettle();
    expect(git.calls.where((c) => c.first == 'difftool').single, [
      'difftool',
      '--no-prompt',
      '-M',
      '1111111aaaa',
      'abcdef1234567890',
      '--',
      'lib/old.dart',
      'lib/new.dart',
    ]);
  });

  testWidgets('shows metadata, signature and changed files', (tester) async {
    await tester.pumpWidget(
      _harness(
        files: const [
          CommitFileChange(path: 'lib/a.dart', change: GitChange.added),
          CommitFileChange(
            path: 'lib/new.dart',
            change: GitChange.renamed,
            origPath: 'lib/old.dart',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('feat: something'), findsOneWidget);
    expect(find.text('Tester <t@example.com>'), findsOneWidget);
    expect(find.text('Jul 2, 2026 14:33'), findsOneWidget);
    expect(find.text('abcdef1'), findsOneWidget);
    expect(find.text('1111111'), findsOneWidget);
    expect(find.text('Verified signature'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('lib/old.dart → lib/new.dart'), findsOneWidget);
  });

  testWidgets('shows no signature row for an unsigned commit', (tester) async {
    await tester.pumpWidget(_harness(sigStatus: 'N'));
    await tester.pumpAndSettle();

    expect(find.text('feat: something'), findsOneWidget);
    expect(find.text('Verified signature'), findsNothing);
  });

  testWidgets('a signature that cannot be checked says so', (tester) async {
    await tester.pumpWidget(_harness(sigStatus: 'E'));
    await tester.pumpAndSettle();

    expect(find.text('Cannot verify signature'), findsOneWidget);
    expect(find.textContaining('Verified'), findsNothing);
  });

  testWidgets('each signed tag on the commit shows its own verdict', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        tags: const {
          'v1.0': SignatureVerdict(state: SignatureState.good),
          'v1.1': SignatureVerdict(state: SignatureState.bad),
          'lightweight': SignatureVerdict.unsigned,
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tag v1.0'), findsOneWidget);
    expect(find.text('Tag v1.1'), findsOneWidget);
    expect(find.text('Verified signature'), findsOneWidget);
    expect(find.text('Bad signature'), findsOneWidget);
    // An unsigned tag has nothing to say.
    expect(find.text('Tag lightweight'), findsNothing);
  });

  testWidgets('an annotated tag shows its tagger, date and message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        tags: const {'v2.0': SignatureVerdict.unsigned},
        tagInfos: [
          TagInfo(
            name: 'v2.0',
            annotated: true,
            tagger: 'Release Bot',
            taggerEmail: 'bot@example.com',
            date: DateTime.utc(2026, 10, 19, 10, 30),
            dateOffset: const Duration(hours: 1),
            subject: 'Version 2.0',
            body: 'Highlights:\n- signed tags',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tag v2.0'), findsOneWidget);
    expect(find.text('Release Bot <bot@example.com>'), findsOneWidget);
    // In the tagger's own offset, as commit dates are.
    expect(find.textContaining('Oct 19, 2026 11:30'), findsOneWidget);
    expect(
      find.text('Version 2.0\n\nHighlights:\n- signed tags'),
      findsOneWidget,
    );
    // Unsigned: no badge.
    expect(find.textContaining('signature'), findsNothing);
  });

  testWidgets('a signed tag shows its message under its verdict', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        tags: const {'v3': SignatureVerdict(state: SignatureState.good)},
        tagInfos: const [
          TagInfo(name: 'v3', annotated: true, tagger: 'T', subject: 'Three'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tag v3'), findsOneWidget);
    expect(find.text('Verified signature'), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
  });

  testWidgets('tags are read in one go, and not at all without tags', (
    tester,
  ) async {
    final reads = <String>[];
    await tester.pumpWidget(_harness(tagInfoReads: reads));
    await tester.pumpAndSettle();
    expect(reads, isEmpty);

    await tester.pumpWidget(
      _harness(
        tagInfoReads: reads,
        tags: const {
          'a': SignatureVerdict.unsigned,
          'b': SignatureVerdict.unsigned,
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, [_commit.sha]);
  });

  testWidgets('a tag added to the shown commit is read afresh', (tester) async {
    final reads = <String>[];
    await tester.pumpWidget(
      _harness(
        tagInfoReads: reads,
        tags: const {'a': SignatureVerdict.unsigned},
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _harness(
        tagInfoReads: reads,
        tags: const {
          'a': SignatureVerdict.unsigned,
          'b': SignatureVerdict.unsigned,
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, hasLength(2));
  });

  testWidgets('a tag without a recorded tagger shows no empty tagger line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        tags: const {'old': SignatureVerdict.unsigned},
        tagInfos: const [
          TagInfo(name: 'old', annotated: true, subject: 'Ancient'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ancient'), findsOneWidget);
    expect(find.text('Tagger'), findsNothing);
  });

  testWidgets('a commit with many tags verifies a bounded number', (
    tester,
  ) async {
    final verified = <String>[];
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        verifiedTags: verified,
        tags: {
          for (var i = 0; i < 8; i++)
            'pkg$i/v1': const SignatureVerdict(state: SignatureState.good),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(verified, hasLength(kMaxVerifiedTags));
    expect(find.text('Verify 3 more tags'), findsOneWidget);

    await tester.tap(find.text('Verify 3 more tags'));
    await tester.pumpAndSettle();
    expect(verified, hasLength(8));
    expect(find.textContaining('more tags'), findsNothing);
  });

  testWidgets('the allowed signers path git already named is not re-read', (
    tester,
  ) async {
    final reads = <String>[];
    await tester.pumpWidget(
      _harness(
        sigStatus:
            'U\x1f\x1fSHA256:abc\x1fSHA256:abc\x1f\x1fundefined\x1f'
            'Unable to open allowed keys file "/gone": No such file',
        signersReads: reads,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valid, untrusted key'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/gone'), findsOneWidget);
    expect(reads, isEmpty);
  });

  testWidgets('a commit without tags verifies no tag at all', (tester) async {
    final verified = <String>[];
    await tester.pumpWidget(_harness(verifiedTags: verified));
    await tester.pumpAndSettle();
    expect(verified, isEmpty);
  });

  testWidgets('a long signed tag name fits the narrowest panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(336, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        tags: const {
          'release/2026-10-05-a-really-long-tag-name': SignatureVerdict(
            state: SignatureState.unverifiable,
          ),
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cannot verify signature'), findsOneWidget);
  });

  testWidgets('shows the commit description body below the subject', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        commit: _commit.copyWith(
          body: 'Explains the why.\n\nSecond paragraph.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('feat: something'), findsOneWidget);
    expect(find.text('Explains the why.\n\nSecond paragraph.'), findsOneWidget);
  });

  testWidgets('WIP shortcut appears only when the tree is dirty and selects '
      'the WIP row', (tester) async {
    await tester.pumpWidget(_harness(hasWip: false));
    await tester.pumpAndSettle();
    expect(find.text('‹ WIP'), findsNothing);

    await tester.pumpWidget(_harness(hasWip: true));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CommitDetails)),
    );
    await tester.tap(find.text('‹ WIP'));
    await tester.pump();
    expect(container.read(selectedCommitProvider), wipSelection);
  });

  testWidgets('asks LFS about the diff against the first parent', (
    tester,
  ) async {
    final seen = <LfsQuery>[];
    await tester.pumpWidget(
      _harness(
        lfsPaths: (ref, q) async {
          seen.add(q);
          return const <String>{};
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty);
    final q = seen.first;
    expect(q.source.repoPath, '/repo');
    expect(q.source.rev, _commit.sha);
    expect(q.source.parentRev, _commit.parents.first);
    expect(q.paths, ['x']);
  });

  testWidgets('a root commit has no parent to diff against', (tester) async {
    final seen = <LfsQuery>[];
    await tester.pumpWidget(
      _harness(
        commit: _commit.copyWith(parents: const []),
        lfsPaths: (ref, q) async {
          seen.add(q);
          return const <String>{};
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(seen, isNotEmpty);
    expect(seen.first.source.parentRev, isNull);
  });

  testWidgets('a tag read that fails says so rather than hiding the tag', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        tags: const {'v1': SignatureVerdict.unsigned},
        tagInfosFail: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tag v1'), findsOneWidget);
    expect(find.text('Could not read this tag'), findsOneWidget);
  });

  testWidgets('a tag on the commit that git no longer lists still shows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        tags: const {'gone': SignatureVerdict.unsigned},
        tagInfos: const [TagInfo(name: 'other', annotated: false)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tag gone'), findsOneWidget);
    expect(find.text('Could not read this tag'), findsOneWidget);
  });

  testWidgets('a lightweight unsigned tag stays quiet once read', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        sigStatus: 'N',
        tags: const {'lw': SignatureVerdict.unsigned},
        tagInfos: const [TagInfo(name: 'lw', annotated: false)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tag lw'), findsNothing);
  });
}
