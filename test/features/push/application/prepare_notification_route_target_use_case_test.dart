import 'dart:convert';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';

import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_pending_key_repair_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/prepare_notification_route_target_use_case.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../conversation/domain/repositories/fake_media_attachment_repository.dart';

void main() {
  group('prepareNotificationRouteTarget warmPeer forwarding (FDC-04 WIRE-1)', () {
    // TC-04-10b: the notif-tap warm hook is actually WIRED THROUGH
    // `prepareNotificationRouteTarget` into `prepareNotificationOpen` — not a
    // dead optional param. Because the hook defaults to null, a null/dead wire
    // at this seam would pass TC-04-10 (which calls prepareNotificationOpen
    // directly) green while notif-tap warm silently never fires in production.
    // Mutation: stop passing `warmPeer: warmPeer` from
    // prepareNotificationRouteTarget into prepareNotificationOpen → re-red.
    test('TC-04-10b: forwards warmPeer into prepareNotificationOpen for a '
        'conversation route', () async {
      final warmed = <String>[];
      await prepareNotificationRouteTarget(
        routeTarget: const NotificationRouteTarget.conversation('peer-123'),
        drainOfflineInbox: () async {},
        bridge: PassthroughCryptoBridge(),
        groupRepository: null,
        groupMessageRepository: null,
        mediaAttachmentRepository: FakeMediaAttachmentRepository(),
        reactionRepository: null,
        groupPendingReactionRepository: null,
        warmPeer: (pid) async {
          warmed.add(pid);
        },
      );
      expect(warmed, ['peer-123']);
    });

    // A null warmPeer wire (the production path before main.dart supplies the
    // real fn) must be harmless — the route still completes without throwing.
    test(
      'TC-04-10b: a null warmPeer wire is harmless for a conversation route',
      () async {
        final result = prepareNotificationRouteTarget(
          routeTarget: const NotificationRouteTarget.conversation('peer-123'),
          drainOfflineInbox: () async {},
          bridge: PassthroughCryptoBridge(),
          groupRepository: null,
          groupMessageRepository: null,
          mediaAttachmentRepository: FakeMediaAttachmentRepository(),
          reactionRepository: null,
          groupPendingReactionRepository: null,
        );
        await expectLater(result, completes);
      },
    );
  });

  for (final activeSender in [false, true]) {
    test(
      'group notification persists missing-key replay and '
      '${activeSender ? 'emits the active repair request' : 'keeps the log-only default'}',
      () async {
        final bridge = FakeBridge();
        final groups = InMemoryGroupRepository();
        final messages = InMemoryGroupMessageRepository();
        final pending = InMemoryGroupPendingKeyRepairRepository();
        final now = DateTime.now().toUtc();
        await groups.saveGroup(
          GroupModel(
            id: 'group-repair',
            name: 'Repair group',
            type: GroupType.chat,
            topicName: 'repair-topic',
            createdAt: now.subtract(const Duration(days: 1)),
            createdBy: 'peer-self',
            myRole: GroupRole.admin,
          ),
        );
        for (final peer in ['peer-self', 'peer-sender']) {
          await groups.saveMember(
            GroupMember(
              groupId: 'group-repair',
              peerId: peer,
              role: peer == 'peer-self' ? MemberRole.admin : MemberRole.writer,
              publicKey: peer == 'peer-self' ? 'pk-self' : 'pk-sender',
              joinedAt: now.subtract(const Duration(days: 1)),
            ),
          );
        }
        await groups.saveKey(
          GroupKeyInfo(
            groupId: 'group-repair',
            keyGeneration: 1,
            encryptedKey: 'epoch-one-key',
            createdAt: now,
          ),
        );
        final envelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groups,
          groupId: 'group-repair',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode({
            'groupId': 'group-repair',
            'senderId': 'peer-sender',
            'keyEpoch': 2,
            'messageId': 'missing-key-message',
            'text': 'Needs epoch two',
            'timestamp': now.toIso8601String(),
          }),
          messageId: 'missing-key-message',
          senderPeerId: 'peer-sender',
          senderPublicKey: 'pk-sender',
          senderPrivateKey: 'sk-sender',
          keyInfo: GroupKeyInfo(
            groupId: 'group-repair',
            keyGeneration: 2,
            encryptedKey: 'epoch-two-key',
            createdAt: now,
          ),
        );
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            {
              'from': 'peer-sender',
              'message': envelope,
              'timestamp': now.millisecondsSinceEpoch,
            },
          ],
          'cursor': '',
        };
        final requests = <GroupKeyRepairRequest>[];
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));
        await prepareNotificationRouteTarget(
          routeTarget: const NotificationRouteTarget.group(
            'group-repair',
            messageId: 'missing-key-message',
          ),
          drainOfflineInbox: () async {},
          bridge: bridge,
          groupRepository: groups,
          groupMessageRepository: messages,
          pendingKeyRepairRepository: pending,
          requestGroupKeyRepair: activeSender ? requests.add : null,
          mediaAttachmentRepository: FakeMediaAttachmentRepository(),
          reactionRepository: null,
          groupPendingReactionRepository: null,
          selfPeerId: 'peer-self',
        );
        expect(pending.repairs.values, hasLength(1));
        final repair = pending.repairs.values.single;
        expect(repair.groupId, 'group-repair');
        expect(repair.keyEpoch, 2);
        expect(repair.status, groupPendingKeyRepairStatusPendingKey);
        final placeholder = await messages.getMessage('missing-key-message');
        expect(placeholder, isNotNull);
        expect(placeholder!.status, groupPendingKeyRepairStatusPendingKey);
        expect(bridge.commandLog, contains('group:inboxRetrieveCursor'));
        expect(bridge.commandLog, isNot(contains('group.decrypt')));
        final loggedRequests = events.where(
          (event) => event['event'] == 'GROUP_KEY_REPAIR_REQUESTED',
        );
        if (activeSender) {
          expect(
            requests,
            hasLength(1),
            reason: 'the configured active repair sender must run',
          );
          expect(requests.single.groupId, 'group-repair');
          expect(requests.single.keyEpoch, 2);
          expect(requests.single.reason, groupKeyRepairReasonOfflineMissingKey);
          expect(loggedRequests, isEmpty);
        } else {
          expect(requests, isEmpty);
          expect(loggedRequests, hasLength(1));
        }
      },
    );
  }
}
