import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late FakeBridge bridge;

  const groupId = 'group-repair';
  const adminPeerId = 'admin-peer';
  const adminTransport = 'admin-transport';
  const requesterPeerId = 'requester-peer';
  const requesterDeviceId = 'requester-device';

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    bridge = FakeBridge();

    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.utc(2026, 4, 5, 12),
        createdBy: adminPeerId,
        myRole: GroupRole.member,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: adminPeerId,
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        mlKemPublicKey: 'mlkem-admin',
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'admin-device',
            transportPeerId: adminTransport,
            deviceSigningPublicKey: 'sign-admin',
            mlKemPublicKey: 'mlkem-admin-device',
          ),
        ],
        joinedAt: DateTime.utc(2026, 4, 5, 12),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: requesterPeerId,
        username: 'Requester',
        role: MemberRole.writer,
        publicKey: 'pk-req',
        mlKemPublicKey: 'mlkem-req',
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: requesterDeviceId,
            transportPeerId: 'requester-transport',
            deviceSigningPublicKey: 'sign-req',
            mlKemPublicKey: 'mlkem-req-device',
          ),
        ],
        joinedAt: DateTime.utc(2026, 4, 5, 12, 1),
      ),
    );
  });

  GroupKeyRepairRequestSender buildSender({
    required Future<bool> Function(String, String) send,
    Future<bool> Function(String, String)? inbox,
  }) {
    return GroupKeyRepairRequestSender(
      bridge: bridge,
      groupRepo: groupRepo,
      getOwnPeerId: () async => requesterPeerId,
      getOwnDeviceId: () async => requesterDeviceId,
      getOwnPrivateKey: () async => 'sk-req',
      sendP2PMessage: send,
      storeP2PMessageInInbox: inbox,
    );
  }

  test(
    'sends one signed group_key_repair_request to the admin transport peer',
    () async {
      final sent = <(String, String)>[];
      final sender = buildSender(
        send: (peer, msg) async {
          sent.add((peer, msg));
          return true;
        },
      );

      await sender.call(
        const GroupKeyRepairRequest(
          groupId: groupId,
          keyEpoch: 3,
          reason: 'received_message_epoch_missing_local_key',
          messageId: 'msg-1',
        ),
      );

      expect(sent, hasLength(1));
      expect(sent.single.$1, adminTransport);

      final envelope = jsonDecode(sent.single.$2) as Map<String, dynamic>;
      expect(envelope['type'], 'group_key_repair_request');
      expect(envelope['version'], '1');
      final payload = envelope['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], groupId);
      expect(payload['keyEpoch'], 3);
      expect(payload['requesterPeerId'], requesterPeerId);
      expect(payload['requesterDeviceId'], requesterDeviceId);
      expect((payload['signature'] as String).isNotEmpty, isTrue);
      expect(payload['signedPayload'], isNotNull);

      // The signature MUST be produced via the real bridge sign command.
      expect(bridge.commandLog, contains('payload.sign'));
    },
  );

  test(
    'falls back to the relay inbox with the same envelope on send failure',
    () async {
      final sent = <(String, String)>[];
      final inboxed = <(String, String)>[];
      final sender = buildSender(
        send: (peer, msg) async {
          sent.add((peer, msg));
          return false; // direct send fails
        },
        inbox: (peer, msg) async {
          inboxed.add((peer, msg));
          return true;
        },
      );

      await sender.call(
        const GroupKeyRepairRequest(
          groupId: groupId,
          keyEpoch: 3,
          reason: 'live_decryption_failed',
        ),
      );

      expect(sent, hasLength(1));
      expect(inboxed, hasLength(1));
      expect(inboxed.single.$1, adminTransport);
      // Same envelope bytes go to the inbox.
      expect(inboxed.single.$2, sent.single.$2);

      final envelope = jsonDecode(inboxed.single.$2) as Map<String, dynamic>;
      expect(envelope['type'], 'group_key_repair_request');
    },
  );

  test('marked shell emits no signed key-repair network request', () async {
    await groupRepo.updateGroup(
      (await groupRepo.getGroup(
        groupId,
      ))!.copyWith(selfRemovedAt: DateTime.utc(2026, 7, 20)),
    );
    var directCalls = 0;
    var inboxCalls = 0;
    final sender = buildSender(
      send: (_, _) async {
        directCalls++;
        return true;
      },
      inbox: (_, _) async {
        inboxCalls++;
        return true;
      },
    );

    await sender.call(
      const GroupKeyRepairRequest(
        groupId: groupId,
        keyEpoch: 3,
        reason: 'live_decryption_failed',
      ),
    );

    expect(directCalls, 0);
    expect(inboxCalls, 0);
    expect(bridge.commandLog, isNot(contains('payload.sign')));
  });
}
