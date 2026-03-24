import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';

void main() {
  final chatGroup = GroupModel(
    id: 'group-chat',
    name: 'Project Chat',
    type: GroupType.chat,
    topicName: 'topic-chat',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.member,
  );

  final announcementGroup = GroupModel(
    id: 'group-announcements',
    name: 'Project Announcements',
    type: GroupType.announcement,
    topicName: 'topic-announcements',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  GroupMessage buildMessage({
    required String id,
    required String groupId,
    required String senderUsername,
    required String text,
  }) {
    return GroupMessage(
      id: id,
      groupId: groupId,
      senderPeerId: 'peer-sender',
      senderUsername: senderUsername,
      text: text,
      timestamp: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
    );
  }

  Widget buildScreen({
    required List<GroupModel> groups,
    required Map<String, GroupMessage?> latestMessages,
  }) {
    return MaterialApp(
      home: GroupListScreen(
        groups: groups,
        latestMessages: latestMessages,
        onGroupTap: (_) {},
        onBack: () {},
      ),
    );
  }

  Text _textWidget(WidgetTester tester, String text) {
    return tester.widget<Text>(find.text(text));
  }

  testWidgets('does not flatten sender and body into a single preview string', (
    tester,
  ) async {
    const chatSender = 'مرحبا Ali';
    const chatBody = 'Hello مرحبا 123';
    const announcementSender = 'Admin';
    const announcementBody = 'مرحبا Hello 123';

    await tester.pumpWidget(
      buildScreen(
        groups: [chatGroup, announcementGroup],
        latestMessages: {
          chatGroup.id: buildMessage(
            id: 'msg-chat',
            groupId: chatGroup.id,
            senderUsername: chatSender,
            text: chatBody,
          ),
          announcementGroup.id: buildMessage(
            id: 'msg-announcement',
            groupId: announcementGroup.id,
            senderUsername: announcementSender,
            text: announcementBody,
          ),
        },
      ),
    );

    expect(find.text('$chatSender: $chatBody'), findsNothing);
    expect(find.text('$announcementSender: $announcementBody'), findsNothing);
    expect(find.text(chatSender), findsOneWidget);
    expect(find.text(chatBody), findsOneWidget);
    expect(find.text(announcementSender), findsOneWidget);
    expect(find.text(announcementBody), findsOneWidget);
    expect(_textWidget(tester, chatBody).textDirection, TextDirection.ltr);
    expect(
      _textWidget(tester, announcementBody).textDirection,
      TextDirection.rtl,
    );
  });
}
