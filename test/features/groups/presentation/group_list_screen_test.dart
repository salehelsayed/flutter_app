import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_list_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
    Map<String, int> rejoinAttempts = const <String, int>{},
    bool isLoading = false,
    ValueChanged<GroupModel>? onRetryStuckRejoin,
    ValueChanged<GroupModel>? onLeaveStuckGroup,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupListScreen(
        groups: groups,
        pendingInvites: pendingInvites,
        latestMessages: latestMessages,
        rejoinAttempts: rejoinAttempts,
        isLoading: isLoading,
        onGroupTap: (_) {},
        onAcceptPendingInvite: (_) {},
        onDeclinePendingInvite: (_) {},
        onRetryStuckRejoin: onRetryStuckRejoin,
        onLeaveStuckGroup: onLeaveStuckGroup,
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

  group('G2 stuck-rejoin retry/leave UX', () {
    testWidgets(
      'a stuck group (attempt >= 10) shows the give-up badge with Retry + Leave',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            groups: [testGroups.first],
            rejoinAttempts: const {'group-1': 11},
            onRetryStuckRejoin: (_) {},
            onLeaveStuckGroup: (_) {},
          ),
        );

        expect(find.text("Couldn't join — retry"), findsOneWidget);
        expect(
          find.byKey(const ValueKey('group-stuck-retry-group-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('group-stuck-leave-group-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'tapping "Retry now" invokes onRetryStuckRejoin with the group',
      (tester) async {
        GroupModel? retried;
        await tester.pumpWidget(
          buildTestWidget(
            groups: [testGroups.first],
            rejoinAttempts: const {'group-1': 10},
            onRetryStuckRejoin: (g) => retried = g,
            onLeaveStuckGroup: (_) {},
          ),
        );

        await tester.tap(
          find.byKey(const ValueKey('group-stuck-retry-group-1')),
        );
        await tester.pump();

        expect(retried?.id, 'group-1');
      },
    );

    testWidgets('tapping "Leave" invokes onLeaveStuckGroup with the group', (
      tester,
    ) async {
      GroupModel? left;
      await tester.pumpWidget(
        buildTestWidget(
          groups: [testGroups.first],
          rejoinAttempts: const {'group-1': 10},
          onRetryStuckRejoin: (_) {},
          onLeaveStuckGroup: (g) => left = g,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('group-stuck-leave-group-1')));
      await tester.pump();

      expect(left?.id, 'group-1');
    });

    testWidgets(
      'a non-stuck group (attempt < 10) shows the passive Joining… badge with '
      'no actions',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            groups: [testGroups.first],
            rejoinAttempts: const {'group-1': 3},
            onRetryStuckRejoin: (_) {},
            onLeaveStuckGroup: (_) {},
          ),
        );

        expect(find.text('Joining…'), findsOneWidget);
        expect(find.text("Couldn't join — retry"), findsNothing);
        expect(
          find.byKey(const ValueKey('group-stuck-retry-group-1')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('group-stuck-leave-group-1')),
          findsNothing,
        );
      },
    );
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

  testWidgets('IR-016 shows expired backlog summary on the group card', (
    tester,
  ) async {
    final expiredGroup = testGroups.first.copyWith(
      lastBacklogExpiredAt: DateTime.utc(2026, 4, 5, 12),
    );

    await tester.pumpWidget(buildTestWidget(groups: [expiredGroup]));

    expect(find.text('Missed backlog expired after 7 days'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets(
    'IR-016 shows mixed-window backlog summary alongside latest message',
    (tester) async {
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
    },
  );

  testWidgets(
    'GPL-15F Group List latest body is generic for private and unsupported '
    'parents while ordinary text remains unchanged',
    (tester) async {
      GroupMessage latest({
        required String id,
        required String text,
        required GroupPrivateMediaPolicy policy,
      }) => GroupMessage(
        id: id,
        groupId: testGroups.first.id,
        senderPeerId: 'peer-2',
        senderUsername: 'Alice',
        text: text,
        timestamp: DateTime.utc(2026, 4, 6, 12, 30),
        createdAt: DateTime.utc(2026, 4, 6, 12, 30),
        isIncoming: true,
        privateMediaPolicy: policy,
      );

      for (final testCase
          in <({String id, String text, GroupPrivateMediaPolicy policy})>[
            (
              id: 'private-latest',
              text: 'private list caption',
              policy: const GroupPrivateMediaPolicy.viewOnce(),
            ),
            (
              id: 'unsupported-latest',
              text: 'future list caption',
              policy: const GroupPrivateMediaPolicy.unsupported(
                sourceVersion: 9,
              ),
            ),
          ]) {
        await tester.pumpWidget(
          buildTestWidget(
            groups: [testGroups.first],
            latestMessages: {
              testGroups.first.id: latest(
                id: testCase.id,
                text: testCase.text,
                policy: testCase.policy,
              ),
            },
          ),
        );

        expect(find.text('Media unavailable'), findsOneWidget);
        expect(find.text(testCase.text), findsNothing);
      }

      await tester.pumpWidget(
        buildTestWidget(
          groups: [testGroups.first],
          latestMessages: {
            testGroups.first.id: latest(
              id: 'ordinary-latest',
              text: 'ordinary list caption',
              policy: const GroupPrivateMediaPolicy.ordinary(),
            ),
          },
        ),
      );

      expect(find.text('ordinary list caption'), findsOneWidget);
      expect(find.text('Media unavailable'), findsNothing);
    },
  );

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

  group('localized last-message timestamps (finding 11 item 3)', () {
    // Fixed local wall-clock 14:05 so toLocal() is a no-op (TZ-independent).
    final localAfternoon = DateTime(2026, 2, 9, 14, 5);

    GroupMessage lastMessageAt(DateTime when) => GroupMessage(
      id: 'msg-time',
      groupId: testGroups.first.id,
      senderPeerId: 'peer-2',
      senderUsername: 'Alice',
      text: 'Latest',
      timestamp: when,
      createdAt: when,
      isIncoming: true,
    );

    testWidgets('de renders the 24-hour list time without an AM/PM marker', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestWidget(
          groups: [testGroups.first],
          latestMessages: {testGroups.first.id: lastMessageAt(localAfternoon)},
          locale: const Locale('de'),
        ),
      );
      await tester.pump();

      expect(find.textContaining('14:05'), findsOneWidget);
      expect(find.textContaining('PM'), findsNothing);
    });

    testWidgets('en keeps the 12-hour list time', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          groups: [testGroups.first],
          latestMessages: {testGroups.first.id: lastMessageAt(localAfternoon)},
          locale: const Locale('en'),
        ),
      );
      await tester.pump();

      final expected = intl.DateFormat.jm('en').format(localAfternoon);
      expect(expected, contains('PM'));
      expect(find.textContaining(expected), findsOneWidget);
    });
  });
}
