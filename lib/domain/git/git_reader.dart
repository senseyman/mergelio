import 'dart:convert';

import 'git_service.dart';
import 'models.dart';

/// Reads a repository's refs, commits and working-tree state through a
/// [GitService] and parses the raw output into domain [models]. Kept separate
/// from [GitService] (a thin process runner) so the parsing is reusable if the
/// engine is swapped for libgit2.
class GitReader {
  final GitService git;
  final String repoPath;
  const GitReader(this.git, this.repoPath);

  static const _fs = '\x1f'; // field separator inside a record
  static const _rs = '\x00'; // record separator (git -z)

  Future<GitResult> _run(List<String> args) =>
      git.run(args, repoPath: repoPath);

  /// Commits across all refs in topological order, newest first. Layout fields
  /// are left at their defaults; run [assignLanes] to populate them. Returns an
  /// empty list for a repository with no commits yet.
  Future<List<Commit>> commits({int? maxCount}) async {
    // Stash commits live outside any ref `--all` walks, so fetch their shas and
    // pass them as extra revisions below; `stash@{0}` is already reachable via
    // `--all` but duplicate revs are harmless to `git log`.
    final stashList = await _run(['stash', 'list', '--format=%H']);
    final stashShas = stashList.ok
        ? const LineSplitter()
              .convert(stashList.stdout)
              .where((s) => s.isNotEmpty)
              .toList()
        : const <String>[];

    // A stash commit's 2nd/3rd parents are its internal index/untracked
    // snapshots; walking the stash pulls them in as nodes. Collect them so they
    // are dropped below — only the stash commit itself should show. This also
    // clears the pre-existing `stash@{0}` index/untracked leak from `--all`.
    final auxShas = <String>{};
    if (stashShas.isNotEmpty) {
      final rl = await _run([
        'rev-list',
        '--no-walk',
        '--parents',
        ...stashShas,
      ]);
      if (rl.ok) {
        for (final line in const LineSplitter().convert(rl.stdout)) {
          final toks = line.split(' ').where((s) => s.isNotEmpty).toList();
          // <stash> <base> <index> [<untracked>] — keep base, drop the rest.
          if (toks.length > 2) auxShas.addAll(toks.sublist(2));
        }
      }
    }

    final r = await _run([
      'log',
      '--all',
      '--topo-order',
      '--decorate=full',
      '-z',
      if (maxCount != null) '--max-count=$maxCount',
      '--pretty=format:%H$_fs%P$_fs%an$_fs%ae$_fs%aI$_fs%G?$_fs%D$_fs%s$_fs%b',
      ...stashShas,
    ]);
    if (!r.ok) {
      final e = r.err;
      // A repository with no commits yet (or an unborn HEAD) is not an error.
      if (e.contains('does not have any commits') ||
          e.contains('bad default revision') ||
          e.contains('bad revision')) {
        return const [];
      }
      throw GitException('git log failed', r);
    }

    final out = <Commit>[];
    for (final rec in r.stdout.split(_rs)) {
      final f = rec.split(_fs);
      if (f.length < 9) continue;
      if (auxShas.contains(f[0])) continue; // drop stash index/untracked nodes
      final gcode = f[5];
      out.add(
        Commit(
          sha: f[0],
          parents: f[1].split(' ').where((s) => s.isNotEmpty).toList(),
          author: f[2],
          authorEmail: f[3],
          date: DateTime.parse(f[4]),
          signed: gcode.isNotEmpty && gcode != 'N' && gcode != 'E',
          sigStatus: gcode.isEmpty ? 'N' : gcode,
          refs: _parseRefs(f[6]),
          message: f[7],
          body: f[8].trimRight(),
          coauthor: f[8].toLowerCase().contains('co-authored-by:'),
          avatarValue: _avatarFor(f[3]),
        ),
      );
    }
    return out;
  }

  /// Local branches with tracking info, in git's default (alphabetical) order.
  Future<List<Branch>> branches() async {
    final r = await _run([
      'for-each-ref',
      '--format=%(refname:short)\t%(HEAD)\t%(upstream:track)\t%(objectname)'
          '\t%(upstream:short)',
      'refs/heads',
    ]);
    if (!r.ok) throw GitException('git for-each-ref failed', r);
    final out = <Branch>[];
    var i = 0;
    for (final line in const LineSplitter().convert(r.stdout)) {
      if (line.isEmpty) continue;
      final p = line.split('\t');
      final track = p.length > 2 ? p[2] : '';
      out.add(
        Branch(
          name: p[0],
          current: p.length > 1 && p[1] == '*',
          ahead: _trackNum(track, 'ahead'),
          behind: _trackNum(track, 'behind'),
          ci: i % 8,
          tip: p.length > 3 ? p[3] : '',
          upstream: p.length > 4 ? p[4] : '',
        ),
      );
      i++;
    }
    return out;
  }

  Future<List<String>> remotes() async {
    final r = await _run(['remote']);
    if (!r.ok) throw GitException('git remote failed', r);
    return const LineSplitter()
        .convert(r.stdout)
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Remote-tracking branches (`refs/remotes/*`), excluding the `*/HEAD`
  /// symrefs. [hasLocal] flags branches that already have a local counterpart.
  Future<List<RemoteBranch>> remoteBranches() async {
    final results = await Future.wait([
      _run([
        'for-each-ref',
        '--format=%(refname:short)\t%(objectname)',
        'refs/remotes',
      ]),
      _run(['for-each-ref', '--format=%(refname:short)', 'refs/heads']),
    ]);
    if (!results[0].ok) {
      throw GitException('git for-each-ref refs/remotes failed', results[0]);
    }
    final locals = const LineSplitter().convert(results[1].stdout).toSet();
    final out = <RemoteBranch>[];
    for (final line in const LineSplitter().convert(results[0].stdout)) {
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      final short = tab < 0 ? line : line.substring(0, tab);
      final tip = tab < 0 ? '' : line.substring(tab + 1);
      final slash = short.indexOf('/');
      if (slash < 0) continue;
      final remote = short.substring(0, slash);
      final branch = short.substring(slash + 1);
      if (branch == 'HEAD') continue; // symref
      out.add(
        RemoteBranch(
          remote: remote,
          branch: branch,
          hasLocal: locals.contains(branch),
          tip: tip,
        ),
      );
    }
    return out;
  }

  /// Paths with unresolved merge conflicts (status filter U).
  Future<List<String>> conflictedFiles() async {
    final r = await _run(['diff', '--name-only', '--diff-filter=U', '-z']);
    if (!r.ok) throw GitException('git diff --diff-filter=U failed', r);
    return r.stdout.split(_rs).where((s) => s.isNotEmpty).toList();
  }

  /// Fetch URL configured for [remote], or empty if none.
  Future<String> remoteUrl(String remote) async {
    final r = await _run(['remote', 'get-url', remote]);
    return r.ok ? r.out : '';
  }

  /// Full message (subject + body) of HEAD, or empty in an unborn repo. Used
  /// to pre-fill the composer when amending.
  Future<String> lastCommitMessage() async {
    final r = await _run(['log', '-1', '--format=%B']);
    return r.ok ? r.stdout.trimRight() : '';
  }

  Future<List<String>> tags() async {
    final r = await _run(['tag', '--sort=-creatordate']);
    if (!r.ok) throw GitException('git tag failed', r);
    return const LineSplitter()
        .convert(r.stdout)
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<Stash>> stashes() async {
    final r = await _run(['stash', 'list', '--format=%gd\t%H\t%gs']);
    if (!r.ok) throw GitException('git stash list failed', r);
    final out = <Stash>[];
    for (final line in const LineSplitter().convert(r.stdout)) {
      if (line.isEmpty) continue;
      final p = line.split('\t');
      if (p.length < 2) continue;
      out.add(
        Stash(
          ref: p[0],
          sha: p[1],
          message: p.length > 2 ? p.sublist(2).join('\t') : '',
        ),
      );
    }
    return out;
  }

  /// Submodules of this repo: their recorded commit + status from
  /// `git submodule status`, enriched with url/branch/name from `.gitmodules`.
  /// Empty when the repo has no submodules.
  Future<List<Submodule>> submodules() async {
    final status = await _run(['submodule', 'status']);
    if (!status.ok || status.stdout.trim().isEmpty) return const [];

    // Metadata (name/url/branch) keyed by path, parsed from .gitmodules.
    final meta = <String, ({String name, String url, String? branch})>{};
    final cfg = await _run(['config', '-f', '.gitmodules', '-l', '-z']);
    if (cfg.ok) {
      final byName = <String, Map<String, String>>{};
      for (final rec in cfg.stdout.split(_rs)) {
        if (rec.isEmpty) continue;
        final nl = rec.indexOf('\n');
        if (nl < 0 || !rec.startsWith('submodule.')) continue;
        final key = rec.substring('submodule.'.length, nl);
        final dot = key.lastIndexOf('.');
        if (dot < 0) continue;
        (byName[key.substring(0, dot)] ??= {})[key.substring(dot + 1)] = rec
            .substring(nl + 1);
      }
      byName.forEach((name, m) {
        final p = m['path'];
        if (p != null) {
          meta[p] = (name: name, url: m['url'] ?? '', branch: m['branch']);
        }
      });
    }

    final out = <Submodule>[];
    for (final line in const LineSplitter().convert(status.stdout)) {
      if (line.isEmpty) continue;
      // '<char><sha> <path>[ (describe)]'
      final rest = line.substring(1);
      final sp = rest.indexOf(' ');
      if (sp < 0) continue;
      final sha = rest.substring(0, sp);
      final tail = rest.substring(sp + 1);
      final paren = tail.indexOf(' (');
      final path = (paren >= 0 ? tail.substring(0, paren) : tail).trim();
      final m = meta[path];
      out.add(
        Submodule(
          name: m?.name ?? path,
          path: path,
          url: m?.url ?? '',
          branch: m?.branch,
          sha: sha,
          status: submoduleStatusFromChar(line[0]),
        ),
      );
    }
    return out;
  }

  /// Working-tree changes via `status --porcelain=v2 -z`. Entries carry both
  /// staged ([WorkingFile.index]) and unstaged ([WorkingFile.worktree]) sides;
  /// renames also carry [WorkingFile.origPath]. `--untracked-files=all` lists
  /// each file inside a wholly-untracked directory instead of collapsing it to
  /// a single `dir/` entry, so the file tree can show and stage them.
  Future<List<WorkingFile>> status() async {
    final r = await _run([
      'status',
      '--porcelain=v2',
      '-z',
      '--untracked-files=all',
    ]);
    if (!r.ok) throw GitException('git status failed', r);
    final out = <WorkingFile>[];
    final toks = r.stdout.split(_rs);
    var i = 0;
    while (i < toks.length) {
      final e = toks[i];
      if (e.isEmpty) {
        i++;
        continue;
      }
      switch (e[0]) {
        case '1':
          final p = e.split(' ');
          out.add(
            WorkingFile(
              path: p.sublist(8).join(' '),
              index: _code(p[1][0]),
              worktree: _code(p[1][1]),
            ),
          );
          i++;
        case '2':
          final p = e.split(' ');
          out.add(
            WorkingFile(
              path: p.sublist(9).join(' '),
              index: _code(p[1][0]),
              worktree: _code(p[1][1]),
              origPath: i + 1 < toks.length ? toks[i + 1] : null,
            ),
          );
          i += 2; // rename/copy: the next token is the original path
        case 'u':
          final p = e.split(' ');
          out.add(
            WorkingFile(
              path: p.sublist(10).join(' '),
              index: GitChange.conflicted,
              worktree: GitChange.conflicted,
            ),
          );
          i++;
        case '?':
          out.add(
            WorkingFile(path: e.substring(2), worktree: GitChange.untracked),
          );
          i++;
        default: // '!' ignored, or anything unexpected
          i++;
      }
    }
    return out;
  }

  /// Unified diff of the unstaged changes to [path] (working tree vs index).
  Future<String> workingDiff(String path) async {
    final r = await _run(['diff', '--no-color', '--', path]);
    if (!r.ok) throw GitException('git diff failed', r);
    return r.stdout;
  }

  /// Unified diff of the staged changes to [path] (index vs HEAD).
  Future<String> stagedDiff(String path) async {
    final r = await _run(['diff', '--no-color', '--cached', '--', path]);
    if (!r.ok) throw GitException('git diff --cached failed', r);
    return r.stdout;
  }

  /// Full content of an untracked [path] rendered as an all-added diff, via
  /// `git diff --no-index` against /dev/null. That command exits 1 when there
  /// is a difference, which is expected here — not an error.
  Future<String> untrackedDiff(String path) async {
    final r = await _run([
      'diff',
      '--no-color',
      '--no-index',
      '--',
      '/dev/null',
      path,
    ]);
    return r.stdout;
  }

  /// Unified diff introduced by [sha] for [path], against its first parent.
  Future<String> commitDiff(String sha, String path) async {
    final r = await _run([
      'show',
      '--no-color',
      '--format=',
      '--first-parent',
      sha,
      '--',
      path,
    ]);
    if (!r.ok) throw GitException('git show failed', r);
    return r.stdout;
  }

  /// Commit history for [path], following renames (`git log --follow`).
  Future<List<Commit>> fileHistory(String path) async {
    final r = await _run([
      'log',
      '--follow',
      '--decorate=full',
      '-z',
      '--pretty=format:%H$_fs%P$_fs%an$_fs%ae$_fs%aI$_fs%G?$_fs%D$_fs%s$_fs%b',
      '--',
      path,
    ]);
    if (!r.ok) throw GitException('git log --follow failed', r);
    final out = <Commit>[];
    for (final rec in r.stdout.split(_rs)) {
      final f = rec.split(_fs);
      if (f.length < 9) continue;
      out.add(
        Commit(
          sha: f[0],
          parents: f[1].split(' ').where((s) => s.isNotEmpty).toList(),
          author: f[2],
          authorEmail: f[3],
          date: DateTime.parse(f[4]),
          message: f[7],
          avatarValue: _avatarFor(f[3]),
        ),
      );
    }
    return out;
  }

  /// Raw `git blame --line-porcelain` output for [path] (parse with
  /// [parseBlame]).
  Future<String> blame(String path) async {
    final r = await _run(['blame', '--line-porcelain', '--', path]);
    if (!r.ok) throw GitException('git blame failed', r);
    return r.stdout;
  }

  /// Files changed by [sha]. Merges are diffed against their first parent, so
  /// the list shows what the merged branch brought in.
  Future<List<CommitFileChange>> commitFiles(String sha) async {
    // `git show --first-parent` reports exactly the merge's own first-parent
    // changes; `diff-tree -m` instead unions the diff against every parent,
    // which for a merge pulls in files that only changed on the mainline. This
    // uses the same base as [commitDiff], so the list and per-file diff agree.
    final r = await _run([
      'show',
      '--no-color',
      '--format=',
      '--first-parent',
      '--name-status',
      '-z',
      sha,
    ]);
    if (!r.ok) throw GitException('git show failed', r);

    final out = <CommitFileChange>[];
    final toks = r.stdout.split(_rs);
    var i = 0;
    while (i + 1 < toks.length && toks[i].isNotEmpty) {
      final status = toks[i];
      final change = _code(status[0]);
      // Renames/copies (R100 etc.) carry two paths: original, then new.
      if (status[0] == 'R' || status[0] == 'C') {
        if (i + 2 >= toks.length) break;
        out.add(
          CommitFileChange(
            path: toks[i + 2],
            change: change,
            origPath: toks[i + 1],
          ),
        );
        i += 3;
      } else {
        out.add(CommitFileChange(path: toks[i + 1], change: change));
        i += 2;
      }
    }
    return out;
  }

  /// Squash-merge links from each branch (other than [into]) to the mainline
  /// commit that carries its squashed changes. A branch is considered squashed
  /// onto commit C when C is the first commit after their merge-base on the
  /// path to [into] and C has the same tree as the branch tip — i.e. C
  /// introduces exactly the branch's net change. Tree equality keeps this
  /// conservative: open branches and unrelated history are not linked.
  Future<List<SquashLink>> squashLinks(
    List<Branch> branches, {
    required String into,
  }) async {
    final results = await Future.wait([
      for (final b in branches)
        if (b.name != into) _squashLinkFor(b.name, into),
    ]);
    return results.whereType<SquashLink>().toList();
  }

  Future<String?> _revParse(String rev) async {
    final r = await _run(['rev-parse', '--verify', '--quiet', rev]);
    return r.ok && r.out.isNotEmpty ? r.out : null;
  }

  Future<SquashLink?> _squashLinkFor(String branch, String into) async {
    final tip = await _revParse(branch);
    if (tip == null) return null;

    final baseRes = await _run(['merge-base', into, branch]);
    if (!baseRes.ok || baseRes.out.isEmpty) return null;
    final base = baseRes.out;
    if (base == tip) return null; // already an ancestor of `into`

    final pathRes = await _run([
      'rev-list',
      '--reverse',
      '--ancestry-path',
      '$base..$into',
    ]);
    if (!pathRes.ok) return null;
    final landing = const LineSplitter()
        .convert(pathRes.stdout)
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (landing.isEmpty) return null;

    final tipTree = await _revParse('$tip^{tree}');
    final landingTree = await _revParse('$landing^{tree}');
    if (tipTree == null || tipTree != landingTree) return null;

    return SquashLink(fromSha: tip, toSha: landing);
  }

  static int _trackNum(String track, String key) {
    final m = RegExp('$key (\\d+)').firstMatch(track);
    return m == null ? 0 : int.parse(m.group(1)!);
  }

  static List<GitRef> _parseRefs(String d) {
    final out = <GitRef>[];
    if (d.trim().isEmpty) return out;
    for (var tok in d.split(',')) {
      tok = tok.trim();
      if (tok.isEmpty) continue;
      if (tok.startsWith('tag: ')) {
        out.add(
          GitRef(kind: RefKind.tag, name: _strip(tok.substring(5).trim())),
        );
        continue;
      }
      if (tok == 'HEAD') {
        out.add(const GitRef(kind: RefKind.head, name: 'HEAD'));
        continue;
      }
      if (tok.startsWith('HEAD -> ')) {
        out.add(const GitRef(kind: RefKind.head, name: 'HEAD'));
        tok = tok.substring(8).trim();
      }
      if (tok.startsWith('refs/heads/')) {
        out.add(GitRef(kind: RefKind.local, name: tok.substring(11)));
      } else if (tok.startsWith('refs/remotes/')) {
        final name = tok.substring(13);
        // Skip the `origin/HEAD` symref — it's noise, not a real branch.
        if (!name.endsWith('/HEAD')) {
          out.add(GitRef(kind: RefKind.remote, name: name));
        }
      } else if (tok.startsWith('refs/tags/')) {
        out.add(GitRef(kind: RefKind.tag, name: tok.substring(10)));
      } else {
        out.add(GitRef(kind: RefKind.local, name: tok));
      }
    }
    return out;
  }

  static String _strip(String ref) =>
      ref.startsWith('refs/tags/') ? ref.substring(10) : ref;

  static GitChange _code(String c) => switch (c) {
    '.' || ' ' => GitChange.none,
    'M' || 'T' => GitChange.modified,
    'A' => GitChange.added,
    'D' => GitChange.deleted,
    'R' => GitChange.renamed,
    'C' => GitChange.copied,
    'U' => GitChange.conflicted,
    '?' => GitChange.untracked,
    _ => GitChange.modified,
  };

  static const _avatarPalette = <int>[
    0xFF6C8CFF,
    0xFFF5C451,
    0xFF3DD68C,
    0xFFEB6F92,
    0xFF9D7CFF,
    0xFF4CC9F0,
    0xFFF08C4C,
    0xFF57C7A0,
  ];

  static int _avatarFor(String email) {
    var h = 0;
    for (final c in email.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _avatarPalette[h % _avatarPalette.length];
  }
}
