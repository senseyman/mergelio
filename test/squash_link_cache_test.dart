import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/state/squash_link_cache.dart';

/// Squash-link inference spawns roughly five git subprocesses per branch, so on
/// a repository with many branches it dominates the time to open or refresh.
/// The cache exists to keep that cost proportional to what actually changed,
/// which these tests pin down: what it recomputes, and what it refuses to.
void main() {
  Branch b(String name, String tip, {bool current = false}) =>
      Branch(name: name, tip: tip, current: current);

  late SquashLinkCache cache;
  late List<List<String>> asked;

  /// Stands in for the reader. Records which branches it was asked about and
  /// links every branch whose name starts with `merged`.
  Future<List<SquashLink>> compute(List<Branch> branches, String into) async {
    asked.add([for (final x in branches) x.name]);
    return [
      for (final x in branches)
        if (x.name.startsWith('merged'))
          SquashLink(fromSha: x.tip, toSha: 'landing-$into'),
    ];
  }

  setUp(() {
    cache = SquashLinkCache();
    asked = [];
  });

  Future<List<SquashLink>> resolve(List<Branch> branches) =>
      cache.resolve(path: '/repo', branches: branches, compute: compute);

  test('infers every branch on the first load', () async {
    final links = await resolve([
      b('main', 'aaa', current: true),
      b('merged-one', 'bbb'),
      b('open', 'ccc'),
    ]);

    expect(asked, [
      ['main', 'merged-one', 'open'],
    ]);
    expect(links.map((l) => l.fromSha), ['bbb']);
  });

  test('reuses everything when nothing moved', () async {
    final branches = [b('main', 'aaa', current: true), b('merged-one', 'bbb')];
    await resolve(branches);
    asked.clear();

    final links = await resolve(branches);

    expect(asked, isEmpty, reason: 'no branch moved, so nothing to infer');
    expect(links.map((l) => l.fromSha), ['bbb']);
  });

  test('infers only the branch that was added', () async {
    await resolve([b('main', 'aaa', current: true), b('merged-one', 'bbb')]);
    asked.clear();

    final links = await resolve([
      b('main', 'aaa', current: true),
      b('merged-one', 'bbb'),
      b('merged-two', 'ddd'),
    ]);

    expect(asked, [
      ['merged-two'],
    ]);
    expect(links.map((l) => l.fromSha), ['bbb', 'ddd']);
  });

  test('infers only the branch whose tip moved', () async {
    await resolve([
      b('main', 'aaa', current: true),
      b('merged-one', 'bbb'),
      b('open', 'ccc'),
    ]);
    asked.clear();

    await resolve([
      b('main', 'aaa', current: true),
      b('merged-one', 'bbb'),
      b('open', 'ccc2'),
    ]);

    expect(asked, [
      ['open'],
    ]);
  });

  test('remembers that a branch has no link', () async {
    await resolve([b('main', 'aaa', current: true), b('open', 'ccc')]);
    asked.clear();

    final links = await resolve([
      b('main', 'aaa', current: true),
      b('open', 'ccc'),
    ]);

    expect(asked, isEmpty, reason: 'an absent link is still an answer');
    expect(links, isEmpty);
  });

  test(
    'reuses the inference when the checkout lands on the same commit',
    () async {
      // Creating a branch and checking it out leaves the new branch on the tip
      // the old one was already at. The inference only ever uses the current
      // branch as a revision, so the answer cannot have changed.
      await resolve([b('main', 'aaa', current: true), b('merged-one', 'bbb')]);
      asked.clear();

      final links = await resolve([
        b('main', 'aaa'),
        b('side', 'aaa', current: true),
        b('merged-one', 'bbb'),
      ]);

      expect(asked, isEmpty);
      expect(links.map((l) => l.fromSha), ['bbb']);
    },
  );

  test('re-infers everything once the current branch moves', () async {
    await resolve([b('main', 'aaa', current: true), b('merged-one', 'bbb')]);
    asked.clear();

    await resolve([b('main', 'aaa2', current: true), b('merged-one', 'bbb')]);

    expect(asked, [
      ['main', 'merged-one'],
    ], reason: 'every link is measured against the current tip');
  });

  test('drops branches that no longer exist', () async {
    await resolve([
      b('main', 'aaa', current: true),
      b('merged-one', 'bbb'),
      b('gone', 'ccc'),
    ]);
    asked.clear();

    final links = await resolve([
      b('main', 'aaa', current: true),
      b('merged-one', 'bbb'),
    ]);

    expect(asked, isEmpty);
    expect(links.map((l) => l.fromSha), ['bbb']);

    // The deleted branch is really gone, not merely filtered out of the answer.
    await resolve([
      b('main', 'aaa', current: true),
      b('merged-one', 'bbb'),
      b('gone', 'ccc'),
    ]);
    expect(asked, [
      ['gone'],
    ]);
  });

  test('keeps repositories apart', () async {
    await cache.resolve(
      path: '/one',
      branches: [b('main', 'aaa', current: true), b('merged-one', 'bbb')],
      compute: compute,
    );
    asked.clear();

    await cache.resolve(
      path: '/two',
      branches: [b('main', 'aaa', current: true), b('merged-one', 'bbb')],
      compute: compute,
    );

    expect(asked, [
      ['main', 'merged-one'],
    ]);
  });

  test('answers with no links when no branch is current', () async {
    final links = await resolve([b('main', 'aaa'), b('merged-one', 'bbb')]);

    expect(links, isEmpty);
    expect(asked, isEmpty, reason: 'there is nothing to measure against');
  });

  test('forgetting a repository makes the next load infer again', () async {
    final branches = [b('main', 'aaa', current: true), b('merged-one', 'bbb')];
    await resolve(branches);
    asked.clear();

    cache.forget('/repo');
    await resolve(branches);

    expect(asked, [
      ['main', 'merged-one'],
    ]);
  });
}
