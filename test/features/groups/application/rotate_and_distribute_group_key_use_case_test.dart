import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late PassthroughCryptoBridge bridge;
  late InMemoryGroupRepository groupRepo;

  const selfPeerId = 'peer-self';
  const groupId = 'group-1';

  setUp(() async {
    bridge = PassthroughCryptoBridge();
    groupRepo = InMemoryGroupRepository();

    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Test Group',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.now().toUtc(),
        createdBy: selfPeerId,
        myRole: GroupRole.admin,
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: selfPeerId,
        username: 'Self',
        role: MemberRole.admin,
        publicKey: 'selfPubKey',
        mlKemPublicKey: 'selfMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-bob',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'bobPubKey',
        mlKemPublicKey: 'bobMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-carol',
        username: 'Carol',
        role: MemberRole.writer,
        publicKey: 'carolPubKey',
        mlKemPublicKey: 'carolMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'oldKey==',
        createdAt: DateTime.now().toUtc(),
      ),
    );

    bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'newKey==',
      'keyEpoch': 2,
    };

    bridge.responses['group:publish'] = {'ok': true, 'messageId': 'sys-msg-id'};
  });

  test(
    'allows writer with rotate permission override to rotate keys',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(rotateKeys: true),
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
      );

      expect(result, isNotNull);
      expect(result!.keyGeneration, 2);
      expect(bridge.commandLog, contains('group:generateNextKey'));

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 2);
    },
  );

  test('denies admin whose rotate permission override is false', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: selfPeerId,
        username: 'Self',
        role: MemberRole.admin,
        permissions: const GroupMemberPermissions(rotateKeys: false),
        publicKey: 'selfPubKey',
        mlKemPublicKey: 'selfMlKem',
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    expect(result, isNull);
    expect(bridge.commandLog, isEmpty);

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
  });

  test(
    'rechecks revoked rotate permission before generating a queued key',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.writer,
          permissions: const GroupMemberPermissions(rotateKeys: true),
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.writer,
          publicKey: 'selfPubKey',
          mlKemPublicKey: 'selfMlKem',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
      );

      expect(result, isNull);
      expect(bridge.commandLog, isEmpty);

      final latestKey = await groupRepo.getLatestKey(groupId);
      expect(latestKey, isNotNull);
      expect(latestKey!.keyGeneration, 1);
    },
  );

  test('promotes generated key only after distribution completes', () async {
    final bobSend = Completer<bool>();
    final carolSend = Completer<bool>();

    final pending = rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      perRecipientTimeout: const Duration(milliseconds: 200),
      distributionTimeout: const Duration(milliseconds: 200),
      sendP2PMessage: (peerId, message) {
        if (peerId == 'peer-bob') return bobSend.future;
        if (peerId == 'peer-carol') return carolSend.future;
        return Future.value(true);
      },
    );

    await Future<void>.delayed(Duration.zero);

    final latestBeforePromotion = await groupRepo.getLatestKey(groupId);
    expect(latestBeforePromotion, isNotNull);
    expect(latestBeforePromotion!.keyGeneration, 1);
    expect(await groupRepo.getKeyByGeneration(groupId, 2), isNull);

    expect(bridge.commandLog, contains('group:generateNextKey'));
    expect(bridge.commandLog.where((c) => c == 'message.encrypt').length, 2);
    expect(bridge.commandLog, isNot(contains('group:updateKey')));
    expect(bridge.commandLog, isNot(contains('group:publish')));

    bobSend.complete(true);
    carolSend.complete(true);

    final result = await pending;

    expect(result, isNotNull);
    expect(result!.keyGeneration, 2);
    expect(result.encryptedKey, 'newKey==');

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 2);
  });

  test('distribution completes before admin update and broadcast', () async {
    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    expect(result, isNotNull);

    final generateIdx = bridge.commandLog.indexOf('group:generateNextKey');
    final encryptIdx = bridge.commandLog.indexOf('message.encrypt');
    final updateIdx = bridge.commandLog.indexOf('group:updateKey');
    final publishIdx = bridge.commandLog.lastIndexOf('group:publish');

    expect(generateIdx, greaterThanOrEqualTo(0));
    expect(encryptIdx, greaterThan(generateIdx));
    expect(updateIdx, greaterThan(encryptIdx));
    expect(publishIdx, greaterThan(updateIdx));
  });

  test('calls bridge to encrypt key for each non-self member', () async {
    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    // message.encrypt should be called twice (Bob + Carol, not self)
    final encryptCount = bridge.commandLog
        .where((c) => c == 'message.encrypt')
        .length;
    expect(encryptCount, 2);
  });

  test('broadcasts key_rotated system message', () async {
    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    // group:publish should be called for the system message
    expect(bridge.commandLog, contains('group:publish'));

    // Parse the published text to verify it's a key_rotated system message
    final publishMsg = bridge.sentMessages.firstWhere((m) {
      final parsed = jsonDecode(m) as Map<String, dynamic>;
      return parsed['cmd'] == 'group:publish';
    });
    final publishPayload =
        (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    final sysText =
        jsonDecode(publishPayload['text'] as String) as Map<String, dynamic>;
    expect(sysText['__sys'], 'key_rotated');
    expect(sysText['newKeyEpoch'], 2);
  });

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT signs key_rotated transition before publish',
    () async {
      await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
      );

      final publishMsg = bridge.sentMessages.firstWhere((m) {
        final parsed = jsonDecode(m) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:publish';
      });
      final publishPayload =
          (jsonDecode(publishMsg) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      final sysText =
          jsonDecode(publishPayload['text'] as String) as Map<String, dynamic>;

      expect(sysText['__sys'], 'key_rotated');
      expect(sysText[signedGroupTransitionAuditField], isNotNull);
      expect(bridge.commandLog.where((c) => c == 'payload.sign').length, 5);
    },
  );

  test('sends key update to each non-self member via p2p', () async {
    final sentMessages = <(String, String)>[];

    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      distributionAttemptCount: 2,
      distributionRetryDelay: Duration.zero,
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Should send to Bob and Carol (not self)
    expect(sentMessages.length, 2);
    final peerIds = sentMessages.map((m) => m.$1).toSet();
    expect(peerIds, contains('peer-bob'));
    expect(peerIds, contains('peer-carol'));

    // Each message should be a group_key_update envelope
    for (final (_, msg) in sentMessages) {
      final parsed = jsonDecode(msg) as Map<String, dynamic>;
      expect(parsed['type'], 'group_key_update');
      expect(parsed['version'], '2');
      expect(parsed['encrypted'], isNotNull);
    }
  });

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT signs distributed direct key-update payloads before encryption',
    () async {
      final sentMessages = <(String, String)>[];

      await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: (peerId, message) async {
          sentMessages.add((peerId, message));
          return true;
        },
      );

      expect(sentMessages.length, 2);
      expect(bridge.commandLog.where((c) => c == 'payload.sign').length, 5);

      final sourceEventIds = <String>{};
      final eventAtValues = <String>{};
      for (final (_, message) in sentMessages) {
        final envelope = jsonDecode(message) as Map<String, dynamic>;
        final encrypted = envelope['encrypted'] as Map<String, dynamic>;
        final keyPayload =
            jsonDecode(encrypted['ciphertext'] as String)
                as Map<String, dynamic>;

        expect(keyPayload['sourcePeerId'], selfPeerId);
        expect(keyPayload['sourceEventId'], isA<String>());
        expect(keyPayload['eventAt'], isA<String>());
        sourceEventIds.add(keyPayload['sourceEventId'] as String);
        eventAtValues.add(keyPayload['eventAt'] as String);
        expect(
          keyPayload['signatureAlgorithm'],
          groupKeyUpdateSignatureAlgorithm,
        );
        expect(keyPayload['signature'], 'fake-signature');
        expect(keyPayload[signedGroupTransitionAuditField], isNotNull);

        final expectedSignedPayload = canonicalGroupKeyUpdateSignedPayload(
          groupId: groupId,
          sourcePeerId: selfPeerId,
          keyGeneration: 2,
          encryptedKey: 'newKey==',
          sourceDeviceId: selfPeerId,
          sourceTransportPeerId: selfPeerId,
          recipientPeerId: keyPayload['recipientPeerId'] as String?,
          recipientDeviceId: keyPayload['recipientDeviceId'] as String?,
          recipientTransportPeerId:
              keyPayload['recipientTransportPeerId'] as String?,
        );
        expect(keyPayload['signedPayload'], expectedSignedPayload);
        final signedAudit =
            keyPayload[signedGroupTransitionAuditField] as Map<String, dynamic>;
        expect(signedAudit['transitionType'], 'group_key_update');
        expect(signedAudit['sourceEventId'], keyPayload['sourceEventId']);
        expect(signedAudit['eventAt'], keyPayload['eventAt']);
        expect(signedAudit['signedPayload'], isA<String>());
      }
      expect(sourceEventIds, hasLength(2));
      expect(eventAtValues, hasLength(1));
    },
  );

  test('returns null when generate-next-key fails (ok: false)', () async {
    bridge.responses['group:generateNextKey'] = {
      'ok': false,
      'errorCode': 'GENERATE_FAILED',
    };

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
    );

    expect(result, isNull);

    // Verify no new key was saved — latest key should still be generation 1
    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
  });

  test('skips members without mlKemPublicKey', () async {
    // Add Dave without an ML-KEM public key
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: 'peer-dave',
        username: 'Dave',
        role: MemberRole.writer,
        publicKey: 'davePubKey',
        mlKemPublicKey: null,
        joinedAt: DateTime.now().toUtc(),
      ),
    );

    final sentMessages = <(String, String)>[];

    await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      distributionAttemptCount: 2,
      distributionRetryDelay: Duration.zero,
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Only Bob and Carol should receive P2P messages (Dave skipped)
    expect(sentMessages.length, 2);
    final peerIds = sentMessages.map((m) => m.$1).toSet();
    expect(peerIds, contains('peer-bob'));
    expect(peerIds, contains('peer-carol'));
    expect(peerIds, isNot(contains('peer-dave')));

    // message.encrypt should be called only twice (not three times)
    final encryptCount = bridge.commandLog
        .where((c) => c == 'message.encrypt')
        .length;
    expect(encryptCount, 2);
  });

  test(
    'targets active registered recipient devices and skips revoked devices',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'self-device-1',
              transportPeerId: 'self-device-1',
              deviceSigningPublicKey: 'selfPubKey',
              mlKemPublicKey: 'selfDeviceMlKem',
              keyPackageId: 'self-kp-1',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'bobPubKey',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'bob-phone',
              transportPeerId: 'bob-phone-transport',
              deviceSigningPublicKey: 'bobPhonePubKey',
              mlKemPublicKey: 'bobPhoneMlKem',
              keyPackageId: 'bob-phone-kp',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'bob-tablet',
              transportPeerId: 'bob-tablet-transport',
              deviceSigningPublicKey: 'bobTabletPubKey',
              mlKemPublicKey: 'bobTabletMlKem',
              keyPackageId: 'bob-tablet-kp',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'bob-revoked',
              transportPeerId: 'bob-revoked-transport',
              deviceSigningPublicKey: 'bobRevokedPubKey',
              mlKemPublicKey: 'bobRevokedMlKem',
              keyPackageId: 'bob-revoked-kp',
              status: GroupMemberDeviceStatus.revoked,
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      final sentMessages = <(String, Map<String, dynamic>)>[];

      await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
        sendP2PMessage: (peerId, message) async {
          final envelope = jsonDecode(message) as Map<String, dynamic>;
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          final payload =
              jsonDecode(encrypted['ciphertext'] as String)
                  as Map<String, dynamic>;
          sentMessages.add((peerId, payload));
          return true;
        },
      );

      final targetPeerIds = sentMessages.map((entry) => entry.$1).toSet();
      expect(targetPeerIds, contains('bob-phone-transport'));
      expect(targetPeerIds, contains('bob-tablet-transport'));
      expect(targetPeerIds, isNot(contains('bob-revoked-transport')));
      final bobPayloads = sentMessages
          .where(
            (entry) => (entry.$2['recipientPeerId'] as String?) == 'peer-bob',
          )
          .map((entry) => entry.$2)
          .toList();
      expect(
        bobPayloads.map((payload) => payload['recipientDeviceId']).toSet(),
        {'bob-phone', 'bob-tablet'},
      );
      expect(bobPayloads.map((payload) => payload['sourceDeviceId']).toSet(), {
        'self-device-1',
      });
    },
  );

  test(
    'rejects registered source member without matching active source device before key generation',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          publicKey: 'selfPubKey',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'self-device-1',
              transportPeerId: 'self-device-1',
              deviceSigningPublicKey: 'different-device-pub-key',
              mlKemPublicKey: 'selfDeviceMlKem',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );

      final result = await rotateAndDistributeGroupKey(
        bridge: bridge,
        groupRepo: groupRepo,
        groupId: groupId,
        selfPeerId: selfPeerId,
        senderPublicKey: 'selfPubKey',
        senderPrivateKey: 'selfPrivKey',
        senderUsername: 'Self',
      );

      expect(result, isNull);
      expect(bridge.commandLog, isNot(contains('group:generateNextKey')));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      final latest = await groupRepo.getLatestKey(groupId);
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
    },
  );

  test('continues distribution when per-member encrypt fails', () async {
    // Use a custom bridge that fails encrypt for Bob but succeeds for Carol
    final selectiveBridge = _SelectiveEncryptFailBridge();
    selectiveBridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'newKey==',
      'keyEpoch': 2,
    };
    selectiveBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'sys-msg-id',
    };

    final sentMessages = <(String, String)>[];

    final result = await rotateAndDistributeGroupKey(
      bridge: selectiveBridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      distributionAttemptCount: 2,
      distributionRetryDelay: Duration.zero,
      sendP2PMessage: (peerId, message) async {
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Only Carol should receive a P2P message (Bob's encrypt failed)
    expect(result, isNull);
    expect(sentMessages.length, 1);
    expect(sentMessages.first.$1, 'peer-carol');
    expect(selectiveBridge.commandLog, isNot(contains('group:updateKey')));
    expect(selectiveBridge.commandLog, isNot(contains('group:publish')));
  });

  test('retries transient send failures before promotion', () async {
    final attemptsByPeer = <String, int>{};
    final sentMessages = <(String, String)>[];

    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      distributionRetryDelay: Duration.zero,
      sendP2PMessage: (peerId, message) async {
        attemptsByPeer[peerId] = (attemptsByPeer[peerId] ?? 0) + 1;
        if (peerId == 'peer-bob' && attemptsByPeer[peerId] == 1) {
          throw Exception('Network error for first peer');
        }
        sentMessages.add((peerId, message));
        return true;
      },
    );

    // Function should still complete and return a result
    expect(result, isNotNull);
    expect(result!.keyGeneration, 2);

    expect(attemptsByPeer['peer-bob'], 2);
    expect(sentMessages.any((message) => message.$1 == 'peer-bob'), isTrue);
    expect(bridge.commandLog, contains('group:updateKey'));
  });

  test('distribution timeout starts all recipients but fails closed', () async {
    final blockedSend = Completer<bool>();
    var bobStarted = false;
    var carolStarted = false;

    final pending = rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      perRecipientTimeout: const Duration(seconds: 1),
      distributionTimeout: const Duration(milliseconds: 40),
      distributionAttemptCount: 1,
      sendP2PMessage: (peerId, message) {
        if (peerId == 'peer-bob') {
          bobStarted = true;
          return blockedSend.future;
        }
        if (peerId == 'peer-carol') {
          carolStarted = true;
        }
        return Future.value(true);
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(bobStarted, isTrue);
    expect(carolStarted, isTrue);
    expect(bridge.commandLog, isNot(contains('group:updateKey')));

    final result = await pending;
    blockedSend.complete(false);

    expect(result, isNull);
    expect(bridge.commandLog, isNot(contains('group:updateKey')));
    expect(bridge.commandLog, isNot(contains('group:publish')));
  });

  test('does not update admin key after distribution timeout', () async {
    final blockedSend = Completer<bool>();
    final result = await rotateAndDistributeGroupKey(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      selfPeerId: selfPeerId,
      senderPublicKey: 'selfPubKey',
      senderPrivateKey: 'selfPrivKey',
      senderUsername: 'Self',
      perRecipientTimeout: const Duration(seconds: 1),
      distributionTimeout: const Duration(milliseconds: 40),
      distributionAttemptCount: 1,
      sendP2PMessage: (_, _) => blockedSend.future,
    );
    blockedSend.complete(false);

    expect(result, isNull);
    expect(bridge.commandLog, isNot(contains('group:updateKey')));
    expect(bridge.commandLog, isNot(contains('group:publish')));

    final latestKey = await groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull);
    expect(latestKey!.keyGeneration, 1);
  });
}

class _SelectiveEncryptFailBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'message.encrypt') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      if (payload['recipientPublicKey'] == 'bobMlKem') {
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        commandLog.add(cmd!);
        return jsonEncode({'ok': false, 'errorCode': 'ENCRYPT_FAILED'});
      }
    }
    return super.send(message);
  }
}
