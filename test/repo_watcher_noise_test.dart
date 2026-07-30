import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/repo_watcher.dart';

/// The watcher must ignore filesystem churn that git commands produce while
/// merely *reading* a repository. If it doesn't, the app's own refresh writes
/// `.git` transients, the watcher sees them, schedules another refresh, and the
/// repository reloads in a loop forever (observed: one reload every ~600ms on
/// small repos, every ~3.5s on large ones).
void main() {
  group('RepoWatcher.isNoise', () {
    test('ignores lock files under .git', () {
      expect(RepoWatcher.isNoise('/repo/.git/index.lock'), isTrue);
      expect(RepoWatcher.isNoise('/repo/.git/HEAD.lock'), isTrue);
      expect(RepoWatcher.isNoise('/repo/.git/config.lock'), isTrue);
      expect(RepoWatcher.isNoise('/repo/.git/refs/heads/main.lock'), isTrue);
      expect(RepoWatcher.isNoise('/repo/.git/shallow.lock'), isTrue);
    });

    test('ignores FETCH_HEAD (rewritten by every fetch, even a no-op one)', () {
      expect(RepoWatcher.isNoise('/repo/.git/FETCH_HEAD'), isTrue);
    });

    test('still reacts to real git state files', () {
      expect(RepoWatcher.isNoise('/repo/.git/index'), isFalse);
      expect(RepoWatcher.isNoise('/repo/.git/HEAD'), isFalse);
      expect(RepoWatcher.isNoise('/repo/.git/refs/heads/main'), isFalse);
      expect(RepoWatcher.isNoise('/repo/.git/MERGE_HEAD'), isFalse);
    });

    test('still reacts to lock files in the working tree', () {
      expect(RepoWatcher.isNoise('/repo/pubspec.lock'), isFalse);
      expect(RepoWatcher.isNoise('/repo/sub/package-lock.json'), isFalse);
    });

    test('keeps existing high-churn exclusions', () {
      expect(RepoWatcher.isNoise('/repo/.git/objects/ab/cdef'), isTrue);
      expect(RepoWatcher.isNoise('/repo/node_modules/x/y.js'), isTrue);
      expect(RepoWatcher.isNoise('/repo/build/out.bin'), isTrue);
    });
  });
}
