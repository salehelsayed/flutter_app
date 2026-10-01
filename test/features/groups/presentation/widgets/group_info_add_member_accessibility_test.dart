import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Add Member is an identified, tappable button for admins', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupInfoScreen(
            group: GroupModel(
              id: 'group',
              name: 'Group',
              type: GroupType.chat,
              topicName: 'topic',
              createdAt: DateTime.utc(2026),
              createdBy: 'admin',
              myRole: GroupRole.admin,
            ),
            members: const [],
            isAdmin: true,
            onBack: () {},
            onLeave: () {},
            onAddMember: () => taps++,
          ),
        ),
      );
      // The screen animates continuously; pump fixed frames, never settle.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final control = find.bySemanticsIdentifier('group-info-add-member');
      expect(control, findsOneWidget);
      final data = tester.getSemantics(control).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, 'Add Member');
      await tester.ensureVisible(control);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(control);
      expect(taps, 1);
    } finally {
      semantics.dispose();
    }
  });
}
