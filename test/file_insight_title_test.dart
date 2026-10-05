import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/ui/insight/file_insight_dialog.dart';

void main() {
  test('the checkout reads as the bare path', () {
    expect(fileInsightTitle('lib/a.dart', null), 'lib/a.dart');
  });

  test('a revision is named, a sha shortened', () {
    expect(fileInsightTitle('lib/a.dart', 'feature'), 'lib/a.dart @ feature');
    expect(fileInsightTitle('a', 'f' * 40), 'a @ fffffff');
  });
}
