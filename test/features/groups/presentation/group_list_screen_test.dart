import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

import '../../../shared/helpers/readability_test_helpers.dart';

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

  final pendingInvite = PendingGroupInvite(
    groupId: 'pending-1',
    inviteId: 'invite-1',
    payloadJson: '{}',
    groupName: 'Book Club',
    groupType: GroupType.chat,
    groupDescription: 'Read together',
    senderPeerId: 'peer-alice',
    senderUsername: 'Alice',
    createdBy: 'peer-alice',
    createdAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
    receivedAt: DateTime.now().toUtc().subtract(const Duration(hours: 6)),
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 6)),
  );

  final expiredPendingInvite = PendingGroupInvite(
    groupId: 'pending-expired',
    inviteId: 'invite-expired',
    payloadJson: '{}',
    groupName: 'Expired Invite',
    groupType: GroupType.chat,
    groupDescription: 'Too late',
    senderPeerId: 'peer-bob',
    senderUsername: 'Bob',
    createdBy: 'peer-bob',
    createdAt: DateTime.utc(2026, 3, 20),
    receivedAt: DateTime.utc(2026, 3, 21, 12),
    expiresAt: DateTime.utc(2026, 3, 28, 12),
  );

  Widget buildTestWidget({
    List<GroupModel> groups = const [],
    List<PendingGroupInvite> pendingInvites = const [],
    Map<String, GroupMessage?> latestMessages = const {},
    bool isLoading = false,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
  }) {
    return MaterialApp(
      home: GroupListScreen(
        groups: groups,
        pendingInvites: pendingInvites,
        latestMessages: latestMessages,
        isLoading: isLoading,
        onGroupTap: (_) {},
        onAcceptPendingInvite: (_) {},
        onDeclinePendingInvite: (_) {},
        onBack: () {},
        backgroundPreference: backgroundPreference,
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

  testWidgets('renders pending invite review card and actions', (tester) async {
    await tester.pumpWidget(buildTestWidget(pendingInvites: [pendingInvite]));

    expect(find.text('Pending Invites'), findsOneWidget);
    expect(find.text('Book Club'), findsOneWidget);
    expect(find.text('Invited by Alice'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pending-group-invite-accept-pending-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('pending-group-invite-decline-pending-1')),
      findsOneWidget,
    );
    expect(
      find.text('No joined groups yet. Accept an invite to add it here.'),
      findsOneWidget,
    );
  });

  testWidgets('renders expired pending invite as non-joinable', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(pendingInvites: [expiredPendingInvite]),
    );

    expect(find.text('Expired'), findsWidgets);
    final acceptButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('pending-group-invite-accept-pending-expired')),
    );
    expect(acceptButton.onPressed, isNull);
    expect(
      find.byKey(
        const ValueKey('pending-group-invite-decline-pending-expired'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not show FAB (FAB moved to Orbit screen)', (tester) async {
    await tester.pumpWidget(buildTestWidget());

    expect(find.byIcon(Icons.add), findsNothing);
  });

  testWidgets('shows expired backlog summary on the group card', (
    tester,
  ) async {
    final expiredGroup = testGroups.first.copyWith(
      lastBacklogExpiredAt: DateTime.utc(2026, 4, 5, 12),
    );

    await tester.pumpWidget(buildTestWidget(groups: [expiredGroup]));

    expect(find.text('Missed backlog expired after 7 days'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets('shows mixed-window backlog summary alongside latest message', (
    tester,
  ) async {
    final mixedGroup = testGroups.first.copyWith(
      lastBacklogExpiredAt: DateTime.utc(2026, 4, 5, 12),
      lastBacklogRetainedAt: DateTime.utc(2026, 4, 6, 12),
    );
    final retainedMessage = GroupMessage(
      id: 'msg-retained',
      groupId: mixedGroup.id,
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Recent backlog survived',
      timestamp: DateTime.utc(2026, 4, 6, 12, 30),
      createdAt: DateTime.utc(2026, 4, 6, 12, 30),
      isIncoming: true,
    );

    await tester.pumpWidget(
      buildTestWidget(
        groups: [mixedGroup],
        latestMessages: {mixedGroup.id: retainedMessage},
      ),
    );

    expect(find.text('Older backlog expired after 7 days'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Recent backlog survived'), findsOneWidget);
  });

  testWidgets('daylight lagoon keeps list and invite content readable', (
    tester,
  ) async {
    final latestMessage = GroupMessage(
      id: 'msg-daylight',
      groupId: testGroups.first.id,
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Hello مرحبا from Daylight',
      timestamp: DateTime.utc(2026, 4, 6, 12, 30),
      createdAt: DateTime.utc(2026, 4, 6, 12, 30),
      isIncoming: true,
    );

    await tester.pumpWidget(
      buildTestWidget(
        groups: [testGroups.first],
        pendingInvites: [pendingInvite],
        latestMessages: {testGroups.first.id: latestMessage},
        backgroundPreference: BackgroundPreference.daylightLagoon,
      ),
    );

    const colors = BackgroundReadableColors.representativeLight;
    final header = tester.widget<Text>(find.text('Groups'));
    expectTextContrast(header.style!.color!, colors.surfaceBase);

    final groupTitle = tester.widget<Text>(find.text('Alpha Group'));
    expectTextContrast(groupTitle.style!.color!, colors.surfaceBase);

    final inviteTitle = tester.widget<Text>(find.text('Book Club'));
    expectTextContrast(inviteTitle.style!.color!, colors.surfaceRaised);

    final inviteDescription = tester.widget<Text>(find.text('Read together'));
    expectTextContrast(inviteDescription.style!.color!, colors.surfaceRaised);
  });
}
