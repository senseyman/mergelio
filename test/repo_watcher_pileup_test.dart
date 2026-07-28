import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/repo_data.dart';
import 'package:mergelio/state/repo_watcher.dart';
import 'package:mergelio/state/workspace.dart';

/// A repository whose read takes longer than the disk keeps quiet must not end
/// up with a stack of overlapping reads: twelve concurrent walks of the same
/// repository starve each other badly enough to hit the read timeout, which the
/// user sees as "Could not read repository".
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_pileup_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a stream of disk events cannot stack up repository reads', () async {
    var reads = 0;
    final c = ProviderContainer(
      overrides: [
        repoDataProvider.overrideWith((ref, path) async {
          reads++;
          // Slower than the gap between events below, so each new trigger lands
          // while the previous read is still running.
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          return const RepoData();
        }),
      ],
    );
    addTearDown(c.dispose);

    c.read(workspaceProvider.notifier).openRepo(dir.path);
    final sub = c.listen(repoDataProvider(dir.path), (_, _) {});
    addTearDown(sub.close);
    c.read(repoWatcherProvider);
    await c.read(repoDataProvider(dir.path).future);

    // One event per settle window: each one is far enough apart to fire the
    // debounce, yet lands while the previous read is still in flight.
    for (var i = 0; i < 6; i++) {
      await File('${dir.path}/f$i.txt').writeAsString('$i');
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    await Future<void>.delayed(const Duration(milliseconds: 2000));

    // One initial read plus a small number of refreshes. The defect produced
    // one read per event instead.
    expect(reads, lessThanOrEqualTo(4), reason: 'reads piled up: $reads');
  });
}
