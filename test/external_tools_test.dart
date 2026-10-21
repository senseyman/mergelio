import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/external_tools.dart';
import 'package:mergelio/domain/git/diff.dart';

/// Handing a file to another program is all string work until the spawn: how
/// the user's command splits, where the file and line go, which directory
/// the executable comes from, and whether git has a tool to run at all. Kept
/// pure so every platform's answer is checkable without opening a window.
void main() {
  group('splitCommand', () {
    test('splits on runs of whitespace', () {
      expect(splitCommand('  code   -g  x '), ['code', '-g', 'x']);
    });

    test('keeps quoted words whole, either quote', () {
      expect(splitCommand('"/Apps/My Editor/bin/ed" \'a b\' c'), [
        '/Apps/My Editor/bin/ed',
        'a b',
        'c',
      ]);
    });

    test('joins a quoted part to the word around it', () {
      expect(splitCommand('--x="a b"c'), ['--x=a bc']);
    });

    test('a backslash escapes the next character outside single quotes', () {
      expect(
        splitCommand(
          r'a\ b "c\"d" '
          "'e\\f'",
        ),
        ['a b', 'c"d', r'e\f'],
      );
    });

    test('an empty quoted word is still a word', () {
      expect(splitCommand('a "" b'), ['a', '', 'b']);
    });

    test('nothing but whitespace is no words', () {
      expect(splitCommand('   '), isEmpty);
    });

    test('an unbalanced quote is refused', () {
      expect(() => splitCommand('code "x'), throwsFormatException);
      expect(() => splitCommand("code 'x"), throwsFormatException);
    });
  });

  group('editorInvocation', () {
    void expectInvocation(
      (String, List<String>) actual,
      String exe,
      List<String> args,
    ) {
      expect(actual.$1, exe);
      expect(actual.$2, args);
    }

    test('no command opens the file with the platform default', () {
      expectInvocation(editorInvocation('', '/r/a.txt', os: 'macos'), 'open', [
        '/r/a.txt',
      ]);
      expectInvocation(
        editorInvocation('  ', '/r/a.txt', os: 'linux'),
        'xdg-open',
        ['/r/a.txt'],
      );
      expectInvocation(
        editorInvocation('', r'C:\r\a.txt', os: 'windows'),
        'explorer',
        [r'C:\r\a.txt'],
      );
    });

    test('fills file and line inside words', () {
      expectInvocation(
        editorInvocation(kVsCodeEditor, '/r/a b.dart', line: 12, os: 'macos'),
        'code',
        ['-g', '/r/a b.dart:12'],
      );
      expectInvocation(
        editorInvocation(kIdeaEditor, '/r/a.dart', line: 3, os: 'linux'),
        'idea',
        ['--line', '3', '/r/a.dart'],
      );
    });

    test('line defaults to 1', () {
      expectInvocation(
        editorInvocation('ed +{line} {file}', '/f', os: 'macos'),
        'ed',
        ['+1', '/f'],
      );
    });

    test('appends the file when the command never names it', () {
      expectInvocation(editorInvocation('subl -n', '/f', os: 'macos'), 'subl', [
        '-n',
        '/f',
      ]);
    });

    test('the executable word is never substituted into', () {
      expectInvocation(
        editorInvocation('{file}', '/f', os: 'macos'),
        '{file}',
        ['/f'],
      );
    });

    test('a broken command is refused', () {
      expect(
        () => editorInvocation('code "x', '/f', os: 'macos'),
        throwsFormatException,
      );
      expect(
        () => editorInvocation('""', '/f', os: 'macos'),
        throwsFormatException,
      );
    });
  });

  group('toolSearchPath', () {
    test('appends the install dirs a GUI launch misses, in order', () {
      final path = toolSearchPath('/usr/bin:/bin', os: 'macos', home: '/U/me');
      final dirs = path.split(':');
      expect(dirs.take(2), ['/usr/bin', '/bin']);
      expect(
        dirs,
        containsAllInOrder([
          '/opt/homebrew/bin',
          '/usr/local/bin',
          '/U/me/.local/bin',
          '/U/me/bin',
        ]),
      );
      expect(
        dirs,
        contains(
          '/Applications/Visual Studio Code.app/Contents/Resources/app/bin',
        ),
      );
      expect(
        dirs,
        contains('/U/me/Library/Application Support/JetBrains/Toolbox/scripts'),
      );
    });

    test('does not repeat a dir already on PATH', () {
      final path = toolSearchPath(
        '/usr/local/bin/:/usr/bin',
        os: 'macos',
        home: '/U/me',
      );
      expect(path.split(':').where((d) => d.startsWith('/usr/local/bin')), [
        '/usr/local/bin/',
      ]);
    });

    test('linux gets its own dirs', () {
      final dirs = toolSearchPath(null, os: 'linux', home: '/h').split(':');
      expect(dirs, containsAll(['/h/.local/bin', '/snap/bin']));
      expect(dirs, isNot(contains('/opt/homebrew/bin')));
    });

    test('windows PATH is left alone', () {
      expect(
        toolSearchPath(r'C:\bin', os: 'windows', home: r'C:\Users\me'),
        r'C:\bin',
      );
    });
  });

  group('resolveExecutable', () {
    test('first PATH dir holding the name wins', () {
      final have = {'/b/code', '/c/code'};
      expect(
        resolveExecutable(
          'code',
          path: '/a:/b:/c',
          os: 'macos',
          exists: have.contains,
        ),
        '/b/code',
      );
    });

    test('a name found nowhere is null', () {
      expect(
        resolveExecutable(
          'code',
          path: '/a',
          os: 'macos',
          exists: (_) => false,
        ),
        isNull,
      );
    });

    test('a path is taken as given, if it exists', () {
      expect(
        resolveExecutable(
          '/x/ed',
          path: '/a',
          os: 'macos',
          exists: (p) => p == '/x/ed',
        ),
        '/x/ed',
      );
      expect(
        resolveExecutable(
          './ed',
          path: '/a',
          os: 'linux',
          exists: (_) => false,
        ),
        isNull,
      );
    });

    test('a leading ~/ is the home directory, as a shell would read it', () {
      expect(
        resolveExecutable(
          '~/bin/ed',
          path: '/a',
          os: 'macos',
          home: '/U/me',
          exists: (p) => p == '/U/me/bin/ed',
        ),
        '/U/me/bin/ed',
      );
      // Only a leading one, and only before a slash.
      expect(
        resolveExecutable(
          '~ed',
          path: '/a',
          os: 'linux',
          home: '/h',
          exists: (p) => p == '/a/~ed',
        ),
        '/a/~ed',
      );
    });

    test('windows tries each executable extension', () {
      expect(
        resolveExecutable(
          'code',
          path: r'C:\a;C:\vs\bin',
          os: 'windows',
          exists: (p) => p == r'C:\vs\bin\code.cmd',
        ),
        r'C:\vs\bin\code.cmd',
      );
    });

    test('windows keeps an extension the user gave', () {
      expect(
        resolveExecutable(
          'ed.exe',
          path: r'C:\a',
          os: 'windows',
          exists: (p) => p == r'C:\a\ed.exe',
        ),
        r'C:\a\ed.exe',
      );
    });
  });

  group('parseToolConfig', () {
    test('reads key/value records, last occurrence wins', () {
      final c = parseToolConfig(
        'merge.tool\nbc\x00diff.tool\nmeld\x00merge.tool\nkdiff3\x00'
        'mergetool.my.cmd\ncp "\$REMOTE" "\$MERGED"\x00',
      );
      expect(c.value('merge.tool'), 'kdiff3');
      expect(c.value('diff.tool'), 'meld');
      expect(c.value('mergetool.my.cmd'), r'cp "$REMOTE" "$MERGED"');
      expect(c.value('diff.guitool'), isNull);
    });

    test('a bare key has an empty value; empty output is empty', () {
      expect(parseToolConfig('diff.tool\x00').value('diff.tool'), '');
      expect(parseToolConfig('').value('diff.tool'), isNull);
    });
  });

  group('pickExternalTool', () {
    ExternalToolConfig cfg(Map<String, String> m) => ExternalToolConfig(m);

    test('diff.guitool runs with --gui', () {
      expect(
        pickExternalTool(
          cfg({'diff.guitool': 'meld', 'diff.tool': 'vimdiff'}),
          ToolKind.diff,
        ),
        const ToolReady('meld', gui: true),
      );
    });

    test('diff.tool, then merge.tool, without --gui', () {
      expect(
        pickExternalTool(
          cfg({'diff.tool': 'meld', 'merge.tool': 'bc'}),
          ToolKind.diff,
        ),
        const ToolReady('meld', gui: false),
      );
      expect(
        pickExternalTool(cfg({'merge.tool': 'bc'}), ToolKind.diff),
        const ToolReady('bc', gui: false),
      );
    });

    test('a merge never borrows the diff tool', () {
      expect(
        pickExternalTool(cfg({'diff.tool': 'meld'}), ToolKind.merge),
        const ToolMissing(),
      );
      expect(
        pickExternalTool(
          cfg({'merge.guitool': 'p4merge', 'merge.tool': 'bc'}),
          ToolKind.merge,
        ),
        const ToolReady('p4merge', gui: true),
      );
    });

    test('nothing set, or set empty, is missing', () {
      expect(pickExternalTool(cfg({}), ToolKind.diff), const ToolMissing());
      expect(
        pickExternalTool(cfg({'diff.tool': ' '}), ToolKind.diff),
        const ToolMissing(),
      );
    });

    test('a builtin terminal tool needs a terminal', () {
      for (final t in ['vimdiff', 'vimdiff2', 'nvimdiff', 'emerge']) {
        expect(
          pickExternalTool(cfg({'merge.tool': t}), ToolKind.merge),
          ToolNeedsTerminal(t),
        );
      }
      expect(
        pickExternalTool(cfg({'diff.tool': 'gvimdiff'}), ToolKind.diff),
        const ToolReady('gvimdiff', gui: false),
      );
    });

    test('a custom cmd under a terminal name is the user\'s own tool', () {
      expect(
        pickExternalTool(
          cfg({'diff.tool': 'vimdiff', 'difftool.vimdiff.cmd': 'meld \$LOCAL'}),
          ToolKind.diff,
        ),
        const ToolReady('vimdiff', gui: false),
      );
      // difftool falls back to the mergetool cmd for any tool name.
      expect(
        pickExternalTool(
          cfg({'merge.tool': 'vimdiff', 'mergetool.vimdiff.cmd': 'x'}),
          ToolKind.diff,
        ),
        const ToolReady('vimdiff', gui: false),
      );
      expect(
        pickExternalTool(
          cfg({'diff.tool': 'nvimdiff', 'mergetool.nvimdiff.cmd': 'x'}),
          ToolKind.diff,
        ),
        const ToolReady('nvimdiff', gui: false),
      );
      // mergetool never reads difftool.*.
      expect(
        pickExternalTool(
          cfg({'merge.tool': 'vimdiff', 'difftool.vimdiff.cmd': 'x'}),
          ToolKind.merge,
        ),
        const ToolNeedsTerminal('vimdiff'),
      );
    });
  });

  group('difftoolArgs', () {
    test('unstaged and staged working-tree changes', () {
      expect(difftoolArgs(path: 'a/b.txt'), [
        'difftool',
        '--no-prompt',
        '--',
        'a/b.txt',
      ]);
      expect(difftoolArgs(path: 'a', staged: true, gui: true), [
        'difftool',
        '--no-prompt',
        '--gui',
        '--cached',
        '--',
        'a',
      ]);
    });

    test('two revisions, with renames followed', () {
      expect(difftoolArgs(path: 'new', origPath: 'old', from: 'p', to: 'c'), [
        'difftool',
        '--no-prompt',
        '-M',
        'p',
        'c',
        '--',
        'old',
        'new',
      ]);
    });

    test('staged is meaningless between revisions', () {
      expect(
        difftoolArgs(path: 'x', from: 'p', to: 'c', staged: true),
        isNot(contains('--cached')),
      );
    });

    test('a path that looks like an option stays a path', () {
      expect(difftoolArgs(path: '-rf').last, '-rf');
      expect(difftoolArgs(path: '-rf').reversed.skip(1).first, '--');
    });
  });

  test('mergetoolArgs', () {
    expect(mergetoolArgs('x'), ['mergetool', '--no-prompt', '--', 'x']);
    expect(mergetoolArgs('x', gui: true), [
      'mergetool',
      '--no-prompt',
      '--gui',
      '--',
      'x',
    ]);
  });

  group('firstChangedLine', () {
    DiffLine ctx(int o, int n) =>
        DiffLine(type: DiffLineType.context, oldNo: o, newNo: n, text: '');
    DiffLine add(int n) => DiffLine(type: DiffLineType.add, newNo: n, text: '');
    DiffLine del(int o) => DiffLine(type: DiffLineType.del, oldNo: o, text: '');

    test('the first added line, past the leading context', () {
      expect(
        firstChangedLine([
          DiffHunk(
            header: '',
            oldStart: 10,
            newStart: 12,
            lines: [ctx(10, 12), ctx(11, 13), add(14)],
          ),
        ]),
        14,
      );
    });

    test('a deletion lands where the line used to be', () {
      expect(
        firstChangedLine([
          DiffHunk(
            header: '',
            oldStart: 4,
            newStart: 4,
            lines: [ctx(4, 4), del(5), ctx(6, 5)],
          ),
        ]),
        5,
      );
      expect(
        firstChangedLine([
          DiffHunk(header: '', oldStart: 1, newStart: 0, lines: [del(1)]),
        ]),
        1,
      );
    });

    test('no hunks is the top of the file', () {
      expect(firstChangedLine(const []), 1);
    });
  });

  group('mergetoolLeftovers', () {
    test('picks out the copies git makes of a file, and nothing else', () {
      expect(
        mergetoolLeftovers('src/a.txt', [
          'a.txt',
          'a_BACKUP_123.txt',
          'a_BASE_123.txt',
          'a_LOCAL_123.txt',
          'a_REMOTE_123.txt',
          'a_REMOTE_x.txt',
          'a_OTHER_1.txt',
          'b_BASE_1.txt',
          'a_BASE_1.md',
        ]),
        [
          'a_BACKUP_123.txt',
          'a_BASE_123.txt',
          'a_LOCAL_123.txt',
          'a_REMOTE_123.txt',
        ],
      );
    });

    test('a file without an extension, and one with dots in its name', () {
      expect(mergetoolLeftovers('Makefile', ['Makefile_BASE_9', 'Makefile']), [
        'Makefile_BASE_9',
      ]);
      expect(mergetoolLeftovers('a.b.c', ['a.b_LOCAL_7.c', 'a_LOCAL_7.b.c']), [
        'a.b_LOCAL_7.c',
      ]);
    });

    test('names that are only regexp-like are matched literally', () {
      expect(
        mergetoolLeftovers('a+(1).txt', [
          'a+(1)_BASE_2.txt',
          'aa(1)_BASE_2.txt',
        ]),
        ['a+(1)_BASE_2.txt'],
      );
    });
  });
}
