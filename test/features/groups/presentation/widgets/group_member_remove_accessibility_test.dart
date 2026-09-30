import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_member_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('accessible removal selects the exact member', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final removed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                for (final peer in ['bob', 'charlie'])
                  GroupMemberRow(
                    member: GroupMember(
                      groupId: 'group',
                      peerId: peer,
                      username: 'Journey$peer',
                      role: MemberRole.writer,
                      joinedAt: DateTime.utc(2026),
                    ),
                    isAdmin: true,
                    onRemove: () => removed.add(peer),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final control = find.bySemanticsIdentifier('group-member-remove-charlie');
      expect(control, findsOneWidget);
      expect(
        tester
            .getSemantics(control)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(control);
      expect(removed, ['charlie']);
      expect(
        find.bySemanticsIdentifier('group-member-remove-bob'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });
}
