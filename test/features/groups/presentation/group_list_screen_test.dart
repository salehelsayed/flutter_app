import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';

void main() {
  final testGroups = [
    GroupModel(
      id: 'group-1',
      name: 'Alpha Group',
      type: GroupType.chat,
      topicName: 'topic-1',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-1',
      myRole: GroupRole.admin,
    ),
    GroupModel(
      id: 'group-2',
      name: 'Beta Announcements',
      type: GroupType.announcement,
      topicName: 'topic-2',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-1',
      myRole: GroupRole.member,
    ),
  ];

  Widget buildTestWidget({
    List<GroupModel> groups = const [],
    ValueChanged<GroupType>? onCreateGroup,
  }) {
    return MaterialApp(
      home: GroupListScreen(
        groups: groups,
        onGroupTap: (_) {},
        onCreateGroup: onCreateGroup ?? (_) {},
        onBack: () {},
      ),
    );
  }

  testWidgets('renders groups', (tester) async {
    await tester.pumpWidget(buildTestWidget(groups: testGroups));

    expect(find.text('Alpha Group'), findsOneWidget);
    expect(find.text('Beta Announcements'), findsOneWidget);
  });

  testWidgets('shows empty state when no groups', (tester) async {
    await tester.pumpWidget(buildTestWidget(groups: []));

    expect(find.text('No groups yet'), findsOneWidget);
  });

  testWidgets('shows type badges', (tester) async {
    await tester.pumpWidget(buildTestWidget(groups: testGroups));

    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Announce'), findsOneWidget);
  });

  testWidgets('shows FAB with + icon', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('tapping FAB opens menu with New Group, New Announce, New Q&A',
      (tester) async {
    await tester.pumpWidget(buildTestWidget());

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('New Group'), findsOneWidget);
    expect(find.text('New Announce'), findsOneWidget);
    expect(find.text('New Q&A'), findsOneWidget);
  });

  testWidgets('tapping New Group calls onCreateGroup with GroupType.chat',
      (tester) async {
    GroupType? captured;
    await tester.pumpWidget(
      buildTestWidget(onCreateGroup: (type) => captured = type),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('New Group'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(captured, GroupType.chat);
  });

  testWidgets(
      'tapping New Announce calls onCreateGroup with GroupType.announcement',
      (tester) async {
    GroupType? captured;
    await tester.pumpWidget(
      buildTestWidget(onCreateGroup: (type) => captured = type),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('New Announce'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(captured, GroupType.announcement);
  });

  testWidgets('tapping New Q&A calls onCreateGroup with GroupType.qa',
      (tester) async {
    GroupType? captured;
    await tester.pumpWidget(
      buildTestWidget(onCreateGroup: (type) => captured = type),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('New Q&A'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(captured, GroupType.qa);
  });
}
