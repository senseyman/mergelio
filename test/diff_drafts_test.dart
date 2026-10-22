import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/diff_drafts.dart';
import 'package:mergelio/state/diff_target.dart';
import 'package:mergelio/state/file_editor.dart';

const _f = DiffTarget(repoPath: '/r', path: 'f.txt');
final _fWhole = _f.withWholeFile(true);

EditorDraft _draft(String text) => EditorDraft(
  text: text,
  baseline: const EditableFile(text: 'disk'),
);

void main() {
  test('a file is found however its diff is being viewed', () {
    final drafts = DiffDrafts()..put(_fWhole, _draft('typed'));

    expect(draftFor(drafts.state, _f)?.text, 'typed');
    expect(draftFor(drafts.state, _fWhole)?.text, 'typed');
  });

  test('typing into the same file in another view replaces its draft', () {
    final drafts = DiffDrafts()
      ..put(_fWhole, _draft('first'))
      ..put(_f, _draft('second'));

    expect(drafts.state.length, 1);
    expect(draftFor(drafts.state, _fWhole)?.text, 'second');
  });

  test('dropping the file in another view drops its draft', () {
    final drafts = DiffDrafts()
      ..put(_fWhole, _draft('typed'))
      ..drop(_f);

    expect(drafts.state, isEmpty);
  });

  test('both sides of a working-tree file share its one draft', () {
    // Either side edits the same file on disk.
    final drafts = DiffDrafts()
      ..put(_f, _draft('first'))
      ..put(_f.withStaged(true), _draft('second'));

    expect(drafts.state.length, 1);
    expect(draftFor(drafts.state, _f)?.text, 'second');
  });

  test('another file is another draft', () {
    final drafts = DiffDrafts()
      ..put(_f, _draft('a'))
      ..put(const DiffTarget(repoPath: '/r', path: 'g.txt'), _draft('b'))
      ..put(const DiffTarget(repoPath: '/s', path: 'f.txt'), _draft('c'));

    expect(drafts.state.length, 3);
  });
}
