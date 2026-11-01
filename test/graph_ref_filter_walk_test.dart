import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/graph_ref_filter.dart';

import 'support/hermetic_git.dart';

void main() {
  late Directory dir;
  const svc = HermeticGit();
  late Map<String, String> sha;

  Future<String> g(List<String> a) async {
    final r = await svc.run(a, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${a.join(' ')} failed: ${r.err}');
    return r.out;
  }

  Future<void> commit(String name) async {
    await File('${dir.path}/$name.txt').writeAsString('$name\n');
    await g(['add', '.']);
    await g(['commit', '-q', '-m', name]);
    sha[name] = await g(['rev-parse', 'HEAD']);
  }

  /// base ─ on-main (main)
  ///    ├─ on-feat (feat)
  ///    └─ on-other (other), plus a stash made on main.
  setUp(() async {
    sha = {};
    dir = await Directory.systemTemp.createTemp('mergelio_grf_');
    await g(['init', '-q', '-b', 'main']);
    await g(['config', 'user.email', 't@e.com']);
    await g(['config', 'user.name', 'T']);
    await commit('base');
    await g(['switch', '-q', '-c', 'feat']);
    await commit('on-feat');
    await g(['switch', '-q', '-c', 'other', 'main']);
    await commit('on-other');
    await g(['switch', '-q', 'main']);
    await commit('on-main');
    await File('${dir.path}/base.txt').writeAsString('dirty\n');
    await g(['stash', '-q']);
    sha['stash'] = await g(['rev-parse', 'stash@{0}']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<Set<String>> walk(GraphRefFilter filter) async {
    final page = await GitReader(svc, dir.path).commitPage(filter: filter);
    return {for (final c in page.commits) c.sha};
  }

  test('no filter shows every branch and the stash', () async {
    final shas = await walk(GraphRefFilter.none);
    expect(shas, containsAll(sha.values));
  });

  test('a hidden branch drops only the commits it alone reaches', () async {
    final shas = await walk(
      GraphRefFilter.none.toggleHidden('refs/heads/feat'),
    );
    expect(shas, isNot(contains(sha['on-feat'])));
    expect(shas, containsAll([sha['base'], sha['on-main'], sha['on-other']]));
  });

  test('a soloed branch shows its ancestry and nothing else', () async {
    final shas = await walk(GraphRefFilter.none.toggleSolo('refs/heads/feat'));
    expect(shas, {sha['base'], sha['on-feat']});
  });

  test('soloing a branch that no longer exists falls back to all', () async {
    final shas = await walk(
      GraphRefFilter.none
          .toggleSolo('refs/heads/gone')
          .toggleHidden('refs/heads/other'),
    );
    expect(shas, isNot(contains(sha['on-other'])));
    expect(shas, containsAll([sha['on-feat'], sha['on-main'], sha['stash']]));
  });

  test('a soloed branch now a folder of others falls back to all', () async {
    // `feat` soloed, then deleted, then reused as a folder: a lookup of
    // refs/heads/feat now lists refs/heads/feat/child instead.
    await g(['branch', '-D', 'feat']);
    await g(['branch', 'feat/child', 'other']);
    final shas = await walk(GraphRefFilter.none.toggleSolo('refs/heads/feat'));
    expect(shas, containsAll([sha['on-main'], sha['on-other'], sha['stash']]));
  });

  test('a remote-tracking branch hides and solos like a local one', () async {
    await g(['update-ref', 'refs/remotes/origin/feat', sha['on-feat']!]);
    await g(['branch', '-D', 'feat']);
    final hidden = await walk(
      GraphRefFilter.none.toggleHidden('refs/remotes/origin/feat'),
    );
    expect(hidden, isNot(contains(sha['on-feat'])));
    final soloed = await walk(
      GraphRefFilter.none.toggleSolo('refs/remotes/origin/feat'),
    );
    expect(soloed, {sha['base'], sha['on-feat']});
  });
}
