import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/workspace/forge_presentation.dart';

void main() {
  late AppLocalizations l;

  setUp(() async {
    l = await AppLocalizations.delegate.load(const Locale('en'));
  });

  String? ago(Duration d) => forgeAgo(l, DateTime.now().subtract(d));

  group('the boundary between units', () {
    // Pinned to the second, which the clock-reading version could not be.
    final at = DateTime(2026, 1, 1, 12);
    String? at2(Duration d) => forgeAgo(l, at, now: at.add(d));

    test('a minute begins at sixty seconds, not before', () {
      expect(at2(const Duration(seconds: 59)), 'now');
      expect(at2(const Duration(seconds: 60)), '1m');
    });

    test('an hour begins at sixty minutes', () {
      expect(at2(const Duration(minutes: 59)), '59m');
      expect(at2(const Duration(minutes: 60)), '1h');
    });

    test('a day begins at twenty-four hours', () {
      expect(at2(const Duration(hours: 23)), '23h');
      expect(at2(const Duration(hours: 24)), '1d');
    });
  });

  test('anything under a minute reads as just now', () {
    expect(ago(const Duration(seconds: 42)), 'now');
  });

  test('minutes, hours and days each get their own unit', () {
    expect(ago(const Duration(minutes: 5)), '5m');
    expect(ago(const Duration(hours: 3)), '3h');
    expect(ago(const Duration(days: 2)), '2d');
  });

  test('the largest whole unit wins, so a row stays short', () {
    // 90 minutes is an hour, not ninety minutes: the sidebar is 264px and
    // this sits beside an author and two branch names.
    expect(ago(const Duration(minutes: 90)), '1h');
    expect(ago(const Duration(hours: 49)), '2d');
  });

  test('a timestamp in the future does not read as an age', () {
    // Clock skew between a forge and this machine is ordinary; "-3h" or a
    // negative day count would be worse than admitting nothing useful.
    expect(forgeAgo(l, DateTime.now().add(const Duration(hours: 3))), 'now');
  });

  test('nothing to show when the forge sent no timestamp', () {
    expect(forgeAgo(l, null), isNull);
  });
}
