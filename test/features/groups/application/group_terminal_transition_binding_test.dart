import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  const groupId = 'r2-terminal-group';
  const adminId = 'peer-admin';
  const selfId = 'peer-member';
  final joinedAt = DateTime.utc(2026, 9, 27, 12);
  final eventAt = joinedAt.add(const Duration(minutes: 1));
  late InMemoryGroupRepository repo;
  late InMemoryGroupMessageRepository messages;
  late FakeBridge bridge;
  late GroupMessageListener listener;
  late StreamController<Map<String, dynamic>> source;
  late List<Map<String, dynamic>> flows;
  late List<String> projected;
  late List<String> removed;
  late List<String> audits;

  Future<void> saveAdmin({
    MemberRole role = MemberRole.admin,
    List<GroupMemberDeviceIdentity> devices = const [],
  }) => repo.saveMember(
    GroupMember(
      groupId: groupId,
      peerId: adminId,
      username: 'Admin',
      publicKey: 'pk-admin',
      role: role,
      devices: devices,
      joinedAt: joinedAt,
    ),
  );

  setUp(() async {
    repo = InMemoryGroupRepository();
    messages = InMemoryGroupMessageRepository();
    bridge = FakeBridge();
    flows = [];
    projected = [];
    removed = [];
    audits = [];
    debugSetFlowEventSink(flows.add);
    await repo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'R2 group',
        type: GroupType.chat,
        topicName: 'r2-topic',
        createdAt: joinedAt,
        createdBy: adminId,
        myRole: GroupRole.member,
      ),
    );
    await saveAdmin();
    await repo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: selfId,
        username: 'Member',
        publicKey: 'pk-member',
        role: MemberRole.writer,
        joinedAt: joinedAt,
      ),
    );
    await repo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'fixture-group-key',
        createdAt: joinedAt,
      ),
    );
    listener = GroupMessageListener(
      groupRepo: repo,
      msgRepo: messages,
      bridge: bridge,
      getSelfPeerId: () async => selfId,
      appendGroupEventLogEntry:
          ({
            required groupId,
            required eventType,
            required sourcePeerId,
            required sourceEventId,
            required sourceTimestamp,
            required payload,
            createdAt,
          }) async {
            audits.add(sourceEventId);
            return <String, Object?>{};
          },
    );
    source = StreamController<Map<String, dynamic>>();
    listener.start(source.stream);
    final messageSub = listener.groupMessageStream.listen(
      (m) => projected.add(m.id),
    );
    final removedSub = listener.groupRemovedStream.listen(removed.add);
    addTearDown(() async {
      await listener.stop();
      await source.close();
      await messageSub.cancel();
      await removedSub.cancel();
      listener.dispose();
      debugSetFlowEventSink(null);
    });
  });

  Future<Map<String, dynamic>> envelope(
    String type, {
    String? signedDevice,
    String? signedTransport,
    String? observedDevice = adminId,
    String? observedTransport = adminId,
    String? preState,
    String target = selfId,
  }) async {
    final payload = await signGroupSystemTransitionPayload(
      bridge: bridge,
      groupRepo: repo,
      groupId: groupId,
      transitionType: type,
      sourceEventId: 'r2-$type',
      eventAt: eventAt,
      actorPeerId: adminId,
      actorUsername: 'Admin',
      actorSigningPublicKey: 'pk-admin',
      actorPrivateKey: 'sk-admin',
      actorDeviceId: signedDevice,
      actorTransportPeerId: signedTransport,
      preTransitionStateHash: preState,
      systemPayload: {
        '__sys': type,
        if (type == 'group_dissolved') ...{
          'dissolvedAt': eventAt.toIso8601String(),
          'dissolvedBy': adminId,
        } else ...{
          'removedAt': eventAt.toIso8601String(),
          'member': {'peerId': target, 'username': 'Member'},
        },
      },
    );
    return {
      'groupId': groupId,
      'senderId': adminId,
      'senderUsername': 'Admin',
      'senderDeviceId': ?observedDevice,
      'transportPeerId': ?observedTransport,
      'messageId': 'r2-$type',
      'text': jsonEncode(payload),
      'timestamp': eventAt.toIso8601String(),
    };
  }

  Future<void> expectApplied(String type) async {
    final group = (await repo.getGroup(groupId))!;
    if (type == 'group_dissolved') {
      expect(group.isDissolved, isTrue);
      expect(group.dissolvedBy, adminId);
    } else {
      expect(await repo.getMember(groupId, selfId), isNull);
      expect(group.selfRemovedAt, eventAt);
      expect(await repo.getLatestKey(groupId), isNull);
      expect(removed, [groupId]);
    }
    expect(audits, ['r2-$type']);
    expect(projected, hasLength(1));
    expect(bridge.commandLog.where((c) => c == 'group:leave'), hasLength(1));
    expect(
      flows.where(
        (f) => f['event'] == 'GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED',
      ),
      isEmpty,
    );
  }

  Future<void> expectUnchanged() async {
    expect((await repo.getGroup(groupId))!.isDissolved, isFalse);
    expect(await repo.getMember(groupId, selfId), isNotNull);
    expect(await repo.getLatestKey(groupId), isNotNull);
    expect(audits, isEmpty);
    expect(projected, isEmpty);
    expect(removed, isEmpty);
    expect(bridge.commandLog, isNot(contains('group:leave')));
  }

  for (final type in ['group_dissolved', 'member_removed']) {
    for (final delivery in ['live', 'inbox']) {
      test(
        'R2 $type accepts legacy account audit via $delivery and deduplicates retry',
        () async {
          // Go stamps both account aliases on live publication. Legacy inbox
          // recovery can supply only transportPeerId. The inner audit has neither.
          final data = await envelope(
            type,
            observedDevice: delivery == 'live' ? adminId : null,
          );
          if (delivery == 'live') {
            final applied = listener.groupMessageStream.first;
            source.add(data);
            await applied.timeout(const Duration(seconds: 2));
          } else {
            await listener.handleReplayEnvelope(data);
          }
          await listener.handleReplayEnvelope(data);
          await Future<void>.delayed(Duration.zero);
          await expectApplied(type);
        },
      );
    }

    test(
      'R2 $type rejects invalid signature on legacy account envelope',
      () async {
        final data = await envelope(type, preState: 'diverged-state');
        bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
        await listener.handleReplayEnvelope(data);
        await expectUnchanged();
        expect(
          flows.any(
            (f) => (f['details'] as Map?)?['reason'] == 'signature_invalid',
          ),
          isTrue,
        );
      },
    );

    test('R2 $type rejects non-admin legacy account envelope', () async {
      await saveAdmin(role: MemberRole.writer);
      await listener.handleReplayEnvelope(await envelope(type));
      await expectUnchanged();
    });

    test('R2 $type rejects a foreign observed transport', () async {
      await listener.handleReplayEnvelope(
        await envelope(type, observedTransport: 'foreign-transport'),
      );
      await expectUnchanged();
    });

    test('R2 $type rejects a foreign observed device', () async {
      await listener.handleReplayEnvelope(
        await envelope(type, observedDevice: 'foreign-device'),
      );
      await expectUnchanged();
    });

    test('R2 $type rejects an explicitly conflicting signed binding', () async {
      await listener.handleReplayEnvelope(
        await envelope(
          type,
          signedDevice: 'foreign-device',
          signedTransport: 'foreign-transport',
        ),
      );
      await expectUnchanged();
    });

    for (final revoked in [false, true]) {
      test(
        'R2 $type preserves ${revoked ? 'revoked' : 'active'} device enforcement',
        () async {
          await saveAdmin(
            devices: [
              GroupMemberDeviceIdentity(
                deviceId: 'admin-device',
                transportPeerId: 'admin-transport',
                deviceSigningPublicKey: 'pk-admin',
                status: revoked
                    ? GroupMemberDeviceStatus.revoked
                    : GroupMemberDeviceStatus.active,
              ),
            ],
          );
          // An unbound account audit cannot masquerade as a rostered device.
          await listener.handleReplayEnvelope(
            await envelope(
              type,
              signedDevice: revoked ? 'admin-device' : null,
              signedTransport: revoked ? 'admin-transport' : null,
              observedDevice: 'admin-device',
              observedTransport: 'admin-transport',
            ),
          );
          await expectUnchanged();
        },
      );
    }

    test('R2 $type accepts a correctly bound active device', () async {
      await saveAdmin(
        devices: [
          const GroupMemberDeviceIdentity(
            deviceId: 'admin-device',
            transportPeerId: 'admin-transport',
            deviceSigningPublicKey: 'pk-admin',
          ),
        ],
      );
      await listener.handleReplayEnvelope(
        await envelope(
          type,
          signedDevice: 'admin-device',
          signedTransport: 'admin-transport',
          observedDevice: 'admin-device',
          observedTransport: 'admin-transport',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await expectApplied(type);
    });

    test(
      'R2 $type converges terminal local state despite earlier state divergence',
      () async {
        await listener.handleReplayEnvelope(
          await envelope(
            type,
            observedDevice: null,
            observedTransport: null,
            preState: 'sender-state-before-missed-upstream-transition',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await expectApplied(type);
      },
    );
  }

  test('R2 stale removal cannot remove a rejoined self', () async {
    final data = await envelope('member_removed', preState: 'older-state');
    final self = (await repo.getMember(groupId, selfId))!;
    await repo.saveMember(
      self.copyWith(joinedAt: eventAt.add(const Duration(minutes: 1))),
    );
    await listener.handleReplayEnvelope(data);
    await expectUnchanged();
  });

  test(
    'R2 removing another member still requires matching pre-transition state',
    () async {
      await listener.handleReplayEnvelope(
        await envelope(
          'member_removed',
          target: 'another-member',
          observedDevice: null,
          observedTransport: null,
          preState: 'diverged-state',
        ),
      );
      await expectUnchanged();
      expect(
        flows.any(
          (f) =>
              (f['details'] as Map?)?['reason'] ==
              'previous_transition_hash_mismatch',
        ),
        isTrue,
      );
    },
  );

  group('removal signed before the remover rotated the key', () {
    const otherId = 'peer-other';
    bool rejected(Map<String, dynamic> f) =>
        f['event'] == 'GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED';

    setUp(() async {
      await repo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: otherId,
          username: 'Other',
          publicKey: 'pk-other',
          role: MemberRole.writer,
          joinedAt: joinedAt,
        ),
      );
    });

    // The remover's key update (generation 2) reached this member over the
    // direct channel before the removal it followed.
    Future<void> rotatedKeyArrives() => repo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'rotated-group-key',
        createdAt: eventAt,
      ),
    );

    Future<Map<String, dynamic>> removal({
      required String preState,
      required int keyEpoch,
    }) async => {
      ...await envelope(
        'member_removed',
        target: otherId,
        observedDevice: null,
        observedTransport: null,
        preState: preState,
      ),
      'keyEpoch': keyEpoch,
    };

    test('applies at the epoch it was encrypted under', () async {
      final preState = await buildGroupTransitionStateHash(repo, groupId);
      await rotatedKeyArrives();
      await listener.handleReplayEnvelope(
        await removal(preState: preState, keyEpoch: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await repo.getMember(groupId, otherId), isNull);
      expect(await repo.getMember(groupId, selfId), isNotNull);
      expect(flows.where(rejected), isEmpty);
      expect(
        flows.any(
          (f) =>
              f['event'] ==
              'GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_AT_ENVELOPE_EPOCH',
        ),
        isTrue,
      );
    });

    test('still rejects when the envelope carries the local epoch', () async {
      final preState = await buildGroupTransitionStateHash(repo, groupId);
      await rotatedKeyArrives();
      await listener.handleReplayEnvelope(
        await removal(preState: preState, keyEpoch: 2),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await repo.getMember(groupId, otherId), isNotNull);
      expect(
        flows.any(
          (f) =>
              rejected(f) &&
              (f['details'] as Map?)?['reason'] ==
                  'previous_transition_hash_mismatch',
        ),
        isTrue,
      );
    });

    test('still rejects a diverged roster at the envelope epoch', () async {
      final preState = await buildGroupTransitionStateHash(repo, groupId);
      await repo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-late',
          username: 'Late',
          publicKey: 'pk-late',
          role: MemberRole.writer,
          joinedAt: eventAt,
        ),
      );
      await rotatedKeyArrives();
      await listener.handleReplayEnvelope(
        await removal(preState: preState, keyEpoch: 1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await repo.getMember(groupId, otherId), isNotNull);
      expect(flows.any(rejected), isTrue);
    });
  });
}
