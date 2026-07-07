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
    final r = await _run([
      'log',
      '--all',
      '--topo-order',
      '--decorate=full',
      '-z',
      if (maxCount != null) '--max-count=$maxCount',
      '--pretty=format:%H$_fs%P$_fs%an$_fs%ae$_fs%aI$_fs%G?$_fs%D$_fs%s$_fs%b',
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
      final gcode = f[5];
      out.add(
        Commit(
          sha: f[0],
          parents: f[1].split(' ').where((s) => s.isNotEmpty).toList(),
          author: f[2],
          authorEmail: f[3],
          date: DateTime.parse(f[4]),
          signed: gcode.isNotEmpty && gcode != 'N' && gcode != 'E',
          refs: _parseRefs(f[6]),
          message: f[7],
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
      '--format=%(refname:short)\t%(HEAD)\t%(upstream:track)',
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

  Future<List<String>> tags() async {
    final r = await _run(['tag', '--sort=-creatordate']);
    if (!r.ok) throw GitException('git tag failed', r);
    return const LineSplitter()
        .convert(r.stdout)
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<Stash>> stashes() async {
    final r = await _run(['stash', 'list', '--format=%gd\t%gs']);
    if (!r.ok) throw GitException('git stash list failed', r);
    final out = <Stash>[];
    for (final line in const LineSplitter().convert(r.stdout)) {
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      out.add(
        tab < 0
            ? Stash(ref: line, message: '')
            : Stash(
                ref: line.substring(0, tab),
                message: line.substring(tab + 1),
              ),
      );
    }
    return out;
  }

  /// Working-tree changes via `status --porcelain=v2 -z`. Entries carry both
  /// staged ([WorkingFile.index]) and unstaged ([WorkingFile.worktree]) sides;
  /// renames also carry [WorkingFile.origPath].
  Future<List<WorkingFile>> status() async {
    final r = await _run(['status', '--porcelain=v2', '-z']);
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
        out.add(GitRef(kind: RefKind.remote, name: tok.substring(13)));
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
