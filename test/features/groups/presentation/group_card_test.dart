import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_card.dart';

import '../../../shared/helpers/readability_test_helpers.dart';

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

  Widget buildTestWidget({
    GroupModel? group,
    int unreadCount = 0,
    String? lastMessageSender,
    String? lastMessageBody,
    String? lastMessageTime,
    BackgroundReadableColors readableColors = BackgroundReadableColors.dark,
  }) {
    return MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[readableColors]),
      home: Scaffold(
        backgroundColor: readableColors.surfaceBase,
        body: GroupCard(
          group: group ?? testGroup,
          lastMessageSender: lastMessageSender,
          lastMessageBody: lastMessageBody,
          lastMessageTime: lastMessageTime,
          unreadCount: unreadCount,
        ),
      ),
    );
  }

  testWidgets('renders group name and type badge', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.text('Test Group'), findsOneWidget);
    expect(find.text('Discussion'), findsOneWidget);
  });

  testWidgets('shows unread count when > 0', (tester) async {
    await tester.pumpWidget(buildTestWidget(unreadCount: 5));

    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('uses representative light readable roles', (tester) async {
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(
      buildTestWidget(
        readableColors: colors,
        lastMessageSender: 'Alice',
        lastMessageBody: 'Hello مرحبا from Daylight',
        lastMessageTime: '9:30 AM',
        unreadCount: 3,
      ),
    );

    final title = tester.widget<Text>(find.text('Test Group'));
    expectTextContrast(title.style!.color!, colors.surfaceBase);

    final sender = tester.widget<Text>(find.text('Alice'));
    expectTextContrast(sender.style!.color!, colors.surfaceBase);

    final body = tester.widget<Text>(find.text('Hello مرحبا from Daylight'));
    expectTextContrast(body.style!.color!, colors.surfaceBase);
  });
}
