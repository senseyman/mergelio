import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/ui/common/change_file_row.dart';

/// Paths of the changed-file rows marked as the one whose diff is open.
List<String> selectedRows(WidgetTester tester) => [
  for (final r in tester.widgetList<ChangeFileRow>(find.byType(ChangeFileRow)))
    if (r.selected) r.file.path,
];

/// Paths of the changed-file rows actually drawn filled — what the user sees,
/// as opposed to the flag the row was given.
List<String> filledRows(WidgetTester tester, Color fill) => [
  for (final row in find.byType(ChangeFileRow).evaluate())
    if (tester
            .widget<Material>(
              find.descendant(
                of: find.byWidget(row.widget),
                matching: find.byType(Material),
              ),
            )
            .color ==
        fill)
      (row.widget as ChangeFileRow).file.path,
];
