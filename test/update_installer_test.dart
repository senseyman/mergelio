import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/update/update_installer.dart';

class FakeLauncher implements ProcessLauncher {
  final List<List<String>> ran = [];
  final List<List<String>> detached = [];
  final Map<String, ProcessResult> results;

  FakeLauncher([this.results = const {}]);

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    ran.add([executable, ...arguments]);
    return results[executable] ?? ProcessResult(0, 0, '', '');
  }

  @override
  Future<void> startDetached(String executable, List<String> arguments) async {
    detached.add([executable, ...arguments]);
  }
}

void main() {
  group('the process seam', () {
    test('records a command instead of running it', () async {
      final launcher = FakeLauncher();
      await launcher.run('codesign', const ['-v', 'Mergelio.app']);
      expect(launcher.ran.single, ['codesign', '-v', 'Mergelio.app']);
      expect(launcher.detached, isEmpty);
    });

    test('keeps a detached launch apart from a plain run', () async {
      final launcher = FakeLauncher();
      await launcher.startDetached('/bin/sh', const ['swap.sh', '123']);
      expect(launcher.detached.single, ['/bin/sh', 'swap.sh', '123']);
      expect(launcher.ran, isEmpty);
    });

    test('hands back the exit code a test asked it to', () async {
      final launcher = FakeLauncher({
        'codesign': ProcessResult(0, 1, '', 'not signed'),
      });
      final result = await launcher.run('codesign', const []);
      expect(result.exitCode, 1);
      expect(result.stderr, 'not signed');
    });
  });
}
