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
    bool isLoading = false,
  }) {
    return MaterialApp(
      home: GroupListScreen(
        groups: groups,
        isLoading: isLoading,
        onGroupTap: (_) {},
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

  testWidgets('shows loading placeholders while groups are loading', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(isLoading: true));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('group-loading-row-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-loading-row-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-loading-row-2')), findsOneWidget);
    expect(find.text('No groups yet'), findsNothing);
  });

  testWidgets(
    'shows group list when groups are available even if isLoading is still true',
    (tester) async {
      await tester.pumpWidget(
        buildTestWidget(groups: testGroups, isLoading: true),
      );

      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-loading-row-0')), findsNothing);
    },
  );

  testWidgets('shows type badges', (tester) async {
    await tester.pumpWidget(buildTestWidget(groups: testGroups));

    expect(find.text('Discussion'), findsOneWidget);
    expect(find.text('Announce'), findsOneWidget);
  });

  testWidgets('does not show FAB (FAB moved to Orbit screen)', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.byIcon(Icons.add), findsNothing);
  });
}
