import 'package:flutter/material.dart';
import 'package:flutter_app/core/widgets/undo_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const window = Duration(seconds: 4);

  Widget buildHarness({
    required VoidCallback onUndo,
    required Future<void> Function() onCommit,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showUndoBar(
                context,
                message: 'Invite declined',
                window: window,
                onUndo: onUndo,
                onCommit: onCommit,
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('visible duration equals the commit window and then commits', (
    tester,
  ) async {
    var undoCount = 0;
    var commitCount = 0;
    await tester.pumpWidget(
      buildHarness(
        onUndo: () => undoCount += 1,
        onCommit: () async => commitCount += 1,
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final barFinder = find.byKey(const ValueKey('undo-bar'));
    expect(barFinder, findsOneWidget);
    expect(tester.widget<SnackBar>(barFinder).duration, window);
    expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);

    await tester.pump(window - const Duration(milliseconds: 500));
    expect(commitCount, 0);
    expect(undoCount, 0);

    await tester.pump(const Duration(milliseconds: 700));
    expect(commitCount, 1);
    expect(undoCount, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(commitCount, 1);
    expect(barFinder, findsNothing);
  });

  testWidgets('Undo resolves once and prevents the deferred commit', (
    tester,
  ) async {
    var undoCount = 0;
    var commitCount = 0;
    await tester.pumpWidget(
      buildHarness(
        onUndo: () => undoCount += 1,
        onCommit: () async => commitCount += 1,
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();

    expect(undoCount, 1);
    expect(commitCount, 0);
    expect(find.byKey(const ValueKey('undo-bar')), findsNothing);

    await tester.pump(window + const Duration(seconds: 1));
    expect(undoCount, 1);
    expect(commitCount, 0);
  });

  testWidgets(
    'supersedes stale feedback so cancellation never closes a queued bar',
    (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      ScaffoldMessenger.of(
        hostContext,
      ).showSnackBar(const SnackBar(content: Text('stale feedback')));
      await tester.pump();

      final handle = showUndoBar(
        hostContext,
        message: 'Invite declined',
        window: window,
        onUndo: () {},
        onCommit: () {},
      );
      await tester.pump();
      expect(find.text('stale feedback'), findsNothing);
      expect(find.byKey(const ValueKey('undo-bar')), findsOneWidget);

      handle.cancel();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
