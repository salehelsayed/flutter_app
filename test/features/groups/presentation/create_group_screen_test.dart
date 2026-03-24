import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/create_group_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({
    void Function(String, GroupType, String?)? onCreate,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CreateGroupScreen(
        onCreate: onCreate ?? (name, type, description) {},
        onBack: () {},
      ),
    );
  }

  testWidgets('renders form fields', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.text('Group Name'), findsOneWidget);
    expect(find.text('Group Type'), findsOneWidget);
    expect(find.text('Description (optional)'), findsOneWidget);
    // "Create Group" appears in both header and button
    expect(find.text('Create Group'), findsNWidgets(2));
  });

  testWidgets('type selector works', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    // Default is Discussion (chat type)
    expect(find.text('Discussion'), findsOneWidget);
    expect(find.text('Announce'), findsOneWidget);
    // Tap on Announce
    await tester.tap(find.text('Announce'));
    await tester.pump();

    // No error — selector remains interactive
    expect(find.text('Announce'), findsOneWidget);
  });

  testWidgets('create button calls onCreate with form data', (tester) async {
    String? capturedName;
    GroupType? capturedType;

    await tester.pumpWidget(buildTestWidget(
      onCreate: (name, type, desc) {
        capturedName = name;
        capturedType = type;
      },
    ));

    // Enter group name
    await tester.enterText(
      find.byType(TextField).first,
      'My New Group',
    );
    await tester.pump();

    // Tap create button (last "Create Group" text is the button)
    await tester.tap(find.text('Create Group').last);
    await tester.pump();

    expect(capturedName, 'My New Group');
    expect(capturedType, GroupType.chat);
  });

  group('initialType', () {
    testWidgets('defaults to chat type when no initialType provided',
        (tester) async {
      GroupType? submittedType;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CreateGroupScreen(
            onCreate: (name, type, description) => submittedType = type,
            onBack: () {},
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter group name'),
        'Test',
      );
      await tester.pump();

      await tester.tap(find.text('Create Group').last);
      await tester.pump();

      expect(submittedType, GroupType.chat);
    });

    testWidgets(
        'pre-selects announcement type when initialType is announcement',
        (tester) async {
      GroupType? submittedType;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CreateGroupScreen(
            initialType: GroupType.announcement,
            onCreate: (name, type, description) => submittedType = type,
            onBack: () {},
          ),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Enter group name'),
        'Test',
      );
      await tester.pump();

      await tester.tap(find.text('Create Group').last);
      await tester.pump();

      expect(submittedType, GroupType.announcement);
    });

  });
}
