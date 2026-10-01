import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/kv_store.dart';
import 'package:mergelio/domain/git/git_providers.dart';
import 'package:mergelio/domain/git/git_service.dart';
import 'package:mergelio/domain/git/maintenance.dart';
import 'package:mergelio/state/maintenance.dart';
import 'package:mergelio/state/operation_journal.dart';

/// Scripts git by exact argument list. A key in [gates] holds that call until
/// the completer finishes, so a test can act while a scan is running.
class _FakeGit implements GitService {
  final responses = <String, GitResult>{};
  final gates = <String, Completer<void>>{};
  final calls = <String>[];

  @override
  Future<GitResult> run(
    List<String> args, {
    String? repoPath,
    Duration? timeout,
    Map<String, String>? environment,
    GitCancel? cancel,
    String? stdin,
  }) async {
    final key = args.join(' ');
    calls.add(key);
    final gate = gates[key];
    if (gate != null) await gate.future;
    if (cancel?.isCancelled ?? false) {
      throw GitCancelledException('git $key cancelled');
    }
    return responses[key] ?? const GitResult(0, '', '');
  }

  @override
  Future<String> version() async => 'git version 2.55.0';
  @override
  Future<bool> isRepository(String path) async => true;
}

const _refsKey = 'for-each-ref --format=%(objectname) %(refname)';
const _listKey = 'cat-file --batch-all-objects --batch-check=$allObjectsFormat';

void main() {
  late _FakeGit git;
  late InMemoryKeyValueStore kv;
  late ProviderContainer container;

  setUp(() {
    git = _FakeGit();
    kv = InMemoryKeyValueStore();
    git.responses[_refsKey] = const GitResult(0, 'a refs/heads/main\n', '');
    git.responses[_listKey] = GitResult(0, 'blob ${'b' * 40} 99\n', '');
    git.responses['log --all --reverse --format=$blobOriginFormat '
        '--name-only --find-object=${'b' * 40}'] = const GitResult(
      0,
      'c\x1fc\x1f2026-01-01T00:00:00Z\x1fs\n\nbig.bin\n',
      '',
    );
    container = ProviderContainer(
      overrides: [
        gitServiceProvider.overrideWithValue(git),
        kvStoreProvider.overrideWithValue(kv),
        maintenanceClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 9, 30, 12),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  BlobScanState state() => container.read(blobScanProvider('/r'));
  BlobScanController ctl() => container.read(blobScanProvider('/r').notifier);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('starts idle with nothing cached', () async {
    ctl();
    await settle();
    expect(state().result, isNull);
    expect(state().scanning, isFalse);
  });

  test('a scan stores its result and caches it per repository', () async {
    await ctl().scan();
    expect(state().result!.blobs.single.blob.path, 'big.bin');
    expect(state().stale, isFalse);
    final cached = await kv.get('maintenance:blobs:/r');
    expect(
      BlobScan.fromJson(jsonDecode(cached!) as Map<String, dynamic>)
          .blobs
          .single
          .blob
          .size,
      99,
    );
  });

  test('a cached scan loads on first read and is not rerun', () async {
    await kv.put(
      'maintenance:blobs:/r',
      jsonEncode(
        BlobScan(
          scannedAt: '2026-09-01T00:00:00.000Z',
          fingerprint: refsFingerprint('a refs/heads/main\n'),
          blobs: const [BigBlob(BlobEntry(sha: 's', size: 1, path: 'p'), null)],
        ).toJson(),
      ),
    );
    ctl();
    await settle();
    await settle();
    expect(state().result!.blobs.single.blob.path, 'p');
    expect(state().stale, isFalse);
    expect(git.calls.where((c) => c.startsWith('cat-file')), isEmpty);
  });

  test('a cached scan from other refs is marked stale', () async {
    await kv.put(
      'maintenance:blobs:/r',
      jsonEncode(
        const BlobScan(
          scannedAt: '2026-09-01T00:00:00.000Z',
          fingerprint: 'old',
          blobs: [],
        ).toJson(),
      ),
    );
    ctl();
    await settle();
    await settle();
    expect(state().result, isNotNull);
    expect(state().stale, isTrue);
  });

  test('an unreadable cache is ignored', () async {
    await kv.put('maintenance:blobs:/r', '{nope');
    ctl();
    await settle();
    expect(state().result, isNull);
    expect(state().error, isNull);
  });

  test('cancel stops a running scan and keeps the old result', () async {
    await ctl().scan();
    final before = state().result;
    git.gates[_listKey] = Completer<void>();
    final running = ctl().scan();
    await settle();
    expect(state().scanning, isTrue);
    ctl().cancel();
    git.gates[_listKey]!.complete();
    await running;
    expect(state().scanning, isFalse);
    expect(state().error, isNull);
    expect(state().result, same(before));
  });

  test('a second scan while one runs is ignored', () async {
    git.gates[_listKey] = Completer<void>();
    final first = ctl().scan();
    await settle();
    await ctl().scan();
    git.gates[_listKey]!.complete();
    await first;
    expect(git.calls.where((c) => c == _listKey), hasLength(1));
  });

  test('a failed scan reports git stderr', () async {
    git.responses[_listKey] = const GitResult(128, '', 'fatal: bad object');
    await ctl().scan();
    expect(state().scanning, isFalse);
    expect(state().error, 'fatal: bad object');
  });

  test('reflogExpiryProvider counts the dry run', () async {
    git.responses['reflog expire --all --dry-run --verbose'] = const GitResult(
      0,
      'would prune x\n',
      '',
    );
    expect(await container.read(reflogExpiryProvider('/r').future), 1);
  });
}
