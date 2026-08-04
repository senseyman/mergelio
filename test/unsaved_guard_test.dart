// Anything that takes the editors away — leaving Files mode, closing a repo
// tab, quitting — asks the open editors first.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/state/unsaved_guard.dart';

void main() {
  late ProviderContainer c;
  late UnsavedGuards guards;

  setUp(() {
    c = ProviderContainer();
    guards = c.read(unsavedGuardsProvider);
  });
  tearDown(() => c.dispose());

  test('a repository with no editors open lets everything through', () async {
    expect(await guards.confirm('/r'), isTrue);
    expect(await guards.confirmAll(), isTrue);
  });

  test('a guard that agrees lets the action proceed', () async {
    guards.register('/r', () async => true);

    expect(await guards.confirm('/r'), isTrue);
  });

  test('a guard that refuses stops the action', () async {
    guards.register('/r', () async => false);

    expect(await guards.confirm('/r'), isFalse);
  });

  test('only the named repository is asked', () async {
    guards.register('/other', () async => false);

    expect(await guards.confirm('/r'), isTrue);
  });

  test('quitting asks every open repository', () async {
    var asked = 0;
    guards
      ..register('/a', () async {
        asked++;
        return true;
      })
      ..register('/b', () async {
        asked++;
        return true;
      });

    expect(await guards.confirmAll(), isTrue);
    expect(asked, 2);
  });

  test('one refusal stops the whole quit', () async {
    var askedSecond = false;
    guards
      ..register('/a', () async => false)
      ..register('/b', () async {
        askedSecond = true;
        return true;
      });

    expect(await guards.confirmAll(), isFalse);
    // Nothing else is asked once the user has said no.
    expect(askedSecond, isFalse);
  });

  test('an unregistered guard is not consulted again', () async {
    guards
      ..register('/r', () async => false)
      ..unregister('/r');

    expect(await guards.confirm('/r'), isTrue);
  });

  test('re-registering replaces the previous guard', () async {
    guards
      ..register('/r', () async => false)
      ..register('/r', () async => true);

    expect(await guards.confirm('/r'), isTrue);
  });
}
