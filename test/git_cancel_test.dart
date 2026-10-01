import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_service.dart';

void main() {
  test('one handle shared by concurrent commands kills every one', () async {
    // A largest-blobs scan looks up many blobs at once under a single
    // handle; cancelling it must stop all of them, not the last to start.
    final cancel = GitCancel();
    final a = await Process.start('sleep', ['30']);
    final b = await Process.start('sleep', ['30']);
    cancel
      ..attach(a)
      ..attach(b);
    cancel.cancel();
    final codes = await Future.wait([a.exitCode, b.exitCode])
        .timeout(const Duration(seconds: 5));
    expect(codes, everyElement(isNot(0)));
  });

  test('a child attached after cancel dies at once', () async {
    final cancel = GitCancel()..cancel();
    final p = await Process.start('sleep', ['30']);
    cancel.attach(p);
    expect(await p.exitCode.timeout(const Duration(seconds: 5)), isNot(0));
  });
}
