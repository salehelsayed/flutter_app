import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/admit_sibling_device_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';

/// Wave 2: the `device_announce` listener dispatch wires the keystone admission
/// to a real, account-signed wire trigger.
void main() {
  const groupId = 'group-1';
  const bobAccountKey = 'pk-bob';
  const siblingDeviceId = 'bob-tablet';

  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;
  late FakeBridge bridge;
  late StreamController<Map<String, dynamic>> source;
  late GroupMessageListener listener;
  late List<Map<String, Object?>> admitCalls;

  Future<SiblingDeviceAdmissionOutcome> admitSpy({
    required groupRepo,
    required String groupId,
    required String memberPeerId,
    required String announcedDeviceId,
    required String announcedTransportPeerId,
    required String announcedDeviceSigningPublicKey,
    required String verifiedAccountSigningPublicKey,
    String? announcedMlKemPublicKey,
    String? announcedKeyPackageId,
    String? announcedKeyPackagePublicMaterial,
  }) async {
    admitCalls.add({
      'memberPeerId': memberPeerId,
      'announcedDeviceId': announcedDeviceId,
      'announcedTransportPeerId': announcedTransportPeerId,
      'announcedDeviceSigningPublicKey': announcedDeviceSigningPublicKey,
      'verifiedAccountSigningPublicKey': verifiedAccountSigningPublicKey,
      'announcedMlKemPublicKey': announcedMlKemPublicKey,
    });
    return SiblingDeviceAdmissionOutcome.admitted;
  }

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    bridge = FakeBridge();
    source = StreamController<Map<String, dynamic>>.broadcast();
    admitCalls = [];

    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'G',
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        createdAt: DateTime.utc(2026, 1, 1),
        createdBy: 'alice',
        myRole: GroupRole.member,
      ),
    );
    // Bob is a member announcing a new device of his own account.
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'bob',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: bobAccountKey,
        mlKemPublicKey: 'mlkem-bob',
        joinedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    listener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      bridge: bridge,
      getSelfPeerId: () async => 'alice',
      admitSiblingDevice: admitSpy,
    );
    listener.start(source.stream);
    addTearDown(() async {
      await listener.stop();
      await source.close();
    });
  });

  Map<String, dynamic> announcedDevice() => {
    'deviceId': siblingDeviceId,
    'transportPeerId': siblingDeviceId,
    'deviceSigningPublicKey': 'bob-tablet-signing',
    'mlKemPublicKey': 'mlkem-bob-tablet',
  };

  Future<void> feed(Map<String, dynamic> systemPayload, String messageId) async {
    // The WIRE timestamp is the Go publish time — deliberately DIFFERENT from the
    // signed eventAt (12:00) below — so this exercises that the receiver
    // reconstructs eventAt from the signed payload (not the wire) before verify.
    source.add({
      'groupId': groupId,
      'senderId': 'bob',
      'senderUsername': 'Bob',
      'keyEpoch': 0,
      'messageId': messageId,
      'text': jsonEncode(systemPayload),
      'timestamp': DateTime.utc(2026, 5, 1, 12, 7, 30).toIso8601String(),
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }

  test('an account-signed device_announce admits the sibling device', () async {
    final signedEventAt = DateTime.utc(2026, 5, 1, 12);
    final signed = await signGroupSystemTransitionPayload(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      transitionType: 'device_announce',
      sourceEventId: 'device-announce-1',
      eventAt: signedEventAt,
      actorPeerId: 'bob',
      actorUsername: 'Bob',
      actorSigningPublicKey: bobAccountKey,
      actorPrivateKey: 'sk-bob',
      systemPayload: {
        '__sys': 'device_announce',
        // The emitter carries eventAt in the payload so the receiver can
        // reconstruct the SAME signed instant (the wire timestamp differs).
        'eventAt': signedEventAt.toIso8601String(),
        'announcedDevice': announcedDevice(),
      },
    );

    await feed(signed, 'device-announce-1');

    expect(admitCalls, hasLength(1));
    final call = admitCalls.single;
    expect(call['memberPeerId'], 'bob');
    expect(call['announcedDeviceId'], siblingDeviceId);
    expect(call['announcedMlKemPublicKey'], 'mlkem-bob-tablet');
    // The trust anchor is bob's ACCOUNT key, resolved from the roster.
    expect(call['verifiedAccountSigningPublicKey'], bobAccountKey);
  });

  test('a device_announce WITHOUT a signed audit is refused', () async {
    await feed(
      {'__sys': 'device_announce', 'announcedDevice': announcedDevice()},
      'device-announce-unsigned',
    );
    expect(admitCalls, isEmpty);
  });

  test(
    're-announce of an ALREADY-ROSTERED device still verifies (account-key '
    'resolution) and re-arms admission',
    () async {
      // The announced device is already on bob's roster (a re-announce, e.g. on
      // a later restart). The signed audit is account-key-signed, so the
      // receiver MUST resolve the account key (not the per-device key) or verify
      // would fail and re-arm would never fire.
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: bobAccountKey,
          mlKemPublicKey: 'mlkem-bob',
          devices: [
            const GroupMemberDeviceIdentity(
              deviceId: siblingDeviceId,
              transportPeerId: siblingDeviceId,
              deviceSigningPublicKey: 'bob-tablet-signing',
              mlKemPublicKey: 'mlkem-bob-tablet',
            ),
          ],
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      final signedEventAt = DateTime.utc(2026, 5, 1, 12);
      final signed = await signGroupSystemTransitionPayload(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        transitionType: 'device_announce',
        sourceEventId: 'device-announce-reannounce',
        eventAt: signedEventAt,
        actorPeerId: 'bob',
        actorUsername: 'Bob',
        actorSigningPublicKey: bobAccountKey,
        actorPrivateKey: 'sk-bob',
        systemPayload: {
          '__sys': 'device_announce',
          'eventAt': signedEventAt.toIso8601String(),
          'announcedDevice': announcedDevice(),
        },
      );

      await feed(signed, 'device-announce-reannounce');

      expect(admitCalls, hasLength(1));
      expect(admitCalls.single['verifiedAccountSigningPublicKey'], bobAccountKey);
    },
  );
}
