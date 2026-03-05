import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';

void main() {
  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  final testMessages = [
    GroupMessage(
      id: 'msg-1',
      groupId: 'group-1',
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Hello everyone!',
      timestamp: DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      isIncoming: true,
    ),
  ];

  Widget buildTestWidget({
    List<GroupMessage> messages = const [],
    bool canWrite = true,
    GroupModel? group,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: GroupConversationScreen(
          group: group ?? testGroup,
          messages: messages,
          ownPeerId: 'peer-1',
          onSend: (_) {},
          onBack: () {},
          canWrite: canWrite,
        ),
      ),
    );
  }

  testWidgets('renders messages', (tester) async {
    await tester.pumpWidget(buildTestWidget(messages: testMessages));

    expect(find.text('Hello everyone!'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('shows compose area when canWrite is true', (tester) async {
    await tester.pumpWidget(buildTestWidget(canWrite: true));

    expect(find.text('Write something...'), findsOneWidget);
  });

  testWidgets('hides compose area for readers in announcement group',
      (tester) async {
    final announcementGroup = GroupModel(
      id: 'group-2',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'topic-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );

    await tester.pumpWidget(buildTestWidget(
      group: announcementGroup,
      canWrite: false,
    ));

    expect(
      find.text('Only admins can send messages in this group'),
      findsOneWidget,
    );
  });
}
