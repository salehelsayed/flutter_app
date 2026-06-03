import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/archived_empty_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  group('ArchivedEmptyState', () {
    testWidgets('renders icon and text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ArchivedEmptyState()),
        ),
      );

      expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
      expect(find.text('No archived friends yet'), findsOneWidget);
      expect(
        find.text('Swipe left on a friend to archive them.'),
        findsOneWidget,
      );
    });
  });
}
