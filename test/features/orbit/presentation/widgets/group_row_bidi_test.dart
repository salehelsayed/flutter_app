import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/group_row.dart';

OrbitGroup _group({
  required String name,
  required String senderUsername,
  required String latestMessageText,
  int unreadCount = 2,
  GroupType type = GroupType.chat,
}) {
  return OrbitGroup(
    group: GroupModel(
      id: 'group-1',
      name: name,
      type: type,
      topicName: 'topic-1',
      createdAt: DateTime(2026, 3, 9).toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    ),
    latestMessageSenderUsername: senderUsername,
    latestMessageText: latestMessageText,
    unreadCount: unreadCount,
    lastActivityTimestamp: DateTime(2026, 3, 9, 9, 30),
  );
}

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  group('GroupRow', () {
    Text _textFor(WidgetTester tester, String text) {
      final finder = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == text,
        description: 'Text("$text")',
      );
      expect(finder, findsOneWidget);
      return tester.widget<Text>(finder);
    }

    testWidgets(
      'renders LTR sender plus Arabic-first body with RTL body direction',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            GroupRow(
              group: _group(
                name: 'النسخة Alpha',
                senderUsername: 'Alice',
                latestMessageText: 'مرحبا Hello 123',
              ),
              onTap: () {},
            ),
          ),
        );

        expect(find.text('النسخة Alpha'), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('مرحبا Hello 123'), findsOneWidget);
        expect(_textFor(tester, 'مرحبا Hello 123').textDirection,
            TextDirection.rtl);
        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets(
      'renders Arabic sender plus English-first body with LTR body direction',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            GroupRow(
              group: _group(
                name: 'Team نور',
                senderUsername: 'نور',
                latestMessageText: 'Hello مرحبا 123',
                type: GroupType.announcement,
                unreadCount: 0,
              ),
              onTap: () {},
            ),
          ),
        );

        expect(find.text('Team نور'), findsOneWidget);
        expect(find.text('نور'), findsOneWidget);
        expect(find.text('Hello مرحبا 123'), findsOneWidget);
        expect(_textFor(tester, 'Hello مرحبا 123').textDirection,
            TextDirection.ltr);
        expect(find.text('Announce'), findsOneWidget);
      },
    );

    testWidgets('renders empty preview fallback when no structured message',
        (tester) async {
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: OrbitGroup(
              group: GroupModel(
                id: 'group-2',
                name: 'No preview',
                type: GroupType.chat,
                topicName: 'topic-2',
                createdAt: DateTime(2026, 3, 9).toUtc(),
                createdBy: 'peer-admin',
                myRole: GroupRole.admin,
              ),
              unreadCount: 0,
              lastActivityTimestamp: DateTime(2026, 3, 9, 9, 30),
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('No preview'), findsOneWidget);
      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('renders mixed-script preview content', (tester) async {
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: _group(
              name: 'النسخة Alpha',
              senderUsername: 'Alice',
              latestMessageText: 'مرحبا Hello 123',
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('النسخة Alpha'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('مرحبا Hello 123'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('renders announcement groups without throwing', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: _group(
              name: 'إعلانات Team',
              senderUsername: 'Bob',
              latestMessageText: 'Status update',
              type: GroupType.announcement,
              unreadCount: 0,
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('إعلانات Team'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Status update'), findsOneWidget);
      expect(find.text('Announce'), findsOneWidget);
    });
  });
}
