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
    guards.register('/r', () async => false)();

    expect(await guards.confirm('/r'), isTrue);
  });

  test('a second guard joins the first rather than replacing it', () async {
    // An editor pane and a bisect bar guard the same repository for different
    // reasons. Whichever registered first must still be asked.
    guards
      ..register('/r', () async => false)
      ..register('/r', () async => true);

    expect(await guards.confirm('/r'), isFalse);
  });

  test('every guard on a repository is asked', () async {
    var asked = 0;
    Future<bool> count() async {
      asked++;
      return true;
    }

    guards
      ..register('/r', count)
      ..register('/r', count);

    expect(await guards.confirm('/r'), isTrue);
    expect(asked, 2);
  });

  test('dropping one guard leaves the others in place', () async {
    final dropFirst = guards.register('/r', () async => true);
    guards.register('/r', () async => false);

    dropFirst();

    // Dropping by path would have taken the second guard too — the way an
    // editor pane being torn down can silently remove somebody else's.
    expect(await guards.confirm('/r'), isFalse);
  });

  test('dropping a guard twice takes nothing else with it', () async {
    final drop = guards.register('/r', () async => true);
    drop();
    guards.register('/r', () async => false);

    drop();

    expect(await guards.confirm('/r'), isFalse);
  });

  test('a guard that registers another guard for the same repository while '
      'confirm is walking does not throw', () async {
    var secondAsked = false;
    guards.register('/r', () async {
      guards.register('/r', () async {
        secondAsked = true;
        return true;
      });
      return true;
    });

    expect(await guards.confirm('/r'), isTrue);
    // The walk had already copied its list before the new guard joined,
    // so it is not asked on this pass.
    expect(secondAsked, isFalse);

    // The newly joined guard is present on the next walk.
    expect(await guards.confirm('/r'), isTrue);
    expect(secondAsked, isTrue);
  });

  test('a guard that drops another guard for the same repository while '
      'confirm is walking does not throw', () async {
    late DropGuard dropSecond;
    var secondAsked = false;
    guards.register('/r', () async {
      dropSecond();
      return true;
    });
    dropSecond = guards.register('/r', () async {
      secondAsked = true;
      return true;
    });

    expect(await guards.confirm('/r'), isTrue);
    // The dropped guard was already copied into this walk, so it is still
    // asked once — the drop only takes effect for the next walk.
    expect(secondAsked, isTrue);

    secondAsked = false;
    expect(await guards.confirm('/r'), isTrue);
    expect(secondAsked, isFalse);
  });

  test('a guard that mutates guards of the same repository while confirmAll '
      'is walking does not throw', () async {
    late DropGuard dropSecond;
    var secondAsked = false;
    var thirdAsked = false;
    guards.register('/a', () async {
      dropSecond();
      guards.register('/a', () async {
        thirdAsked = true;
        return true;
      });
      return true;
    });
    dropSecond = guards.register('/a', () async {
      secondAsked = true;
      return true;
    });

    expect(await guards.confirmAll(), isTrue);
    expect(secondAsked, isTrue);
    expect(thirdAsked, isFalse);
  });

  test('quitting asks every guard of every repository', () async {
    var asked = 0;
    Future<bool> count() async {
      asked++;
      return true;
    }

    guards
      ..register('/a', count)
      ..register('/a', count)
      ..register('/b', count);

    expect(await guards.confirmAll(), isTrue);
    expect(asked, 3);
  });
}
