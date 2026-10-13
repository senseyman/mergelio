import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/blame.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/state/diff_view_options.dart';
import 'package:mergelio/state/file_insight.dart';

/// Answers every command with nothing and records the blame calls, so the
/// test reads the flags a set of options turns into.
class _RecordingGit implements GitService {
  final blames = <List<String>>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    if (args.first == 'blame') blames.add(args);
    return const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';

  @override
  Future<bool> isRepository(String path) async => true;
}

void main() {
  const key = (repo: '/r', path: 'a.txt', rev: null);

  ProviderContainer container(
    _RecordingGit git, {
    BlameRevsFile? revsFile,
    DiffViewOptions diff = const DiffViewOptions(),
  }) {
    final c = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        blameIgnoreRevsProvider('/r').overrideWith((ref) async => revsFile),
        diffViewOptionsProvider.overrideWith((ref) => diff),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<List<String>> blameArgs(ProviderContainer c, _RecordingGit git) async {
    final sub = c.listen(blameProvider(key), (_, _) {});
    addTearDown(sub.close);
    await c.read(blameProvider(key).future);
    return git.blames.last;
  }

  test('defaults: plain blame, the config file switched off', () async {
    final git = _RecordingGit();
    final args = await blameArgs(container(git), git);
    expect(args, isNot(contains('-w')));
    expect(args, isNot(contains('-M')));
    expect(args, isNot(contains('-C')));
    expect(args, contains('--no-ignore-revs-file'));
    expect(args, isNot(contains('--ignore-revs-file')));
  });

  test('a found revs file is skipped through by default', () async {
    final git = _RecordingGit();
    final args = await blameArgs(
      container(git, revsFile: (path: '/r/revs', invalid: null)),
      git,
    );
    expect(args.join(' '), contains('--ignore-revs-file /r/revs'));
  });

  test('switching skipping off leaves the found file out', () async {
    final git = _RecordingGit();
    final c = container(git, revsFile: (path: '/r/revs', invalid: null));
    c.read(blameOptionsProvider.notifier).state = c
        .read(blameOptionsProvider)
        .copyWith(skipIgnoredRevs: false);
    final args = await blameArgs(c, git);
    expect(args, isNot(contains('--ignore-revs-file')));
    expect(args, contains('--no-ignore-revs-file'));
  });

  test('a file git would refuse is never passed on', () async {
    final git = _RecordingGit();
    final c = container(git, revsFile: (path: '/r/revs', invalid: 'abc1234'));
    final args = await blameArgs(c, git);
    expect(args, isNot(contains('--ignore-revs-file')));
    expect(args, contains('--no-ignore-revs-file'));
  });

  test('whitespace and moves turn into their flags', () async {
    final git = _RecordingGit();
    final c = container(git);
    c.read(blameOptionsProvider.notifier).state = const BlameOptions(
      ignoreWhitespace: true,
      moves: BlameMoves.acrossFiles,
    );
    final args = await blameArgs(c, git);
    expect(args, containsAll(['-w', '-C']));
  });

  test('whitespace starts out as the diff sheet has it', () async {
    final git = _RecordingGit();
    final c = container(
      git,
      diff: const DiffViewOptions(whitespace: DiffWhitespace.ignoreAll),
    );
    expect(c.read(blameOptionsProvider).ignoreWhitespace, isTrue);
    expect(await blameArgs(c, git), contains('-w'));
  });

  test('after that the blame toggle is its own', () async {
    final git = _RecordingGit();
    final c = container(git);
    expect(c.read(blameOptionsProvider).ignoreWhitespace, isFalse);
    c.read(diffViewOptionsProvider.notifier).state = const DiffViewOptions(
      whitespace: DiffWhitespace.ignoreAll,
    );
    expect(c.read(blameOptionsProvider).ignoreWhitespace, isFalse);
  });

  group('BlameOptions', () {
    test('isDefault only for plain blame with skipping on', () {
      expect(const BlameOptions().isDefault, isTrue);
      expect(const BlameOptions(ignoreWhitespace: true).isDefault, isFalse);
      expect(
        const BlameOptions(moves: BlameMoves.withinFile).isDefault,
        isFalse,
      );
      expect(const BlameOptions(skipIgnoredRevs: false).isDefault, isFalse);
    });

    test('equality and copyWith', () {
      const a = BlameOptions(moves: BlameMoves.withinFile);
      expect(a.copyWith(), a);
      expect(a.copyWith(moves: BlameMoves.off), const BlameOptions());
      expect(a.hashCode, a.copyWith().hashCode);
    });
  });

  test('blameIgnoreRevsProvider reads through the reader', () async {
    // Real resolution is covered against git; here only the wiring.
    final c = ProviderContainer(
      overrides: [gitServiceProvider.overrideWithValue(_RecordingGit())],
    );
    addTearDown(c.dispose);
    expect(
      await c.read(blameIgnoreRevsProvider('/does/not/exist').future),
      isNull,
    );
  });
}
