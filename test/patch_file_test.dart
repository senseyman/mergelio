import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/patch_file.dart';

void main() {
  group('mailboxSubjects', () {
    test('lists each message subject without the [PATCH n/m] prefix', () {
      const mbox =
          'From 1111111111111111111111111111111111111111 Mon Sep 17 00:00:00 2001\n'
          'From: A <a@e.com>\n'
          'Subject: [PATCH 1/2] Fix the parser\n'
          '\n'
          'body\n'
          '---\n'
          ' f | 2 +-\n'
          'diff --git a/f b/f\n'
          '+Subject: not a header\n'
          'From 2222222222222222222222222222222222222222 Mon Sep 17 00:00:00 2001\n'
          'Subject: [PATCH 2/2] Add a test\n'
          '\n';
      expect(mailboxSubjects(mbox), ['Fix the parser', 'Add a test']);
    });

    test('joins a folded subject header', () {
      const mbox =
          'From abc Mon Sep 17 00:00:00 2001\n'
          'Subject: [PATCH] A rather long subject that git\n'
          ' folded onto a second line\n'
          'Date: x\n'
          '\n';
      expect(mailboxSubjects(mbox), [
        'A rather long subject that git folded onto a second line',
      ]);
    });

    test('keeps a bracketed subject that is not a patch tag', () {
      const mbox = 'From abc Mon Sep 17 00:00:00 2001\nSubject: [ui] Tweak\n\n';
      expect(mailboxSubjects(mbox), ['[ui] Tweak']);
    });

    test('is empty for a plain diff, even one adding a Subject line', () {
      const diff =
          'diff --git a/m b/m\n'
          '--- a/m\n'
          '+++ b/m\n'
          '@@ -1 +1,2 @@\n'
          ' x\n'
          '+Subject: hi\n';
      expect(mailboxSubjects(diff), isEmpty);
    });

    test('reads CRLF line endings', () {
      const mbox =
          'From abc Mon Sep 17 00:00:00 2001\r\nSubject: [PATCH] Hi\r\n\r\n';
      expect(mailboxSubjects(mbox), ['Hi']);
    });
  });

  group('parsePatchNumstat', () {
    test('reads counts and NUL-terminated paths, binary as null', () {
      final stats = parsePatchNumstat('1\t2\ta b.txt\x00-\t-\timg.png\x00');
      expect(stats.map((s) => (s.path, s.added, s.deleted)), [
        ('a b.txt', 1, 2),
        ('img.png', null, null),
      ]);
    });

    test('merges a path that several patches in a series touch', () {
      final stats = parsePatchNumstat('1\t1\tf\x002\t0\tf\x001\t0\tg\x00');
      expect(stats.map((s) => (s.path, s.added, s.deleted)), [
        ('f', 3, 1),
        ('g', 1, 0),
      ]);
    });

    test('is empty for empty output', () {
      expect(parsePatchNumstat(''), isEmpty);
    });
  });

  group('threeWayCheckOf', () {
    test('a failed check is unavailable', () {
      expect(
        threeWayCheckOf(
          const GitResult(1, '', 'error: f: does not match index'),
        ),
        ThreeWayCheck.unavailable,
      );
    });

    test('a passing check that reports conflicts is conflicts', () {
      expect(
        threeWayCheckOf(
          const GitResult(0, '', "Applied patch to 'f' with conflicts.\n"),
        ),
        ThreeWayCheck.conflicts,
      );
    });

    test('a quiet passing check is clean', () {
      expect(
        threeWayCheckOf(
          const GitResult(0, '', "Applied patch to 'f' cleanly."),
        ),
        ThreeWayCheck.clean,
      );
    });
  });

  group('PatchPreview.modes', () {
    PatchPreview preview({
      bool worktree = false,
      bool stage = false,
      ThreeWayCheck threeWay = ThreeWayCheck.unavailable,
    }) => PatchPreview(
      files: const [],
      subjects: const [],
      worktreeOk: worktree,
      stageOk: stage,
      threeWay: threeWay,
      error: '',
    );

    test('offers working tree first, then stage', () {
      expect(preview(worktree: true, stage: true).modes, [
        PatchMode.worktree,
        PatchMode.stage,
      ]);
    });

    test('leaves stage out when the index check failed', () {
      expect(preview(worktree: true).modes, [PatchMode.worktree]);
    });

    test('offers 3-way only when a direct apply fails', () {
      expect(preview(worktree: true, threeWay: ThreeWayCheck.clean).modes, [
        PatchMode.worktree,
      ]);
      expect(preview(threeWay: ThreeWayCheck.conflicts).modes, [
        PatchMode.threeWay,
      ]);
    });

    test('is empty when nothing applies', () {
      expect(preview().modes, isEmpty);
    });
  });
}
