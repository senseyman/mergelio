import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/terminal.dart';

void main() {
  test('inputEndsCommand is true only when Enter (CR/LF) is pressed', () {
    expect(inputEndsCommand('\r'), isTrue); // Enter in a raw PTY
    expect(inputEndsCommand('git status\n'), isTrue);
    expect(inputEndsCommand('git sta'), isFalse); // mid-typing
    expect(inputEndsCommand('a'), isFalse);
    expect(inputEndsCommand(''), isFalse);
  });
}
