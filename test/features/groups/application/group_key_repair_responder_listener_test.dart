import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_key_repair_responder_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late FakeBridge bridge;
  late StreamController<ChatMessage> controller;
  late GroupKeyRepairResponderListener listener;
  late List<({String groupId, String peerId, int keyEpoch})> deliveries;

  const groupId = 'group-resp';
  const adminPeerId = 'admin-peer';
  const requesterPeerId = 'requester-peer';
  const requesterDeviceId = 'requester-device';
  const requesterSigningKey = 'sign-req';

  Future<void> saveActiveGroup() async {
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
        joinedAt: DateTime.utc(2026, 4, 5, 12),
      ),
    );
  }

  Future<void> saveRequesterMember() async {
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
            deviceSigningPublicKey: requesterSigningKey,
            mlKemPublicKey: 'mlkem-req-device',
          ),
        ],
        joinedAt: DateTime.utc(2026, 4, 5, 12, 1),
      ),
    );
  }

  Future<void> saveKeyAtEpoch(int epoch, String key) async {
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: epoch,
        encryptedKey: key,
        createdAt: DateTime.utc(2026, 4, 5, 12, epoch),
      ),
    );
  }

  String request({
    int keyEpoch = 2,
    String peerId = requesterPeerId,
    String deviceId = requesterDeviceId,
    String? signedPayload,
    String signature = 'fake-signature',
    String signatureAlgorithm = groupKeyRepairRequestSignatureAlgorithm,
  }) {
    final canonical = signedPayload ??
        canonicalGroupKeyRepairRequestSignedPayload(
          groupId: groupId,
          keyEpoch: keyEpoch,
          requesterPeerId: peerId,
          requesterDeviceId: deviceId,
        );
    return jsonEncode({
      'type': groupKeyRepairRequestType,
      'version': '1',
      'payload': {
        'groupId': groupId,
        'keyEpoch': keyEpoch,
        'requesterPeerId': peerId,
        'requesterDeviceId': deviceId,
        'signatureAlgorithm': signatureAlgorithm,
        'signedPayload': canonical,
        'signature': signature,
      },
    });
  }

  ChatMessage incoming(String content) => ChatMessage(
        from: 'requester-transport',
        to: 'me',
        content: content,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
      );

  setUp(() {
    groupRepo = InMemoryGroupRepository();
    bridge = FakeBridge(); // payload.verify defaults to valid: true
    controller = StreamController<ChatMessage>.broadcast();
    deliveries = [];
    listener = GroupKeyRepairResponderListener(
      groupKeyRepairRequestStream: controller.stream,
      groupRepo: groupRepo,
      bridge: bridge,
      getOwnPeerId: () async => adminPeerId,
      distributeGroupKeyAtEpochToPeer: ({
        required String groupId,
        required String peerId,
        required int keyEpoch,
      }) async {
        deliveries.add((groupId: groupId, peerId: peerId, keyEpoch: keyEpoch));
        return 1;
      },
    );
    listener.start();
  });

  tearDown(() {
    listener.dispose();
    controller.close();
  });

  test('re-delivers the EXACT requested epoch and mints no new epoch', () async {
    await saveActiveGroup();
    await saveRequesterMember();
    await saveKeyAtEpoch(1, 'key-v1');
    await saveKeyAtEpoch(2, 'key-v2');

    controller.add(incoming(request(keyEpoch: 2)));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(deliveries, hasLength(1));
    expect(deliveries.single.peerId, requesterPeerId);
    expect(deliveries.single.keyEpoch, 2);

    // No epoch minted: never call group:updateKey, never read getLatestKey to
    // promote. Latest persisted key is unchanged.
    expect(bridge.commandLog, isNot(contains('group:updateKey')));
    final latest = await groupRepo.getLatestKey(groupId);
    expect(latest!.keyGeneration, 2);
    expect(latest.encryptedKey, 'key-v2');
  });

  test('serves an old epoch the admin still holds (not getLatestKey)', () async {
    await saveActiveGroup();
    await saveRequesterMember();
    await saveKeyAtEpoch(1, 'key-v1');
    await saveKeyAtEpoch(5, 'key-v5');

    controller.add(incoming(request(keyEpoch: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(deliveries, hasLength(1));
    expect(deliveries.single.keyEpoch, 1);
  });

  test('rejects a request from a non-member', () async {
    await saveActiveGroup();
    // requester NOT saved as a member
    await saveKeyAtEpoch(2, 'key-v2');

    controller.add(incoming(request(keyEpoch: 2)));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(deliveries, isEmpty);
  });

  test('rejects a request with an invalid signature', () async {
    await saveActiveGroup();
    await saveRequesterMember();
    await saveKeyAtEpoch(2, 'key-v2');
    // Force verify to fail.
    bridge.responses['payload.verify'] = {'ok': true, 'valid': false};

    controller.add(incoming(request(keyEpoch: 2)));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(deliveries, isEmpty);
  });

  test('rejects a request whose signedPayload does not match the fields',
      () async {
    await saveActiveGroup();
    await saveRequesterMember();
    await saveKeyAtEpoch(2, 'key-v2');

    // Tampered signedPayload (claims epoch 9 inside, but fields say 2).
    final tampered = canonicalGroupKeyRepairRequestSignedPayload(
      groupId: groupId,
      keyEpoch: 9,
      requesterPeerId: requesterPeerId,
      requesterDeviceId: requesterDeviceId,
    );
    controller.add(incoming(request(keyEpoch: 2, signedPayload: tampered)));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(deliveries, isEmpty);
  });

  test('does nothing when the requested epoch is not held locally', () async {
    await saveActiveGroup();
    await saveRequesterMember();
    await saveKeyAtEpoch(2, 'key-v2');
    // epoch 7 not held

    controller.add(incoming(request(keyEpoch: 7)));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(deliveries, isEmpty);
  });

  test('rate-limits identical valid requests per (requester, groupId, epoch)',
      () async {
    await saveActiveGroup();
    await saveRequesterMember();
    await saveKeyAtEpoch(2, 'key-v2');
    await saveKeyAtEpoch(3, 'key-v3');

    // Three identical valid requests for epoch 2 → at most 1 re-delivery.
    controller.add(incoming(request(keyEpoch: 2)));
    controller.add(incoming(request(keyEpoch: 2)));
    controller.add(incoming(request(keyEpoch: 2)));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final epoch2 = deliveries.where((d) => d.keyEpoch == 2);
    expect(epoch2, hasLength(1));

    // A DISTINCT (groupId, epoch) is NOT throttled against epoch 2.
    controller.add(incoming(request(keyEpoch: 3)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final epoch3 = deliveries.where((d) => d.keyEpoch == 3);
    expect(epoch3, hasLength(1));
  });

  test('rejects when self does not hold rotate/creator rights', () async {
    // Self (adminPeerId here) is present but NOT the creator and NOT rotate-
    // authorized: make self a plain member instead.
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.utc(2026, 4, 5, 12),
        createdBy: 'some-other-creator',
        myRole: GroupRole.member,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: adminPeerId,
        username: 'NotAdmin',
        role: MemberRole.writer,
        publicKey: 'pk-admin',
        mlKemPublicKey: 'mlkem-admin',
        joinedAt: DateTime.utc(2026, 4, 5, 12),
      ),
    );
    await saveRequesterMember();
    await saveKeyAtEpoch(2, 'key-v2');

    controller.add(incoming(request(keyEpoch: 2)));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(deliveries, isEmpty);
  });
}
