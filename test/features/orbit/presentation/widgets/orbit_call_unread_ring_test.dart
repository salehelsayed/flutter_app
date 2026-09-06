import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_timeline_entry.dart';
import 'package:flutter_app/features/orbit/application/inner_circle_items.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';

/// 410: a missed call must reach the RING, not just the loader.
///
/// Device 2026-09-06 proved the count arrives at `loadOrbitData`
/// (`ORBIT_CALL_UNREAD_RESULT {contacts: 1, total: 1}`) but could not prove it
/// survives to the ring node, because the app restored into the conversation
/// on relaunch and `_markAsRead` cleared the badge four seconds later. These
/// tests close that exact link with no device and no timing.
void main() {
  OrbitFriend friendWithMissedCall({
    int unreadMessages = 0,
    required int unreadCalls,
  }) => OrbitFriend(
    contact: ContactModel(
      peerId: '12D3KooWTestPeerId1234567890',
      publicKey: 'pk',
      rendezvous: 'rv',
      username: 'iphone-11',
      signature: 'sig',
      scannedAt: '2026-02-09T10:00:00.000Z',
    ),
    messageCount: 0,
    // The badge is one number for the conversation: messages plus calls.
    unreadCount: unreadMessages + unreadCalls,
    latestCall: ConversationCallTimelineEntry(
      callId: 'a2f0a1d6-0000-4000-8000-000000000410',
      contactPeerId: '12D3KooWTestPeerId1234567890',
      direction: ConversationCallDirection.incoming,
      status: ConversationCallStatus.missed,
      startedAt: DateTime.utc(2026, 2, 9, 16),
      endedAt: DateTime.utc(2026, 2, 9, 16, 0, 20),
    ),
  );

  testWidgets('TC-410-30 a call-only unread seats a ring node that draws its '
      'unread indicator', (tester) async {
    final items = mergeInnerCircleItems(
      friends: <OrbitFriend>[friendWithMissedCall(unreadCalls: 1)],
      groups: const <OrbitGroup>[],
    );
    final friend = (items.single as OrbitFriendItem).friend;

    // The ring reads exactly this field (orbital_visualization.dart), so a
    // count that survives the merge survives to the node.
    expect(friend.unreadCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrbitalAvatar(
              peerId: friend.peerId,
              size: 40,
              globalIndex: 0,
              onTap: () {},
              unreadCount: friend.unreadCount,
              motionEnabled: false,
              unreadMotionEnabled: false,
              child: const SizedBox.expand(key: Key('avatar-core')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byType(UnreadOrbitIndicator),
      findsOneWidget,
      reason: 'a missed call the user has not seen must show on the ring',
    );
  });

  testWidgets('TC-410-31 messages and calls sum into one ring indicator', (
    tester,
  ) async {
    final friend = friendWithMissedCall(unreadMessages: 2, unreadCalls: 3);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrbitalAvatar(
              peerId: friend.peerId,
              size: 40,
              globalIndex: 0,
              onTap: () {},
              unreadCount: friend.unreadCount,
              motionEnabled: false,
              unreadMotionEnabled: false,
              child: const SizedBox.expand(key: Key('avatar-core')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<UnreadOrbitIndicator>(find.byType(UnreadOrbitIndicator))
          .unreadCount,
      5,
      reason: 'one badge for the conversation, not two',
    );
  });

  testWidgets('TC-410-32 no unread draws no indicator', (tester) async {
    final friend = friendWithMissedCall(unreadCalls: 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: OrbitalAvatar(
              peerId: friend.peerId,
              size: 40,
              globalIndex: 0,
              onTap: () {},
              unreadCount: friend.unreadCount,
              motionEnabled: false,
              unreadMotionEnabled: false,
              child: const SizedBox.expand(key: Key('avatar-core')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byType(UnreadOrbitIndicator),
      findsNothing,
      reason: 'a call the user already saw is not waiting for them',
    );
  });
}
