import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_card.dart';

void main() {
  final announcementGroup = GroupModel(
    id: 'group-announcements',
    name: 'Project Announcements',
    type: GroupType.announcement,
    topicName: 'topic-announcements',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  final chatGroup = GroupModel(
    id: 'group-chat',
    name: 'Project Chat',
    type: GroupType.chat,
    topicName: 'topic-chat',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );

  Widget buildCard({
    required GroupModel group,
    required String sender,
    required String body,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: GroupCard(
          group: group,
          lastMessageSender: sender,
          lastMessageBody: body,
          lastMessageTime: '10:30 AM',
        ),
      ),
    );
  }

  Text _textWidget(WidgetTester tester, String text) {
    return tester.widget<Text>(find.text(text));
  }

  testWidgets(
    'announcement preview separates sender label from Arabic-first mixed body',
    (tester) async {
      const sender = 'Admin';
      const body = 'مرحبا Hello 123';

      await tester.pumpWidget(
        buildCard(group: announcementGroup, sender: sender, body: body),
      );

      expect(find.text(sender), findsOneWidget);
      expect(find.text(body), findsOneWidget);
      expect(find.text('$sender: $body'), findsNothing);
      expect(_textWidget(tester, body).textDirection, TextDirection.rtl);
    },
  );

  testWidgets(
    'group preview keeps English-first body LTR even with mixed sender name',
    (tester) async {
      const sender = 'مرحبا Ali';
      const body = 'Hello مرحبا 123';

      await tester.pumpWidget(
        buildCard(group: chatGroup, sender: sender, body: body),
      );

      expect(find.text(sender), findsOneWidget);
      expect(find.text(body), findsOneWidget);
      expect(find.text('$sender: $body'), findsNothing);
      expect(_textWidget(tester, body).textDirection, TextDirection.ltr);
    },
  );
}
