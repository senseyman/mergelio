import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/git/models.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/ui/graph/commit_row.dart';
import 'package:mergelio/ui/graph/rail_metrics.dart';

Commit _c() => Commit(
  sha: '0d54cb5aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  message: 'fix(forge): make a connected token take effect',
  author: 'Neo',
  authorEmail: 'someone@example.test',
  date: DateTime(2026, 9, 18),
);

// Long enough that it still overflows even at the generous share a fair
// split should give it on a wide row, so the rendered width reflects the
// share it was actually granted rather than being capped by its own length.
Commit _longC() => Commit(
  sha: '0d54cb5aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  message:
      'fix(forge): '
      'make a connected token take effect across every panel that reads it, '
      'including the ones that only refresh on focus and the ones that poll',
  author: 'Neo',
  authorEmail: 'someone@example.test',
  date: DateTime(2026, 9, 18),
);

// A long author name so the meta line (author · date · sha) needs more room
// than a narrow row has, forcing all three fields to shrink.
Commit _longAuthorC() => Commit(
  sha: '0d54cb5aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  message: 'fix(forge): make a connected token take effect',
  author: 'Alexandria Fitzgerald-Montgomery Kowalczyk',
  authorEmail: 'someone@example.test',
  date: DateTime(2026, 9, 18),
);

Future<void> _pumpAt(
  WidgetTester tester,
  double width, {
  required bool compact,
  Commit? commit,
}) async {
  // The default test surface is only 800px wide, which silently clamps any
  // width above it — defeating the wide-row cases below. Size the surface to
  // whatever the row itself asks for, with headroom, and restore it after.
  tester.view.physicalSize = Size(width + 400, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppTokens.dark()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: CommitRow(
              commit: commit ?? _c(),
              branchLabels: const [],
              metrics: RailMetrics(compact: compact),
              maxLane: 0,
              cols: const {},
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // Widths a real window produces: the history panel is whatever is left after
  // the sidebar and the changes panel, so it gets narrow long before the
  // window does.
  const narrow = [560.0, 500.0, 460.0, 420.0, 380.0];
  // Widths where the history panel has room to spare — a wide monitor, or a
  // maximized window with the sidebar and changes panel both collapsed.
  const wide = [1200.0, 1600.0];

  for (final compact in [true, false]) {
    final mode = compact ? 'compact' : 'two-line';

    testWidgets('a $mode row does not overflow when the panel is narrow', (
      tester,
    ) async {
      for (final width in narrow) {
        await _pumpAt(tester, width, compact: compact);
        expect(
          tester.takeException(),
          isNull,
          reason: 'a $mode row overflowed at ${width}px',
        );
      }
    });

    testWidgets('a $mode row keeps showing the commit message when narrow', (
      tester,
    ) async {
      // The message is the reason the row exists. The author, date and sha are
      // context for it, so they are what gives way when space runs out — a row
      // that renders its metadata and nothing else has lost the plot.
      for (final width in narrow) {
        await _pumpAt(tester, width, compact: compact);
        tester.takeException();
        final title = find.textContaining('fix(forge)');
        expect(title, findsOneWidget, reason: 'no message at ${width}px');
        expect(
          tester.getSize(title.first).width,
          greaterThan(0),
          reason: 'the message was squeezed to nothing at ${width}px',
        );
      }
    });

    testWidgets('a $mode row gives the message most of the row when wide', (
      tester,
    ) async {
      // The meta line (author · date · sha) is short and needs only a small
      // slice of a wide row. An even flex split still caps the message at
      // half the row regardless, ellipsizing it while empty space sits
      // beside the meta line. The message should get whatever the meta line
      // does not need.
      for (final width in wide) {
        await _pumpAt(tester, width, compact: compact, commit: _longC());
        tester.takeException();
        final title = find.textContaining('fix(forge)');
        expect(title, findsOneWidget, reason: 'no message at ${width}px');
        final titleWidth = tester.getSize(title.first).width;
        expect(
          titleWidth,
          greaterThan(width * 0.5),
          reason:
              'the message only got ${titleWidth}px of a ${width}px row; '
              'the meta line took an even, undeserved share of it',
        );
      }
    });

    testWidgets(
      'a $mode row shrinks meta fields by their own need, not evenly',
      (tester) async {
        // A long author name and short sha both want to shrink under the same
        // pressure. An even three-way split crushes them to the same width
        // regardless — the author loses far more of what it needed than the
        // sha does. Weighting the shrink by each field's own natural width
        // keeps that lopsided loss proportional instead.
        await _pumpAt(tester, 420, compact: compact, commit: _longAuthorC());
        tester.takeException();
        final authorWidth = tester
            .getSize(find.textContaining('Alexandria').first)
            .width;
        final shaWidth = tester
            .getSize(find.textContaining('0d54cb5').first)
            .width;
        expect(
          authorWidth,
          greaterThan(shaWidth * 2),
          reason:
              'author ($authorWidth px) and sha ($shaWidth px) shrank by '
              'about the same amount, meaning the split ignored how much '
              'each field actually needed',
        );
      },
    );
  }
}
