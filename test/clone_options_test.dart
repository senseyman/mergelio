import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/clone_options.dart';
import 'package:mergelio/domain/git/git_service.dart';

void main() {
  group('isLocalCloneSource', () {
    test('plain paths are local', () {
      expect(isLocalCloneSource('/srv/repo.git'), isTrue);
      expect(isLocalCloneSource('../sibling'), isTrue);
      expect(isLocalCloneSource('repo'), isTrue);
      expect(isLocalCloneSource(r'C:\repos\app'), isTrue);
      expect(isLocalCloneSource('C:/repos/app'), isTrue);
    });

    test('urls and scp-like ssh are not', () {
      expect(isLocalCloneSource('https://github.com/a/b.git'), isFalse);
      expect(isLocalCloneSource('file:///srv/repo.git'), isFalse);
      expect(isLocalCloneSource('ssh://git@host/a/b'), isFalse);
      expect(isLocalCloneSource('git@github.com:a/b.git'), isFalse);
      expect(isLocalCloneSource('host:repo'), isFalse);
    });

    test('a colon after the first slash is still a path', () {
      expect(isLocalCloneSource('./a:b'), isTrue);
      expect(isLocalCloneSource('/tmp/a:b'), isTrue);
    });
  });

  group('cloneArgs', () {
    test('defaults recurse submodules and separate the url', () {
      expect(cloneArgs('https://h/r.git', '/t', const CloneOptions()), [
        'clone',
        '--recurse-submodules',
        '--',
        'https://h/r.git',
        '/t',
      ]);
    });

    test('submodules off drops the flag', () {
      expect(
        cloneArgs('https://h/r', '/t', const CloneOptions(submodules: false)),
        ['clone', '--', 'https://h/r', '/t'],
      );
    });

    test('shallow keeps every branch unless single branch is asked', () {
      final args = cloneArgs(
        'https://h/r',
        '/t',
        const CloneOptions(depth: 3, submodules: false),
      );
      expect(args, containsAllInOrder(['--depth', '3', '--no-single-branch']));
      expect(args, isNot(contains('--single-branch')));
    });

    test('shallow single branch', () {
      final args = cloneArgs(
        'https://h/r',
        '/t',
        const CloneOptions(depth: 1, branch: 'dev', singleBranch: true),
      );
      expect(args, containsAllInOrder(['--depth', '1']));
      expect(args, containsAllInOrder(['--branch', 'dev', '--single-branch']));
      expect(args, isNot(contains('--no-single-branch')));
    });

    test('branch alone checks it out without narrowing', () {
      final args = cloneArgs(
        'https://h/r',
        '/t',
        const CloneOptions(branch: ' dev '),
      );
      expect(args, containsAllInOrder(['--branch', 'dev']));
      expect(args, isNot(contains('--single-branch')));
      expect(args, isNot(contains('--no-single-branch')));
    });

    test('blank branch is ignored', () {
      final args = cloneArgs(
        'https://h/r',
        '/t',
        const CloneOptions(branch: '  ', singleBranch: true),
      );
      expect(args, isNot(contains('--branch')));
      expect(args, contains('--single-branch'));
    });

    test('blobless adds the filter', () {
      expect(
        cloneArgs('https://h/r', '/t', const CloneOptions(blobless: true)),
        contains('--filter=blob:none'),
      );
    });

    test('shallow or blobless from a local path forces the transport', () {
      expect(
        cloneArgs('/srv/r', '/t', const CloneOptions(depth: 1)),
        contains('--no-local'),
      );
      expect(
        cloneArgs('/srv/r', '/t', const CloneOptions(blobless: true)),
        contains('--no-local'),
      );
      expect(
        cloneArgs('/srv/r', '/t', const CloneOptions()),
        isNot(contains('--no-local')),
      );
      expect(
        cloneArgs('https://h/r', '/t', const CloneOptions(depth: 1)),
        isNot(contains('--no-local')),
      );
    });

    test('url and target always come last, after --', () {
      final args = cloneArgs(
        '-oops',
        '/t',
        const CloneOptions(depth: 2, blobless: true, branch: 'x'),
      );
      expect(args.sublist(args.length - 3), ['--', '-oops', '/t']);
    });
  });

  group('CloneOptions.problem', () {
    test('defaults are valid', () {
      expect(const CloneOptions().problem, isNull);
    });

    test('depth must be positive', () {
      expect(const CloneOptions(depth: 0).problem, CloneProblem.badDepth);
      expect(const CloneOptions(depth: -2).problem, CloneProblem.badDepth);
      expect(const CloneOptions(depth: 1).problem, isNull);
    });

    test('branch must not look like an option or hold spaces', () {
      expect(const CloneOptions(branch: '-x').problem, CloneProblem.badBranch);
      expect(const CloneOptions(branch: 'a b').problem, CloneProblem.badBranch);
      expect(const CloneOptions(branch: 'feat/x').problem, isNull);
    });
  });

  group('parseDepth', () {
    test('positive integers only', () {
      expect(parseDepth('1'), 1);
      expect(parseDepth(' 50 '), 50);
      expect(parseDepth(''), isNull);
      expect(parseDepth('0'), isNull);
      expect(parseDepth('-1'), isNull);
      expect(parseDepth('1.5'), isNull);
      expect(parseDepth('abc'), isNull);
    });
  });

  group('branch names', () {
    bool ok(String b) => CloneOptions(branch: b).problem == null;

    test('rejects what git rejects', () {
      for (final bad in [
        'a..b',
        'a~1',
        'a^',
        'a:b',
        'a?',
        'a*',
        'a[b',
        r'a\b',
        'a.lock',
        'a/.b',
        '.a',
        'a/',
        'a.',
        '/a',
        'a//b',
        'a@{b',
        'a\tb',
      ]) {
        expect(ok(bad), isFalse, reason: bad);
      }
      for (final good in [
        '@',
        'feat/x',
        'v1.2',
        'a@b',
        'ü',
        'a.lock.b',
        'x.y/z',
      ]) {
        expect(ok(good), isTrue, reason: good);
      }
    });

    test('agrees with git check-ref-format', () async {
      const svc = SystemGitService();
      for (final name in [
        'feat/x',
        'a..b',
        'a~1',
        'a^',
        'a:b',
        'a?',
        'a*',
        'a[b',
        r'a\b',
        'a.lock',
        'a/.b',
        '.a',
        'a/',
        'a.',
        '/a',
        'a//b',
        'a@{b',
        '@',
        'a b',
        'v1.2',
        'a@b',
        'ü',
        'a.lock.b',
      ]) {
        final r = await svc.run(['check-ref-format', '--branch', name]);
        expect(ok(name), r.ok, reason: name);
      }
    });
  });
}
