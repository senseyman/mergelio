import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/external_tools.dart';

/// The launcher is the one place a program the user named is started. It
/// must find it where a Finder launch would not look, refuse cleanly when it
/// is nowhere, and report how the program ended.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_launch_');
  });

  tearDown(() => dir.delete(recursive: true));

  Future<String> script(String name, String body) async {
    final f = File('${dir.path}/$name');
    await f.writeAsString('#!/bin/sh\n$body\n');
    await Process.run('chmod', ['+x', f.path]);
    return f.path;
  }

  test('finds a bare name on the search path and passes the args', () async {
    final out = '${dir.path}/out';
    await script('fake-editor', 'printf "%s|" "\$@" > "$out"');
    final launcher = SystemExternalLauncher(searchPath: () => dir.path);

    final r = await launcher.run('fake-editor', ['-g', '/a b:3']);

    expect(r.exitCode, 0);
    expect(await File(out).readAsString(), '-g|/a b:3|');
  }, skip: Platform.isWindows);

  test('a program under ~/ is found in the home directory', () async {
    await Directory('${dir.path}/bin').create();
    final out = '${dir.path}/out';
    await script('bin/ed', 'echo ran > "$out"');
    final launcher = SystemExternalLauncher(
      searchPath: () => '/nonexistent',
      home: dir.path,
    );

    final r = await launcher.run('~/bin/ed', const []);

    expect(r.exitCode, 0);
    expect(await File(out).readAsString(), 'ran\n');
  }, skip: Platform.isWindows);

  test('a program that exits non-zero hands back its stderr', () async {
    final exe = await script('cross', 'echo nope >&2; exit 3');
    final r = await const SystemExternalLauncher().run(exe, const []);
    expect(r.exitCode, 3);
    expect(r.stderr.toString().trim(), 'nope');
  }, skip: Platform.isWindows);

  test('a name found nowhere is a ProcessException, nothing runs', () async {
    final launcher = SystemExternalLauncher(searchPath: () => dir.path);
    await expectLater(
      launcher.run('no-such-editor-xyz', const []),
      throwsA(
        isA<ProcessException>().having(
          (e) => e.executable,
          'executable',
          'no-such-editor-xyz',
        ),
      ),
    );
  });
}
