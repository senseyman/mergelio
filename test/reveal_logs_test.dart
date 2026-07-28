import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mergelio/core/tokens.dart';
import 'package:mergelio/domain/reveal.dart';
import 'package:mergelio/l10n/gen/app_localizations.dart';
import 'package:mergelio/state/diagnostics.dart';
import 'package:mergelio/ui/preferences/logs_row.dart';

/// The log file is only useful if the user can get to it, so Preferences offers
/// a one-click reveal. The command is built per platform and kept pure so the
/// mapping is verifiable without spawning a process.
void main() {
  group('revealCommand', () {
    test('selects the file in Finder on macOS', () {
      final (exe, args) = revealCommand('/a/b/mergelio.log', os: 'macos')!;
      expect(exe, 'open');
      expect(args, ['-R', '/a/b/mergelio.log']);
    });

    test('opens the folder itself when nothing is to be selected', () {
      final (exe, args) = revealCommand('/a/b', os: 'macos', select: false)!;
      expect(exe, 'open');
      expect(args, ['/a/b']);
    });

    test('selects the file in Explorer on Windows', () {
      final (exe, args) = revealCommand(r'C:\a\mergelio.log', os: 'windows')!;
      expect(exe, 'explorer');
      expect(args, [r'/select,C:\a\mergelio.log']);
    });

    test('opens the containing folder on Linux, which cannot select', () {
      final (exe, args) = revealCommand('/a/b/mergelio.log', os: 'linux')!;
      expect(exe, 'xdg-open');
      expect(args, ['/a/b']);
    });

    test('returns null on a platform with no known file manager', () {
      expect(revealCommand('/a/b.log', os: 'android'), isNull);
    });
  });

  group('revealInFileManager', () {
    test('runs the platform command for the given path', () async {
      final calls = <(String, List<String>)>[];
      await revealInFileManager(
        '/a/b.log',
        os: 'macos',
        run: (exe, args) async {
          calls.add((exe, args));
          return ProcessResult(1, 0, '', '');
        },
      );

      expect(calls.single.$1, 'open');
      expect(calls.single.$2, ['-R', '/a/b.log']);
    });

    test('throws when the platform has no file manager', () {
      expect(
        () => revealInFileManager('/a/b.log', os: 'android'),
        throwsA(isA<ProcessException>()),
      );
    });

    test('throws with the stderr when the command fails', () {
      expect(
        () => revealInFileManager(
          '/a/b.log',
          os: 'macos',
          run: (exe, args) async => ProcessResult(1, 1, '', 'no such file'),
        ),
        throwsA(
          isA<ProcessException>().having(
            (e) => e.message,
            'message',
            'no such file',
          ),
        ),
      );
    });
  });

  group('logFilePathProvider', () {
    test('is null while file logging is inert', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(logFilePathProvider), isNull);
    });
  });

  group('LogsRow', () {
    testWidgets('shows the log path and reveals it on tap', (tester) async {
      final revealed = <String>[];
      await _pump(
        tester,
        path: '/tmp/logs/mergelio.log',
        reveal: (p) async => revealed.add(p),
      );

      expect(find.textContaining('/tmp/logs/mergelio.log'), findsOneWidget);
      await tester.tap(find.text('Reveal'));
      await tester.pump();

      expect(revealed, ['/tmp/logs/mergelio.log']);
    });

    testWidgets('disables the button when file logging is not active', (
      tester,
    ) async {
      await _pump(tester, path: null, reveal: (p) async {});

      final button = tester.widget<TextButton>(find.byType(TextButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('reports a reveal failure instead of throwing', (tester) async {
      await _pump(
        tester,
        path: '/tmp/logs/mergelio.log',
        reveal: (p) async => throw ProcessException('open', const []),
      );

      await tester.tap(find.text('Reveal'));
      await tester.pump();

      expect(find.textContaining('Could not open'), findsOneWidget);
    });
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required String? path,
  required Future<void> Function(String) reveal,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        logFilePathProvider.overrideWithValue(path),
        revealProvider.overrideWithValue(reveal),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppTokens.dark()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: LogsRow()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
