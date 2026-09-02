import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/data/update/installer_factory.dart';
import 'package:mergelio/data/update/installer_linux.dart';
import 'package:mergelio/data/update/installer_macos.dart';
import 'package:mergelio/data/update/installer_windows.dart';
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

  group('windows', () {
    test('hands the installer a silent upgrade command line', () async {
      final launcher = FakeLauncher();
      final file = File('${Directory.systemTemp.path}/setup.exe');
      file.writeAsStringSync('');
      addTearDown(() => file.deleteSync());

      await WindowsInstaller(launcher: launcher).handOff(file);

      expect(launcher.detached, hasLength(1));
      expect(launcher.detached.single, [
        file.path,
        '/SILENT',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
        '/NORESTART',
      ]);
    });

    test('refuses a file that is not there', () async {
      final launcher = FakeLauncher();
      await expectLater(
        WindowsInstaller(launcher: launcher).handOff(File('/nope/setup.exe')),
        throwsA(isA<UpdateInstallError>()),
      );
      expect(launcher.detached, isEmpty);
    });
  });

  group('macos', () {
    Directory workDir() {
      final work = Directory.systemTemp.createTempSync('mergelio-macos-test');
      addTearDown(() => work.deleteSync(recursive: true));
      Directory(
        '${work.path}/extracted/mergelio.app',
      ).createSync(recursive: true);
      return work;
    }

    test('verifies the bundle before it swaps anything', () async {
      final work = workDir();
      final zip = File('${work.path}/update.zip')..writeAsStringSync('');

      final launcher = FakeLauncher();
      await MacosInstaller(
        launcher: launcher,
        bundlePath: '/Applications/mergelio.app',
        processId: 4242,
        workDir: work,
      ).handOff(zip);

      expect(launcher.ran[0].first, 'ditto');
      expect(launcher.ran[1].first, 'codesign');
      expect(launcher.ran[2].first, 'spctl');
      expect(launcher.detached.single.first, '/bin/bash');
      expect(launcher.detached.single, contains('4242'));
      expect(launcher.detached.single, contains('/Applications/mergelio.app'));
    });

    test('stops when the signature does not check out', () async {
      final work = workDir();
      final zip = File('${work.path}/update.zip')..writeAsStringSync('');

      final launcher = FakeLauncher({
        'codesign': ProcessResult(0, 1, '', 'code object is not signed at all'),
      });

      await expectLater(
        MacosInstaller(
          launcher: launcher,
          bundlePath: '/Applications/mergelio.app',
          processId: 4242,
          workDir: work,
        ).handOff(zip),
        throwsA(isA<UpdateInstallError>()),
      );
      expect(launcher.detached, isEmpty);
    });

    test('stops when Gatekeeper rejects the bundle', () async {
      final work = workDir();
      final zip = File('${work.path}/update.zip')..writeAsStringSync('');

      final launcher = FakeLauncher({
        'spctl': ProcessResult(0, 3, '', 'rejected'),
      });

      await expectLater(
        MacosInstaller(
          launcher: launcher,
          bundlePath: '/Applications/mergelio.app',
          processId: 4242,
          workDir: work,
        ).handOff(zip),
        throwsA(isA<UpdateInstallError>()),
      );
      expect(launcher.detached, isEmpty);
    });
  });

  group('linux', () {
    test('never installs in place', () async {
      const installer = LinuxInstaller();
      expect(installer.canInstallInPlace, isFalse);
      await expectLater(
        installer.handOff(File('/tmp/whatever.deb')),
        throwsA(isA<UpdateInstallError>()),
      );
    });
  });

  test('the factory picks the installer this host can actually use', () {
    final installer = installerForHost(launcher: FakeLauncher());
    if (Platform.isMacOS) {
      expect(installer, isA<MacosInstaller>());
    } else if (Platform.isWindows) {
      expect(installer, isA<WindowsInstaller>());
    } else {
      expect(installer, isA<LinuxInstaller>());
    }
  });
}
