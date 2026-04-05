import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/application/set_group_muted_use_case.dart';

import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/group_test_user.dart';

Future<void> waitForCondition(
  Future<bool> Function() condition, {
  int maxTicks = 40,
}) async {
  for (var tick = 0; tick < maxTicks; tick++) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }

  fail('Condition was not met in time');
}

Future<void> mirrorJoinedGroupState({
  required GroupTestUser source,
  required GroupTestUser target,
  required String groupId,
}) async {
  final group = await source.groupRepo.getGroup(groupId);
  expect(group, isNotNull);
  await target.groupRepo.saveGroup(group!);

  final members = await source.groupRepo.getMembers(groupId);
  for (final member in members) {
    await target.groupRepo.saveMember(member);
  }

  final latestKey = await source.groupRepo.getLatestKey(groupId);
  if (latestKey != null) {
    await target.groupRepo.saveKey(latestKey);
  }

  target.subscribeToGroup(groupId);
}

void main() {
  group('same-user multi-device convergence', () {
    test(
      'joined sibling device stores same-user live publish as local sent history',
      () async {
        final network = FakeGroupPubSubNetwork();
        final phone = GroupTestUser.create(
          peerId: 'peer-shared',
          deviceId: 'peer-shared-phone',
          username: 'Alice',
          network: network,
        );
        final tablet = GroupTestUser.create(
          peerId: 'peer-shared',
          deviceId: 'peer-shared-tablet',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        addTearDown(() {
          phone.dispose();
          tablet.dispose();
          bob.dispose();
        });

        phone.start();
        tablet.start();
        bob.start();

        const groupId = 'group-multi-device-shared-send';
        await phone.createGroup(groupId: groupId, name: 'Shared Devices');
        await phone.addMember(groupId: groupId, invitee: bob);
        await mirrorJoinedGroupState(
          source: phone,
          target: tablet,
          groupId: groupId,
        );

        final subscribers = network.getSubscribers(groupId);
        expect(
          subscribers.where((peerId) => peerId == 'peer-shared'),
          hasLength(2),
        );

        await phone.sendGroupMessage(groupId: groupId, text: 'From phone');

        await waitForCondition(
          () async => await tablet.msgRepo.getMessageCount(groupId) == 1,
        );
        await waitForCondition(
          () async => await bob.msgRepo.getMessageCount(groupId) == 1,
        );

        final tabletMessage = await tablet.msgRepo.getLatestMessage(groupId);
        expect(tabletMessage, isNotNull);
        expect(tabletMessage!.text, 'From phone');
        expect(tabletMessage.senderPeerId, 'peer-shared');
        expect(tabletMessage.isIncoming, isFalse);
        expect(tabletMessage.status, 'sent');
        expect(await tablet.msgRepo.getUnreadCount(groupId), 0);

        final phoneMessage = await phone.msgRepo.getLatestMessage(groupId);
        expect(phoneMessage, isNotNull);
        expect(phoneMessage!.text, 'From phone');
        expect(await phone.msgRepo.getMessageCount(groupId), 1);
      },
    );

    test(
      'joined sibling device converges membership updates without duplicate local membership',
      () async {
        final network = FakeGroupPubSubNetwork();
        final phone = GroupTestUser.create(
          peerId: 'peer-shared',
          deviceId: 'peer-shared-phone',
          username: 'Alice',
          network: network,
        );
        final tablet = GroupTestUser.create(
          peerId: 'peer-shared',
          deviceId: 'peer-shared-tablet',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        addTearDown(() {
          phone.dispose();
          tablet.dispose();
          bob.dispose();
          charlie.dispose();
        });

        phone.start();
        tablet.start();
        bob.start();
        charlie.start();

        const groupId = 'group-multi-device-membership';
        await phone.createGroup(groupId: groupId, name: 'Shared Devices');
        await phone.addMember(groupId: groupId, invitee: bob);
        await mirrorJoinedGroupState(
          source: phone,
          target: tablet,
          groupId: groupId,
        );

        await phone.addMember(groupId: groupId, invitee: charlie);
        await phone.broadcastMemberAdded(groupId: groupId, newMember: charlie);

        await waitForCondition(() async {
          final members = await tablet.groupRepo.getMembers(groupId);
          return members.any((member) => member.peerId == 'peer-charlie');
        });

        final tabletMembers = await tablet.groupRepo.getMembers(groupId);
        expect(tabletMembers.map((member) => member.peerId).toSet(), {
          'peer-shared',
          'peer-bob',
          'peer-charlie',
        });
        expect(
          tabletMembers.where((member) => member.peerId == 'peer-shared'),
          hasLength(1),
        );
      },
    );

    test(
      'mute, unread, and local notifications stay device-local across joined sibling devices',
      () async {
        final network = FakeGroupPubSubNetwork();
        final phoneNotifications = FakeNotificationService();
        final tabletNotifications = FakeNotificationService();
        final phone = GroupTestUser.create(
          peerId: 'peer-shared',
          deviceId: 'peer-shared-phone',
          username: 'Alice',
          network: network,
          notificationService: phoneNotifications,
          groupConversationTracker: ActiveConversationTracker(),
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        final tablet = GroupTestUser.create(
          peerId: 'peer-shared',
          deviceId: 'peer-shared-tablet',
          username: 'Alice',
          network: network,
          notificationService: tabletNotifications,
          groupConversationTracker: ActiveConversationTracker(),
          getAppLifecycleState: () => AppLifecycleState.paused,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        addTearDown(() {
          phone.dispose();
          tablet.dispose();
          bob.dispose();
        });

        phone.start();
        tablet.start();
        bob.start();

        const groupId = 'group-multi-device-local-state';
        await phone.createGroup(groupId: groupId, name: 'Shared Devices');
        await phone.addMember(groupId: groupId, invitee: bob);
        await mirrorJoinedGroupState(
          source: phone,
          target: tablet,
          groupId: groupId,
        );

        await setGroupMuted(
          groupRepo: phone.groupRepo,
          groupId: groupId,
          isMuted: true,
        );

        expect((await phone.groupRepo.getGroup(groupId))!.isMuted, isTrue);
        expect((await tablet.groupRepo.getGroup(groupId))!.isMuted, isFalse);

        await bob.sendGroupMessage(groupId: groupId, text: 'From Bob');

        await waitForCondition(
          () async => await phone.msgRepo.getMessageCount(groupId) == 1,
        );
        await waitForCondition(
          () async => await tablet.msgRepo.getMessageCount(groupId) == 1,
        );
        await waitForCondition(
          () async => tabletNotifications.shown.length == 1,
        );

        expect(phoneNotifications.shown, isEmpty);
        expect(tabletNotifications.shown, hasLength(1));
        expect(
          tabletNotifications.shown.single.contactPeerId,
          'group:$groupId',
        );

        expect(await phone.msgRepo.getUnreadCount(groupId), 1);
        expect(await tablet.msgRepo.getUnreadCount(groupId), 1);

        await phone.msgRepo.markAsRead(groupId);

        expect(await phone.msgRepo.getUnreadCount(groupId), 0);
        expect(await tablet.msgRepo.getUnreadCount(groupId), 1);
      },
    );
  });
}
