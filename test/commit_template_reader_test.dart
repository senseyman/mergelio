import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/domain/git/git_reader.dart';
import 'package:mergelio/domain/git/git_service.dart';

void main() {
  late Directory dir;
  const svc = SystemGitService();

  Future<void> g(List<String> args) async {
    final r = await svc.run(args, repoPath: dir.path);
    if (!r.ok) throw StateError('git ${args.join(' ')} failed: ${r.err}');
  }

  GitReader reader() => GitReader(svc, dir.path);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mergelio_template_');
    await g(['init', '-q']);
    // A host-wide commit.template must not leak into what is read here.
    await g(['config', 'commit.template', '']);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('no template anywhere reads as empty', () async {
    final t = await reader().commitTemplate();
    expect(t.template, '');
    expect(t.commentChar, '#');
  });

  test('commit.template is read, relative to the repository', () async {
    File('${dir.path}/tpl.txt').writeAsStringSync('feat: \n# why\n');
    await g(['config', 'commit.template', 'tpl.txt']);
    expect((await reader().commitTemplate()).template, 'feat: \n# why\n');
  });

  test('commit.template may be absolute', () async {
    final other = await Directory.systemTemp.createTemp('mergelio_tpl_abs_');
    addTearDown(() => other.delete(recursive: true));
    File('${other.path}/t').writeAsStringSync('abs');
    await g(['config', 'commit.template', '${other.path}/t']);
    expect((await reader().commitTemplate()).template, 'abs');
  });

  test('.gitmessage at the root is the fallback', () async {
    File('${dir.path}/.gitmessage').writeAsStringSync('from gitmessage');
    expect((await reader().commitTemplate()).template, 'from gitmessage');
  });

  test('a configured template that cannot be read falls back', () async {
    File('${dir.path}/.gitmessage').writeAsStringSync('fallback');
    await g(['config', 'commit.template', 'missing.txt']);
    expect((await reader().commitTemplate()).template, 'fallback');
  });

  test('core.commentChar is reported, auto meaning #', () async {
    await g(['config', 'core.commentChar', ';']);
    expect((await reader().commitTemplate()).commentChar, ';');
    await g(['config', 'core.commentChar', 'auto']);
    expect((await reader().commitTemplate()).commentChar, '#');
  });
}
