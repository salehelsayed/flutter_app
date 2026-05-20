import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  late InMemoryGroupRepository groupRepo;
  late PassthroughCryptoBridge bridge;
  late StreamController<ChatMessage> controller;
  late GroupKeyUpdateListener listener;
  late String? mlKemSecretKey;

  ChatMessage makeMessage(
    String content, {
    String? confirmNonce,
    String from = 'sender-peer',
    String to = 'me',
    String? timestamp,
  }) {
    return ChatMessage(
      from: from,
      to: to,
      content: content,
      timestamp: timestamp ?? DateTime.now().toUtc().toIso8601String(),
      isIncoming: true,
      confirmNonce: confirmNonce,
    );
  }

  /// Builds a valid encrypted envelope whose inner plaintext is a JSON
  /// key-update payload.  Because PassthroughCryptoBridge echoes
  /// ciphertext back as plaintext, we set ciphertext = the key JSON.
  String validEnvelope({
    String groupId = 'group-1',
    int keyGeneration = 2,
    String encryptedKey = 'base64-key-material',
    String sourcePeerId = 'sender-peer',
    String? sourceDeviceId,
    String? sourceTransportPeerId,
    String? recipientPeerId,
    String? recipientDeviceId,
    String? recipientTransportPeerId,
    String? recipientKeyPackageId,
    bool includeSignature = true,
    String? signedPayload,
    String signature = 'fake-signature',
    String? sourceEventId,
    DateTime? eventAt,
    Map<String, Object?>? signedTransitionAudit,
  }) {
    final canonicalPayload =
        signedPayload ??
        canonicalGroupKeyUpdateSignedPayload(
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceDeviceId: sourceDeviceId,
          sourceTransportPeerId: sourceTransportPeerId,
          recipientPeerId: recipientPeerId,
          recipientDeviceId: recipientDeviceId,
          recipientTransportPeerId: recipientTransportPeerId,
          recipientKeyPackageId: recipientKeyPackageId,
          keyGeneration: keyGeneration,
          encryptedKey: encryptedKey,
        );
    final innerJson = jsonEncode({
      'groupId': groupId,
      'sourceEventId': ?sourceEventId,
      'eventAt': ?eventAt?.toUtc().toIso8601String(),
      'sourcePeerId': sourcePeerId,
      'sourceDeviceId': ?sourceDeviceId,
      'sourceTransportPeerId': ?sourceTransportPeerId,
      'recipientPeerId': ?recipientPeerId,
      'recipientDeviceId': ?recipientDeviceId,
      'recipientTransportPeerId': ?recipientTransportPeerId,
      'recipientKeyPackageId': ?recipientKeyPackageId,
      'keyGeneration': keyGeneration,
      'encryptedKey': encryptedKey,
      if (includeSignature) ...{
        'signatureAlgorithm': groupKeyUpdateSignatureAlgorithm,
        'signedPayload': canonicalPayload,
        'signature': signature,
      },
      signedGroupTransitionAuditField: ?signedTransitionAudit,
    });
    return jsonEncode({
      'encrypted': {
        'kem': 'fake-kem',
        'ciphertext': innerJson,
        'nonce': 'fake-nonce',
      },
    });
  }

  Future<void> saveMember({
    required String groupId,
    required String peerId,
    required MemberRole role,
    String? username,
    GroupMemberPermissions permissions = GroupMemberPermissions.empty,
    List<GroupMemberDeviceIdentity> devices =
        const <GroupMemberDeviceIdentity>[],
  }) async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: peerId,
        username: username ?? peerId,
        role: role,
        permissions: permissions,
        publicKey: 'pk-$peerId',
        mlKemPublicKey: 'mlkem-$peerId',
        devices: devices,
        joinedAt: DateTime.utc(2026, 4, 5, 12, 0),
      ),
    );
  }

  Future<void> saveActiveGroup(String groupId) async {
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: 'Group $groupId',
        type: GroupType.chat,
        topicName: '/mknoon/group/$groupId',
        createdAt: DateTime.utc(2026, 4, 5, 12, 0),
        createdBy: 'sender-peer',
        myRole: GroupRole.member,
      ),
    );
    await saveMember(
      groupId: groupId,
      peerId: 'sender-peer',
      role: MemberRole.admin,
      username: 'Sender Admin',
    );
  }

  Future<Map<String, Object?>> signDirectKeyUpdateAudit({
    required String groupId,
    required String sourceEventId,
    required DateTime eventAt,
    required int keyGeneration,
    required String encryptedKey,
    String sourcePeerId = 'sender-peer',
    String actorUsername = 'Sender Admin',
    String? actorSigningPublicKey,
    String? sourceDeviceId,
    String? sourceTransportPeerId,
    String? recipientPeerId,
    String? recipientDeviceId,
    String? recipientTransportPeerId,
    String? recipientKeyPackageId,
  }) {
    return signGroupTransitionAudit(
      bridge: bridge,
      groupRepo: groupRepo,
      groupId: groupId,
      transitionType: 'group_key_update',
      sourceEventId: sourceEventId,
      eventAt: eventAt,
      actorPeerId: sourcePeerId,
      actorUsername: actorUsername,
      actorSigningPublicKey:
          actorSigningPublicKey ??
          (sourceDeviceId == null ? 'pk-$sourcePeerId' : 'pk-$sourceDeviceId'),
      actorPrivateKey: 'sk-$sourcePeerId',
      actorDeviceId: sourceDeviceId,
      actorTransportPeerId: sourceTransportPeerId,
      transitionSubject: buildGroupKeyUpdateTransitionSubject(
        groupId: groupId,
        sourcePeerId: sourcePeerId,
        sourceDeviceId: sourceDeviceId,
        sourceTransportPeerId: sourceTransportPeerId,
        recipientPeerId: recipientPeerId,
        recipientDeviceId: recipientDeviceId,
        recipientTransportPeerId: recipientTransportPeerId,
        recipientKeyPackageId: recipientKeyPackageId,
        keyGeneration: keyGeneration,
        encryptedKey: encryptedKey,
      ),
    );
  }

  Map<String, dynamic> lastGroupOfflineReplayEnvelope(FakeBridge bridge) {
    final inboxMsg = bridge.sentMessages.lastWhere(
      (m) =>
          (jsonDecode(m) as Map<String, dynamic>)['cmd'] == 'group:inboxStore',
    );
    final payload =
        (jsonDecode(inboxMsg) as Map<String, dynamic>)['payload']
            as Map<String, dynamic>;
    return jsonDecode(payload['message'] as String) as Map<String, dynamic>;
  }

  setUp(() {
    groupRepo = InMemoryGroupRepository();
    bridge = PassthroughCryptoBridge();
    controller = StreamController<ChatMessage>.broadcast();
    mlKemSecretKey = 'my-secret-key';

    listener = GroupKeyUpdateListener(
      groupKeyUpdateStream: controller.stream,
      groupRepo: groupRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => mlKemSecretKey,
    );
  });

  tearDown(() {
    listener.dispose();
    controller.close();
  });

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT direct key update retains signature as audit evidence before key save',
    () async {
      await saveActiveGroup('group-prereq-direct-key');
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final sourceEventId = 'direct-key-audit-1';
      final eventAt = DateTime.utc(2026, 5, 1, 12, 2);
      final audit = await signDirectKeyUpdateAudit(
        groupId: 'group-prereq-direct-key',
        sourceEventId: sourceEventId,
        eventAt: eventAt,
        keyGeneration: 2,
        encryptedKey: 'key-v2',
      );

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-prereq-direct-key',
            keyGeneration: 2,
            encryptedKey: 'key-v2',
            sourceEventId: sourceEventId,
            eventAt: eventAt,
            signedTransitionAudit: audit,
          ),
          confirmNonce: sourceEventId,
          timestamp: eventAt.toIso8601String(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final saved = await groupRepo.getLatestKey('group-prereq-direct-key');
      expect(saved, isNotNull);
      expect(saved!.encryptedKey, 'key-v2');
      expect(eventLog.entries, hasLength(1));
      final payload =
          eventLog.entries.single['payload'] as Map<String, Object?>;
      expect(payload[signedGroupTransitionAuditField], isNull);
      expect(payload['encryptedKey'], isNull);
      expect(payload.toString(), isNot(contains('key-v2')));
      expect(payload['encryptedKeyHash'], isNotNull);
      expect(
        payload['signedTransitionAuditHash'],
        signedGroupTransitionAuditHash(audit),
      );

      final tamperedAudit = Map<String, Object?>.from(audit)
        ..['signedPayload'] = (audit['signedPayload'] as String).replaceAll(
          'key-v2',
          'evil-key',
        );
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-prereq-direct-key',
            keyGeneration: 3,
            encryptedKey: 'evil-key',
            sourceEventId: 'direct-key-audit-2',
            eventAt: DateTime.utc(2026, 5, 1, 12, 3),
            signedTransitionAudit: tamperedAudit,
          ),
          confirmNonce: 'direct-key-audit-2',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final stillSaved = await groupRepo.getLatestKey(
        'group-prereq-direct-key',
      );
      expect(stillSaved!.encryptedKey, 'key-v2');
      expect(eventLog.entries, hasLength(1));
    },
  );

  test(
    'PREREQ-SIGNED-COMMIT-AUDIT rejects missing direct key-update audit before side effects when append is wired',
    () async {
      await saveActiveGroup('group-prereq-missing-direct-audit');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-prereq-missing-direct-audit',
          keyGeneration: 1,
          encryptedKey: 'old-key-v1',
          createdAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-prereq-missing-direct-audit',
            keyGeneration: 2,
            encryptedKey: 'unaudited-key-v2',
            sourceEventId: 'missing-direct-audit-1',
            eventAt: DateTime.utc(2026, 5, 1, 12, 5),
          ),
          confirmNonce: 'missing-direct-audit-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      final saved = await groupRepo.getLatestKey(
        'group-prereq-missing-direct-audit',
      );
      expect(saved, isNotNull);
      expect(saved!.keyGeneration, 1);
      expect(saved.encryptedKey, 'old-key-v1');
      expect(
        await groupRepo.getKeyByGeneration(
          'group-prereq-missing-direct-audit',
          2,
        ),
        isNull,
      );
    },
  );

  test(
    'logs key update and rejects tampered replay before replacing key',
    () async {
      await saveActiveGroup('group-log');
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final sourceEventId = 'key-event-1';
      final eventAt = DateTime.utc(2026, 5, 1, 12, 10);
      final audit = await signDirectKeyUpdateAudit(
        groupId: 'group-log',
        sourceEventId: sourceEventId,
        eventAt: eventAt,
        keyGeneration: 2,
        encryptedKey: 'key-v2',
      );
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-log',
            keyGeneration: 2,
            encryptedKey: 'key-v2',
            sourceEventId: sourceEventId,
            eventAt: eventAt,
            signedTransitionAudit: audit,
          ),
          confirmNonce: sourceEventId,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(eventLog.entries, hasLength(1));
      expect(eventLog.entries.single['eventType'], 'group_key_update');
      expect(eventLog.entries.single['sourceEventId'], sourceEventId);
      final payload =
          eventLog.entries.single['payload'] as Map<String, Object?>;
      expect(payload['encryptedKey'], isNull);
      expect(payload['encryptedKeyHash'], isNotNull);
      expect(
        (await groupRepo.getLatestKey('group-log'))!.encryptedKey,
        'key-v2',
      );

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-log',
            keyGeneration: 2,
            encryptedKey: 'tampered-key-v2',
            sourceEventId: sourceEventId,
            eventAt: eventAt,
            signedTransitionAudit: audit,
          ),
          confirmNonce: sourceEventId,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(eventLog.entries, hasLength(1));
      expect(
        (await groupRepo.getLatestKey('group-log'))!.encryptedKey,
        'key-v2',
      );
    },
  );

  test(
    'exact duplicate key update replay keeps one log entry and final key',
    () async {
      await saveActiveGroup('group-exact-replay');
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final sourceEventId = 'key-exact-replay-1';
      final eventAt = DateTime.utc(2026, 5, 1, 12, 11);
      final audit = await signDirectKeyUpdateAudit(
        groupId: 'group-exact-replay',
        sourceEventId: sourceEventId,
        eventAt: eventAt,
        keyGeneration: 2,
        encryptedKey: 'key-v2',
      );
      final message = makeMessage(
        validEnvelope(
          groupId: 'group-exact-replay',
          keyGeneration: 2,
          encryptedKey: 'key-v2',
          sourceEventId: sourceEventId,
          eventAt: eventAt,
          signedTransitionAudit: audit,
        ),
        confirmNonce: sourceEventId,
      );

      controller.add(message);
      controller.add(message);

      await Future<void>.delayed(Duration.zero);

      expect(eventLog.entries, hasLength(1));
      expect(eventLog.entries.single['eventType'], 'group_key_update');
      expect(eventLog.entries.single['sourceEventId'], sourceEventId);

      final saved = await groupRepo.getLatestKey('group-exact-replay');
      expect(saved, isNotNull);
      expect(saved!.keyGeneration, 2);
      expect(saved.encryptedKey, 'key-v2');
    },
  );

  test(
    'direct key guard ignores missing group without bridge update, log, or key save',
    () async {
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'missing-direct-key-group',
            keyGeneration: 2,
            encryptedKey: 'new-key-for-missing-group',
          ),
          confirmNonce: 'missing-direct-key-event',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      expect(await groupRepo.getLatestKey('missing-direct-key-group'), isNull);
    },
  );

  test(
    'direct key guard ignores dissolved group without bridge update, log, or key replacement',
    () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'dissolved-direct-key-group',
          name: 'Dissolved Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/dissolved-direct-key-group',
          createdAt: DateTime.utc(2026, 4, 5, 12, 0),
          createdBy: 'sender-peer',
          myRole: GroupRole.member,
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 30),
          dissolvedBy: 'sender-peer',
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'dissolved-direct-key-group',
          keyGeneration: 1,
          encryptedKey: 'old-dissolved-key',
          createdAt: DateTime.utc(2026, 4, 5, 12, 1),
        ),
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'dissolved-direct-key-group',
            keyGeneration: 2,
            encryptedKey: 'new-dissolved-key',
          ),
          confirmNonce: 'dissolved-direct-key-event',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      final latest = await groupRepo.getLatestKey('dissolved-direct-key-group');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
      expect(latest.encryptedKey, 'old-dissolved-key');
      expect(
        await groupRepo.getKeyByGeneration('dissolved-direct-key-group', 2),
        isNull,
      );
    },
  );

  test(
    'ML-013 RP004 bare writer direct key update is ignored before bridge update, log, or key save',
    () async {
      await saveActiveGroup('group-rp004-direct-auth');
      await saveMember(
        groupId: 'group-rp004-direct-auth',
        peerId: 'peer-writer',
        role: MemberRole.writer,
        username: 'Writer',
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-rp004-direct-auth',
          keyGeneration: 1,
          encryptedKey: 'old-rp004-key',
          createdAt: DateTime.utc(2026, 4, 5, 12, 1),
        ),
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final sourceEventId = 'ml013-writer-key-update';
      final eventAt = DateTime.utc(2026, 5, 1, 13);
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-rp004-direct-auth',
            sourcePeerId: 'peer-writer',
            keyGeneration: 2,
            encryptedKey: 'unauthorized-rp004-key',
            sourceEventId: sourceEventId,
            eventAt: eventAt,
          ),
          confirmNonce: sourceEventId,
          from: 'peer-writer',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      final latest = await groupRepo.getLatestKey('group-rp004-direct-auth');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
      expect(latest.encryptedKey, 'old-rp004-key');
      expect(
        await groupRepo.getKeyByGeneration('group-rp004-direct-auth', 2),
        isNull,
      );
    },
  );

  test(
    'ML-013 removed peer direct key update is ignored before bridge update, log, or key save',
    () async {
      await saveActiveGroup('group-ml013-removed-direct-auth');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-ml013-removed-direct-auth',
          keyGeneration: 1,
          encryptedKey: 'old-ml013-key',
          createdAt: DateTime.utc(2026, 4, 5, 12, 1),
        ),
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final sourceEventId = 'ml013-removed-key-update';
      final eventAt = DateTime.utc(2026, 5, 1, 13, 1);
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-ml013-removed-direct-auth',
            sourcePeerId: 'peer-removed',
            keyGeneration: 2,
            encryptedKey: 'removed-ml013-key',
            sourceEventId: sourceEventId,
            eventAt: eventAt,
          ),
          confirmNonce: sourceEventId,
          from: 'peer-removed',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      final latest = await groupRepo.getLatestKey(
        'group-ml013-removed-direct-auth',
      );
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
      expect(latest.encryptedKey, 'old-ml013-key');
      expect(
        await groupRepo.getKeyByGeneration(
          'group-ml013-removed-direct-auth',
          2,
        ),
        isNull,
      );
    },
  );

  test(
    'RP004 rotate-permission sender direct key update is accepted',
    () async {
      await saveActiveGroup('group-rp004-rotate-override');
      await saveMember(
        groupId: 'group-rp004-rotate-override',
        peerId: 'peer-rotator',
        role: MemberRole.writer,
        username: 'Rotator',
        permissions: const GroupMemberPermissions(rotateKeys: true),
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final sourceEventId = 'rp004-authorized-key-update';
      final eventAt = DateTime.utc(2026, 5, 1, 12, 12);
      final audit = await signDirectKeyUpdateAudit(
        groupId: 'group-rp004-rotate-override',
        sourceEventId: sourceEventId,
        eventAt: eventAt,
        sourcePeerId: 'peer-rotator',
        actorUsername: 'Rotator',
        keyGeneration: 2,
        encryptedKey: 'authorized-rp004-key',
      );
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-rp004-rotate-override',
            sourcePeerId: 'peer-rotator',
            keyGeneration: 2,
            encryptedKey: 'authorized-rp004-key',
            sourceEventId: sourceEventId,
            eventAt: eventAt,
            signedTransitionAudit: audit,
          ),
          confirmNonce: sourceEventId,
          from: 'peer-rotator',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, contains('group:updateKey'));
      expect(eventLog.entries, hasLength(1));
      expect(eventLog.entries.single['sourcePeerId'], 'peer-rotator');
      final latest = await groupRepo.getLatestKey(
        'group-rp004-rotate-override',
      );
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 2);
      expect(latest.encryptedKey, 'authorized-rp004-key');
    },
  );

  test(
    'accepts direct key update only from a registered active source device to the local device',
    () async {
      await saveActiveGroup('group-device-key');
      await saveMember(
        groupId: 'group-device-key',
        peerId: 'me',
        role: MemberRole.writer,
        username: 'Me',
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'me-device-1',
            transportPeerId: 'me-device-1',
            deviceSigningPublicKey: 'pk-me-device-1',
            mlKemPublicKey: 'mlkem-me-device-1',
            keyPackageId: 'me-kp-1',
          ),
        ],
      );
      await saveMember(
        groupId: 'group-device-key',
        peerId: 'sender-peer',
        role: MemberRole.admin,
        username: 'Sender Admin',
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'sender-device-1',
            transportPeerId: 'sender-device-1',
            deviceSigningPublicKey: 'pk-sender-device-1',
            mlKemPublicKey: 'mlkem-sender-device-1',
            keyPackageId: 'sender-kp-1',
          ),
        ],
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        getOwnPeerId: () async => 'me',
        getOwnDeviceId: () async => 'me-device-1',
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final sourceEventId = 'device-key-event-1';
      final eventAt = DateTime.utc(2026, 5, 1, 12, 13);
      final audit = await signDirectKeyUpdateAudit(
        groupId: 'group-device-key',
        sourceEventId: sourceEventId,
        eventAt: eventAt,
        sourceDeviceId: 'sender-device-1',
        sourceTransportPeerId: 'sender-device-1',
        actorSigningPublicKey: 'pk-sender-device-1',
        recipientPeerId: 'me',
        recipientDeviceId: 'me-device-1',
        recipientTransportPeerId: 'me-device-1',
        recipientKeyPackageId: 'me-kp-1',
        keyGeneration: 2,
        encryptedKey: 'device-bound-key-v2',
      );
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-device-key',
            keyGeneration: 2,
            encryptedKey: 'device-bound-key-v2',
            sourceEventId: sourceEventId,
            eventAt: eventAt,
            sourceDeviceId: 'sender-device-1',
            sourceTransportPeerId: 'sender-device-1',
            recipientPeerId: 'me',
            recipientDeviceId: 'me-device-1',
            recipientTransportPeerId: 'me-device-1',
            recipientKeyPackageId: 'me-kp-1',
            signedTransitionAudit: audit,
          ),
          from: 'sender-device-1',
          to: 'me-device-1',
          confirmNonce: sourceEventId,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('group:updateKey'));
      expect(eventLog.entries, hasLength(1));
      final latest = await groupRepo.getLatestKey('group-device-key');
      expect(latest, isNotNull);
      expect(latest!.encryptedKey, 'device-bound-key-v2');
    },
  );

  test(
    'rejects direct key update from unbound registered source before key save',
    () async {
      await saveActiveGroup('group-unbound-source-key');
      await saveMember(
        groupId: 'group-unbound-source-key',
        peerId: 'me',
        role: MemberRole.writer,
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'me-device-1',
            transportPeerId: 'me-device-1',
            deviceSigningPublicKey: 'pk-me-device-1',
            mlKemPublicKey: 'mlkem-me-device-1',
          ),
        ],
      );
      await saveMember(
        groupId: 'group-unbound-source-key',
        peerId: 'sender-peer',
        role: MemberRole.admin,
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'sender-device-1',
            transportPeerId: 'sender-device-1',
            deviceSigningPublicKey: 'pk-sender-device-1',
            mlKemPublicKey: 'mlkem-sender-device-1',
          ),
        ],
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        getOwnPeerId: () async => 'me',
        getOwnDeviceId: () async => 'me-device-1',
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final eventAt = DateTime.utc(2026, 5, 1, 12, 14);
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-unbound-source-key',
            keyGeneration: 2,
            encryptedKey: 'unbound-source-key-v2',
            sourceEventId: 'unbound-source-key-event',
            eventAt: eventAt,
            sourceDeviceId: 'sender-device-2',
            sourceTransportPeerId: 'sender-device-2',
            recipientPeerId: 'me',
            recipientDeviceId: 'me-device-1',
            recipientTransportPeerId: 'me-device-1',
          ),
          from: 'sender-device-2',
          confirmNonce: 'unbound-source-key-event',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      expect(await groupRepo.getLatestKey('group-unbound-source-key'), isNull);
    },
  );

  test(
    'rejects direct key update for the wrong local recipient device before key save',
    () async {
      await saveActiveGroup('group-wrong-recipient-key');
      await saveMember(
        groupId: 'group-wrong-recipient-key',
        peerId: 'me',
        role: MemberRole.writer,
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'me-device-1',
            transportPeerId: 'me-device-1',
            deviceSigningPublicKey: 'pk-me-device-1',
            mlKemPublicKey: 'mlkem-me-device-1',
            keyPackageId: 'me-kp-1',
          ),
        ],
      );
      await saveMember(
        groupId: 'group-wrong-recipient-key',
        peerId: 'sender-peer',
        role: MemberRole.admin,
        devices: const [
          GroupMemberDeviceIdentity(
            deviceId: 'sender-device-1',
            transportPeerId: 'sender-device-1',
            deviceSigningPublicKey: 'pk-sender-device-1',
            mlKemPublicKey: 'mlkem-sender-device-1',
          ),
        ],
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        getOwnPeerId: () async => 'me',
        getOwnDeviceId: () async => 'me-device-1',
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final eventAt = DateTime.utc(2026, 5, 1, 12, 15);
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-wrong-recipient-key',
            keyGeneration: 2,
            encryptedKey: 'wrong-recipient-key-v2',
            sourceEventId: 'wrong-recipient-key-event',
            eventAt: eventAt,
            sourceDeviceId: 'sender-device-1',
            sourceTransportPeerId: 'sender-device-1',
            recipientPeerId: 'me',
            recipientDeviceId: 'me-device-2',
            recipientTransportPeerId: 'me-device-2',
          ),
          from: 'sender-device-1',
          confirmNonce: 'wrong-recipient-key-event',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      expect(await groupRepo.getLatestKey('group-wrong-recipient-key'), isNull);
    },
  );

  test(
    'EK004 rejects unsigned direct key update before bridge update, log, or key save',
    () async {
      await saveActiveGroup('group-ek004-unsigned-key');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-ek004-unsigned-key',
          keyGeneration: 1,
          encryptedKey: 'old-ek004-key',
          createdAt: DateTime.utc(2026, 4, 5, 12, 1),
        ),
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final eventAt = DateTime.utc(2026, 5, 1, 12, 17);
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-ek004-unsigned-key',
            keyGeneration: 2,
            encryptedKey: 'unsigned-ek004-key',
            sourceEventId: 'ek004-unsigned-key-update',
            eventAt: eventAt,
            includeSignature: false,
          ),
          confirmNonce: 'ek004-unsigned-key-update',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      final latest = await groupRepo.getLatestKey('group-ek004-unsigned-key');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
      expect(latest.encryptedKey, 'old-ek004-key');
      expect(
        await groupRepo.getKeyByGeneration('group-ek004-unsigned-key', 2),
        isNull,
      );
    },
  );

  test(
    'EK004 rejects mismatched direct key update signature payload before verify or key save',
    () async {
      await saveActiveGroup('group-ek004-mismatch-key');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-ek004-mismatch-key',
          keyGeneration: 1,
          encryptedKey: 'old-ek004-key',
          createdAt: DateTime.utc(2026, 4, 5, 12, 1),
        ),
      );
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final mismatchedSignedPayload = canonicalGroupKeyUpdateSignedPayload(
        groupId: 'group-ek004-mismatch-key',
        sourcePeerId: 'sender-peer',
        keyGeneration: 2,
        encryptedKey: 'different-signed-key',
      );
      final eventAt = DateTime.utc(2026, 5, 1, 12, 18);

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-ek004-mismatch-key',
            keyGeneration: 2,
            encryptedKey: 'mismatched-ek004-key',
            sourceEventId: 'ek004-mismatched-key-update',
            eventAt: eventAt,
            signedPayload: mismatchedSignedPayload,
          ),
          confirmNonce: 'ek004-mismatched-key-update',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      final latest = await groupRepo.getLatestKey('group-ek004-mismatch-key');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
      expect(latest.encryptedKey, 'old-ek004-key');
      expect(
        await groupRepo.getKeyByGeneration('group-ek004-mismatch-key', 2),
        isNull,
      );
    },
  );

  test(
    'EK004 rejects invalid direct key update signature before bridge update, log, or key save',
    () async {
      await saveActiveGroup('group-ek004-invalid-signature');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-ek004-invalid-signature',
          keyGeneration: 1,
          encryptedKey: 'old-ek004-key',
          createdAt: DateTime.utc(2026, 4, 5, 12, 1),
        ),
      );
      bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
      final eventLog = _FakeEventLog();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
      );
      listener.start();

      final eventAt = DateTime.utc(2026, 5, 1, 12, 16);
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-ek004-invalid-signature',
            keyGeneration: 2,
            encryptedKey: 'invalid-signature-ek004-key',
            sourceEventId: 'ek004-invalid-signature-key-update',
            eventAt: eventAt,
          ),
          confirmNonce: 'ek004-invalid-signature-key-update',
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(eventLog.entries, isEmpty);
      final latest = await groupRepo.getLatestKey(
        'group-ek004-invalid-signature',
      );
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 1);
      expect(latest.encryptedKey, 'old-ek004-key');
      expect(
        await groupRepo.getKeyByGeneration('group-ek004-invalid-signature', 2),
        isNull,
      );
    },
  );

  test(
    'KE-019 rejects tampered direct key update payloads with diagnostics and keeps current key usable',
    () async {
      const groupId = 'group-ke019-direct';
      const currentEpoch = 1;
      const currentKey = 'ke019-current-key-1';
      const signedEpoch = 2;
      const signedKey = 'ke019-valid-key-2';
      const originalSender = 'sender-peer';
      const alternateSender = 'ke019-alternate-admin';

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      await saveActiveGroup(groupId);
      await saveMember(
        groupId: groupId,
        peerId: 'me',
        role: MemberRole.writer,
        username: 'Me',
      );
      await saveMember(
        groupId: groupId,
        peerId: alternateSender,
        role: MemberRole.admin,
        username: 'Alternate Admin',
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: currentEpoch,
          encryptedKey: currentKey,
          createdAt: DateTime.utc(2026, 5, 11, 12),
        ),
      );

      final eventLog = _FakeEventLog();
      final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        appendGroupEventLogEntry: eventLog.append,
        retryPendingGroupKeyRepairs: (request) async {
          repairCalls.add(request);
        },
      );
      listener.start();

      final signedPayload = canonicalGroupKeyUpdateSignedPayload(
        groupId: groupId,
        sourcePeerId: originalSender,
        keyGeneration: signedEpoch,
        encryptedKey: signedKey,
      );

      Future<void> rejectTamperedUpdate({
        required String variant,
        required String envelope,
        required String from,
        required int tamperedEpoch,
      }) async {
        final invalidEventsBefore = flowEvents
            .where(
              (event) =>
                  event['event'] ==
                  'GROUP_KEY_UPDATE_LISTENER_INVALID_SIGNATURE',
            )
            .length;
        bridge.commandLog.clear();

        controller.add(
          makeMessage(
            envelope,
            from: from,
            confirmNonce: 'ke019-$variant',
            timestamp: DateTime.utc(
              2026,
              5,
              11,
              12,
              tamperedEpoch,
            ).toIso8601String(),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(bridge.commandLog, contains('message.decrypt'), reason: variant);
        expect(
          bridge.commandLog,
          isNot(contains('payload.verify')),
          reason: variant,
        );
        expect(
          bridge.commandLog,
          isNot(contains('group:updateKey')),
          reason: variant,
        );
        expect(eventLog.entries, isEmpty, reason: variant);
        expect(repairCalls, isEmpty, reason: variant);

        final latest = await groupRepo.getLatestKey(groupId);
        expect(latest, isNotNull, reason: variant);
        expect(latest!.keyGeneration, currentEpoch, reason: variant);
        expect(latest.encryptedKey, currentKey, reason: variant);
        expect(
          await groupRepo.getKeyByGeneration(groupId, tamperedEpoch),
          isNull,
          reason: variant,
        );

        final invalidEvents = flowEvents
            .where(
              (event) =>
                  event['event'] ==
                  'GROUP_KEY_UPDATE_LISTENER_INVALID_SIGNATURE',
            )
            .toList();
        expect(invalidEvents, hasLength(invalidEventsBefore + 1));
        final details = invalidEvents.last['details'] as Map<String, dynamic>;
        expect(details['reason'], 'signed_payload_mismatch', reason: variant);
      }

      await rejectTamperedUpdate(
        variant: 'key-material',
        from: originalSender,
        tamperedEpoch: signedEpoch,
        envelope: validEnvelope(
          groupId: groupId,
          keyGeneration: signedEpoch,
          encryptedKey: 'ke019-tampered-key-2',
          sourcePeerId: originalSender,
          sourceEventId: 'ke019-tampered-key-material',
          eventAt: DateTime.utc(2026, 5, 11, 12, 2),
          signedPayload: signedPayload,
        ),
      );

      await rejectTamperedUpdate(
        variant: 'epoch',
        from: originalSender,
        tamperedEpoch: 7,
        envelope: validEnvelope(
          groupId: groupId,
          keyGeneration: 7,
          encryptedKey: signedKey,
          sourcePeerId: originalSender,
          sourceEventId: 'ke019-tampered-epoch',
          eventAt: DateTime.utc(2026, 5, 11, 12, 3),
          signedPayload: signedPayload,
        ),
      );

      await rejectTamperedUpdate(
        variant: 'sender-identity',
        from: alternateSender,
        tamperedEpoch: signedEpoch,
        envelope: validEnvelope(
          groupId: groupId,
          keyGeneration: signedEpoch,
          encryptedKey: signedKey,
          sourcePeerId: alternateSender,
          sourceEventId: 'ke019-tampered-source-peer',
          eventAt: DateTime.utc(2026, 5, 11, 12, 4),
          signedPayload: signedPayload,
        ),
      );

      bridge.commandLog.clear();
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'ke019-post-rejection',
        'topicPeers': 1,
      };
      final msgRepo = InMemoryGroupMessageRepository();
      final (sendResult, sentMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'KE-019 preserved epoch send',
        senderPeerId: 'me',
        senderPublicKey: 'pk-me',
        senderPrivateKey: 'sk-me',
        senderUsername: 'Me',
        messageId: 'ke019-post-rejection',
        timestamp: DateTime.utc(2026, 5, 11, 12, 5),
      );

      expect(sendResult, SendGroupMessageResult.success);
      expect(sentMessage, isNotNull);
      expect(sentMessage!.keyGeneration, currentEpoch);
      final savedMessage = await msgRepo.getMessage('ke019-post-rejection');
      expect(savedMessage, isNotNull);
      expect(savedMessage!.keyGeneration, currentEpoch);
      final replayEnvelope = lastGroupOfflineReplayEnvelope(bridge);
      expect(replayEnvelope['keyEpoch'], currentEpoch);
    },
  );

  test('saves key on successful decrypt', () async {
    await saveActiveGroup('group-42');
    listener.start();

    controller.add(
      makeMessage(
        validEnvelope(
          groupId: 'group-42',
          keyGeneration: 3,
          encryptedKey: 'new-key-abc',
        ),
      ),
    );

    // Allow the async listener pipeline to complete.
    await Future<void>.delayed(Duration.zero);

    final saved = await groupRepo.getLatestKey('group-42');
    expect(saved, isNotNull);
    expect(saved!.groupId, 'group-42');
    expect(saved.keyGeneration, 3);
    expect(saved.encryptedKey, 'new-key-abc');

    // Verify the bridge was called with message.decrypt
    expect(bridge.commandLog, contains('message.decrypt'));
  });

  test('promotes key only after group:updateKey succeeds', () async {
    await saveActiveGroup('group-delay');
    final updateCompleter = Completer<String>();
    final delayedBridge = _DelayedUpdateKeyBridge(updateCompleter);

    final delayedListener = GroupKeyUpdateListener(
      groupKeyUpdateStream: controller.stream,
      groupRepo: groupRepo,
      bridge: delayedBridge,
      getOwnMlKemSecretKey: () async => 'my-secret-key',
    );
    delayedListener.start();

    controller.add(
      makeMessage(
        validEnvelope(
          groupId: 'group-delay',
          keyGeneration: 2,
          encryptedKey: 'pending-key',
        ),
      ),
    );

    await Future<void>.delayed(Duration.zero);

    expect(delayedBridge.commandLog, contains('message.decrypt'));
    expect(delayedBridge.commandLog, contains('group:updateKey'));
    expect(await groupRepo.getLatestKey('group-delay'), isNull);

    updateCompleter.complete(jsonEncode({'ok': true}));
    await Future<void>.delayed(Duration.zero);

    final saved = await groupRepo.getLatestKey('group-delay');
    expect(saved, isNotNull);
    expect(saved!.keyGeneration, 2);
    expect(saved.encryptedKey, 'pending-key');

    delayedListener.dispose();
  });

  test(
    'PREREQ-FUTURE-EPOCH-KEY-REPAIR key arrival retries pending future epoch replay after save',
    () async {
      await saveActiveGroup('group-prereq-future-key');
      final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        retryPendingGroupKeyRepairs: (request) async {
          expect(
            await groupRepo.getKeyByGeneration(
              request.groupId,
              request.keyEpoch,
            ),
            isNotNull,
          );
          repairCalls.add(request);
        },
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-prereq-future-key',
            keyGeneration: 2,
            encryptedKey: 'future-key-material',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(repairCalls, hasLength(1));
      expect(repairCalls.single.groupId, 'group-prereq-future-key');
      expect(repairCalls.single.keyEpoch, 2);
      final saved = await groupRepo.getKeyByGeneration(
        'group-prereq-future-key',
        2,
      );
      expect(saved, isNotNull);
      expect(saved!.encryptedKey, 'future-key-material');
    },
  );

  test(
    'GM-014 delayed key arrival retries Charlie post-readd pending replay exactly once after save',
    () async {
      await saveActiveGroup('group-gm014-readd-key');
      final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
      var pendingReplayRetryObserved = false;
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        retryPendingGroupKeyRepairs: (request) async {
          expect(request.groupId, 'group-gm014-readd-key');
          expect(request.keyEpoch, 2);
          expect(
            await groupRepo.getKeyByGeneration(
              request.groupId,
              request.keyEpoch,
            ),
            isNotNull,
          );
          repairCalls.add(request);
          pendingReplayRetryObserved = true;
        },
      );
      listener.start();

      final update = makeMessage(
        validEnvelope(
          groupId: 'group-gm014-readd-key',
          keyGeneration: 2,
          encryptedKey: 'gm014-readd-key-material',
        ),
      );
      controller.add(update);
      await Future<void>.delayed(Duration.zero);

      expect(repairCalls, hasLength(1));
      expect(pendingReplayRetryObserved, isTrue);
      final saved = await groupRepo.getKeyByGeneration(
        'group-gm014-readd-key',
        2,
      );
      expect(saved, isNotNull);
      expect(saved!.encryptedKey, 'gm014-readd-key-material');

      controller.add(update);
      await Future<void>.delayed(Duration.zero);

      expect(repairCalls, hasLength(1));
    },
  );

  test(
    'PREREQ-FUTURE-EPOCH-KEY-REPAIR rejected key updates do not trigger pending repair',
    () async {
      await saveActiveGroup('group-prereq-reject-key');
      final repairCalls = <GroupPendingKeyRepairRetryRequest>[];

      final invalidSignatureBridge = PassthroughCryptoBridge();
      invalidSignatureBridge.responses['payload.verify'] = {
        'ok': true,
        'valid': false,
      };
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: invalidSignatureBridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        retryPendingGroupKeyRepairs: (request) async {
          repairCalls.add(request);
        },
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-prereq-reject-key',
            keyGeneration: 2,
            encryptedKey: 'rejected-key-material',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(invalidSignatureBridge.commandLog, contains('payload.verify'));
      expect(
        invalidSignatureBridge.commandLog,
        isNot(contains('group:updateKey')),
      );
      expect(repairCalls, isEmpty);
      expect(
        await groupRepo.getKeyByGeneration('group-prereq-reject-key', 2),
        isNull,
      );

      final failUpdateKeyBridge = _UpdateKeyFailBridge();
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: failUpdateKeyBridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        retryPendingGroupKeyRepairs: (request) async {
          repairCalls.add(request);
        },
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-prereq-reject-key',
            keyGeneration: 3,
            encryptedKey: 'bridge-rejected-key-material',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(failUpdateKeyBridge.commandLog, contains('group:updateKey'));
      expect(repairCalls, isEmpty);
      expect(
        await groupRepo.getKeyByGeneration('group-prereq-reject-key', 3),
        isNull,
      );
    },
  );

  test(
    'send during pending key update uses old epoch until local update commits',
    () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-pending-send',
          name: 'Pending Send Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/group-pending-send',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-b',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-pending-send',
          peerId: 'peer-b',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-b',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await saveMember(
        groupId: 'group-pending-send',
        peerId: 'sender-peer',
        role: MemberRole.admin,
        username: 'Sender Admin',
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-pending-send',
          keyGeneration: 1,
          encryptedKey: 'old-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final updateCompleter = Completer<String>();
      final delayedBridge = _DelayedUpdateKeyBridge(updateCompleter);
      delayedBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'publish-ok',
        'topicPeers': 1,
      };
      final delayedListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: delayedBridge,
        getOwnMlKemSecretKey: () async => 'my-secret-key',
      );
      final msgRepo = InMemoryGroupMessageRepository();

      delayedListener.start();
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-pending-send',
            keyGeneration: 2,
            encryptedKey: 'new-key',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(delayedBridge.commandLog, contains('group:updateKey'));
      final latestWhilePending = await groupRepo.getLatestKey(
        'group-pending-send',
      );
      expect(latestWhilePending, isNotNull);
      expect(latestWhilePending!.keyGeneration, 1);
      expect(
        await groupRepo.getKeyByGeneration('group-pending-send', 2),
        isNull,
      );

      final (duringResult, duringMessage) = await sendGroupMessage(
        bridge: delayedBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-pending-send',
        text: 'During pending key update',
        senderPeerId: 'peer-b',
        senderPublicKey: 'pk-b',
        senderPrivateKey: 'sk-b',
        senderUsername: 'Bob',
        messageId: 'msg-pending-update-during',
      );

      expect(duringResult, SendGroupMessageResult.success);
      expect(duringMessage, isNotNull);
      expect(duringMessage!.keyGeneration, 1);
      expect(lastGroupOfflineReplayEnvelope(delayedBridge)['keyEpoch'], 1);

      updateCompleter.complete(jsonEncode({'ok': true}));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final latestAfterCommit = await groupRepo.getLatestKey(
        'group-pending-send',
      );
      expect(latestAfterCommit, isNotNull);
      expect(latestAfterCommit!.keyGeneration, 2);

      final (afterResult, afterMessage) = await sendGroupMessage(
        bridge: delayedBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-pending-send',
        text: 'After pending key update',
        senderPeerId: 'peer-b',
        senderPublicKey: 'pk-b',
        senderPrivateKey: 'sk-b',
        senderUsername: 'Bob',
        messageId: 'msg-pending-update-after',
      );

      expect(afterResult, SendGroupMessageResult.success);
      expect(afterMessage, isNotNull);
      expect(afterMessage!.keyGeneration, 2);
      expect(lastGroupOfflineReplayEnvelope(delayedBridge)['keyEpoch'], 2);

      delayedListener.dispose();
    },
  );

  test('returns early when encrypted field is null', () async {
    listener.start();

    // Envelope without the 'encrypted' key.
    final content = jsonEncode({'type': 'group_key_update', 'payload': {}});
    controller.add(makeMessage(content));

    await Future<void>.delayed(Duration.zero);

    // No key should have been saved.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);

    // Bridge should NOT have been called at all.
    expect(bridge.commandLog, isEmpty);
  });

  test('returns early when own ML-KEM secret key is null', () async {
    mlKemSecretKey = null;
    listener.start();

    controller.add(makeMessage(validEnvelope()));

    await Future<void>.delayed(Duration.zero);

    // No decrypt should have been attempted.
    expect(bridge.commandLog, isEmpty);

    // No key saved.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);
  });

  test('returns early when decrypt fails (ok: false)', () async {
    // Override message.decrypt to return a failure response.
    final failBridge = FakeBridge(
      initialResponses: {
        'message.decrypt': {'ok': false, 'errorCode': 'DECRYPT_FAILED'},
      },
    );

    final failListener = GroupKeyUpdateListener(
      groupKeyUpdateStream: controller.stream,
      groupRepo: groupRepo,
      bridge: failBridge,
      getOwnMlKemSecretKey: () async => 'my-secret-key',
    );

    failListener.start();

    controller.add(makeMessage(validEnvelope()));

    await Future<void>.delayed(Duration.zero);

    // Decrypt was called but returned ok: false.
    expect(failBridge.commandLog, contains('message.decrypt'));

    // No key saved.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);

    failListener.dispose();
  });

  test('saves key to DB AND updates Go via group:updateKey', () async {
    await saveActiveGroup('group-99');
    listener.start();

    controller.add(
      makeMessage(
        validEnvelope(
          groupId: 'group-99',
          keyGeneration: 5,
          encryptedKey: 'rotated-key-xyz',
        ),
      ),
    );

    // Allow the async listener pipeline to complete.
    await Future<void>.delayed(Duration.zero);

    // Verify key was saved to DB.
    final saved = await groupRepo.getLatestKey('group-99');
    expect(saved, isNotNull);
    expect(saved!.groupId, 'group-99');
    expect(saved.keyGeneration, 5);
    expect(saved.encryptedKey, 'rotated-key-xyz');

    // Verify bridge was called with message.decrypt (for decryption)
    // AND group:updateKey (to update Go's stored key).
    expect(bridge.commandLog, contains('message.decrypt'));
    expect(bridge.commandLog, contains('group:updateKey'));
  });

  test('does not crash on malformed JSON', () async {
    listener.start();

    controller.add(makeMessage('this is not valid json {{{'));

    await Future<void>.delayed(Duration.zero);

    // No key saved, no crash.
    final saved = await groupRepo.getLatestKey('group-1');
    expect(saved, isNull);
    expect(bridge.commandLog, isEmpty);
  });

  test(
    'group:updateKey payload contains correct groupId, groupKey, keyEpoch',
    () async {
      await saveActiveGroup('group-77');
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-77',
            keyGeneration: 4,
            encryptedKey: 'specific-key-material',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      // Find the group:updateKey command in sentMessages
      final updateKeyMsg = bridge.sentMessages.firstWhere((m) {
        final parsed = jsonDecode(m) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:updateKey';
      });
      final payload =
          (jsonDecode(updateKeyMsg) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;

      expect(payload['groupId'], 'group-77');
      expect(payload['groupKey'], 'specific-key-material');
      expect(payload['keyEpoch'], 4);
    },
  );

  test('handles sequential key updates (epoch 2 then epoch 3)', () async {
    await saveActiveGroup('group-seq');
    listener.start();

    // Send epoch 2
    controller.add(
      makeMessage(
        validEnvelope(
          groupId: 'group-seq',
          keyGeneration: 2,
          encryptedKey: 'key-epoch-2',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Send epoch 3
    controller.add(
      makeMessage(
        validEnvelope(
          groupId: 'group-seq',
          keyGeneration: 3,
          encryptedKey: 'key-epoch-3',
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    // Both should be saved to DB
    final key2 = await groupRepo.getKeyByGeneration('group-seq', 2);
    expect(key2, isNotNull);
    expect(key2!.encryptedKey, 'key-epoch-2');

    final key3 = await groupRepo.getKeyByGeneration('group-seq', 3);
    expect(key3, isNotNull);
    expect(key3!.encryptedKey, 'key-epoch-3');

    // Latest key should be epoch 3
    final latest = await groupRepo.getLatestKey('group-seq');
    expect(latest!.keyGeneration, 3);

    // Both should have triggered group:updateKey
    final updateKeyCount = bridge.commandLog
        .where((c) => c == 'group:updateKey')
        .length;
    expect(updateKeyCount, 2);
  });

  test(
    'delayed older key update after newer generation does not promote active key',
    () async {
      await saveActiveGroup('group-delayed-older');
      final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        retryPendingGroupKeyRepairs: (request) async {
          repairCalls.add(request);
        },
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-delayed-older',
            keyGeneration: 3,
            encryptedKey: 'key-epoch-3',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-delayed-older',
            keyGeneration: 2,
            encryptedKey: 'historical-key-epoch-2',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final historical = await groupRepo.getKeyByGeneration(
        'group-delayed-older',
        2,
      );
      expect(historical, isNotNull);
      expect(historical!.encryptedKey, 'historical-key-epoch-2');

      final latest = await groupRepo.getLatestKey('group-delayed-older');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 3);
      expect(latest.encryptedKey, 'key-epoch-3');

      final updateKeyCount = bridge.commandLog
          .where((c) => c == 'group:updateKey')
          .length;
      expect(updateKeyCount, 1);
      expect(repairCalls, hasLength(1));
      expect(repairCalls.single.keyEpoch, 3);
    },
  );

  test(
    'RA-006 KE-011 delayed old key after re-add stays historical and current delivery remains on re-add epoch',
    () async {
      const groupId = 'group-ke011-readd-delayed-old-key';
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      await saveActiveGroup(groupId);
      await saveMember(
        groupId: groupId,
        peerId: 'me',
        role: MemberRole.writer,
        username: 'Charlie',
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 3,
          encryptedKey: 'ke011-readd-current-key-3',
          createdAt: DateTime.utc(2026, 5, 12, 12, 11),
        ),
      );

      final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        retryPendingGroupKeyRepairs: (request) async {
          repairCalls.add(request);
        },
      );
      listener.start();

      bridge.commandLog.clear();
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'ke011-delayed-old-key-1',
            sourceEventId: 'ke011-delayed-old-key-after-readd',
            eventAt: DateTime.utc(2026, 5, 12, 12, 12),
          ),
          confirmNonce: 'ke011-delayed-old-key-after-readd',
          timestamp: DateTime.utc(2026, 5, 12, 12, 12).toIso8601String(),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final latest = await groupRepo.getLatestKey(groupId);
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 3);
      expect(latest.encryptedKey, 'ke011-readd-current-key-3');

      final historical = await groupRepo.getKeyByGeneration(groupId, 1);
      expect(historical, isNotNull);
      expect(historical!.encryptedKey, 'ke011-delayed-old-key-1');
      expect(bridge.commandLog, contains('message.decrypt'));
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
      expect(repairCalls, isEmpty);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_KEY_UPDATE_LISTENER_HISTORICAL_KEY_SAVED',
        ),
        isTrue,
      );

      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'ke011-after-stale-send',
        'topicPeers': 1,
      };
      final msgRepo = InMemoryGroupMessageRepository();
      final (sendResult, sentMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'KE-011 current epoch still usable after stale key',
        senderPeerId: 'me',
        senderPublicKey: 'pk-me',
        senderPrivateKey: 'sk-me',
        senderUsername: 'Charlie',
        messageId: 'ke011-after-stale-send',
        timestamp: DateTime.utc(2026, 5, 12, 12, 13),
      );
      expect(sendResult, SendGroupMessageResult.success);
      expect(sentMessage, isNotNull);
      expect(sentMessage!.keyGeneration, 3);
    },
  );

  test(
    'KE-005 conflicting same-generation key updates keep first accepted material',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      await saveActiveGroup('group-race');
      final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        retryPendingGroupKeyRepairs: (request) async {
          repairCalls.add(request);
        },
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-race',
            keyGeneration: 2,
            encryptedKey: 'key-epoch-2a',
          ),
        ),
      );
      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-race',
            keyGeneration: 2,
            encryptedKey: 'key-epoch-2b',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final kept = await groupRepo.getKeyByGeneration('group-race', 2);
      expect(kept, isNotNull);
      expect(kept!.encryptedKey, 'key-epoch-2a');

      final latest = await groupRepo.getLatestKey('group-race');
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 2);
      expect(latest.encryptedKey, 'key-epoch-2a');

      final updateKeyCount = bridge.commandLog
          .where((c) => c == 'group:updateKey')
          .length;
      expect(updateKeyCount, 1);
      expect(repairCalls, hasLength(1));
      expect(repairCalls.single.keyEpoch, 2);
      expect(
        flowEvents.where(
          (event) =>
              event['event'] == 'GROUP_KEY_UPDATE_LISTENER_SAME_EPOCH_CONFLICT',
        ),
        hasLength(1),
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] == 'GROUP_KEY_UPDATE_LISTENER_UPDATE_KEY_FAILED' ||
              event['event'] == 'GROUP_KEY_UPDATE_LISTENER_HANDLE_ERROR',
        ),
        isEmpty,
      );
    },
  );

  test(
    'KE-004 duplicate same-generation key update with same material is idempotent',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      await saveActiveGroup('group-duplicate-same-generation');
      final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
      listener.dispose();
      listener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: () async => mlKemSecretKey,
        retryPendingGroupKeyRepairs: (request) async {
          repairCalls.add(request);
        },
      );
      listener.start();

      final update = makeMessage(
        validEnvelope(
          groupId: 'group-duplicate-same-generation',
          keyGeneration: 2,
          encryptedKey: 'key-epoch-2',
        ),
      );
      controller.add(update);
      await Future<void>.delayed(Duration.zero);
      controller.add(update);
      await Future<void>.delayed(Duration.zero);

      final saved = await groupRepo.getKeyByGeneration(
        'group-duplicate-same-generation',
        2,
      );
      expect(saved, isNotNull);
      expect(saved!.encryptedKey, 'key-epoch-2');

      final updateKeyCount = bridge.commandLog
          .where((c) => c == 'group:updateKey')
          .length;
      expect(updateKeyCount, 1);
      expect(repairCalls, hasLength(1));
      expect(repairCalls.single.keyEpoch, 2);
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
              'GROUP_KEY_UPDATE_LISTENER_DUPLICATE_GENERATION',
        ),
        hasLength(1),
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
                  'GROUP_KEY_UPDATE_LISTENER_SAME_EPOCH_CONFLICT' ||
              event['event'] == 'GROUP_KEY_UPDATE_LISTENER_UPDATE_KEY_FAILED' ||
              event['event'] == 'GROUP_KEY_UPDATE_LISTENER_HANDLE_ERROR',
        ),
        isEmpty,
      );
    },
  );

  test(
    'conflicting delayed older key update does not replace historical material',
    () async {
      await saveActiveGroup('group-delayed-older-conflict');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-delayed-older-conflict',
          keyGeneration: 2,
          encryptedKey: 'existing-historical-key-2',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-delayed-older-conflict',
          keyGeneration: 3,
          encryptedKey: 'current-key-3',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      listener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-delayed-older-conflict',
            keyGeneration: 2,
            encryptedKey: 'conflicting-historical-key-2',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final historical = await groupRepo.getKeyByGeneration(
        'group-delayed-older-conflict',
        2,
      );
      expect(historical, isNotNull);
      expect(historical!.encryptedKey, 'existing-historical-key-2');

      final latest = await groupRepo.getLatestKey(
        'group-delayed-older-conflict',
      );
      expect(latest, isNotNull);
      expect(latest!.keyGeneration, 3);
      expect(latest.encryptedKey, 'current-key-3');
      expect(bridge.commandLog, isNot(contains('group:updateKey')));
    },
  );

  test(
    'KE-022 group:updateKey bridge failure keeps the old key active, reports diagnostics, and requests recovery',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final repairRequests = <GroupKeyRepairRequest>[];

      await saveActiveGroup('group-fail');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-fail',
          keyGeneration: 1,
          encryptedKey: 'old-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final failUpdateKeyBridge = _UpdateKeyFailBridge();

      final failListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: failUpdateKeyBridge,
        getOwnMlKemSecretKey: () async => 'my-secret-key',
        requestGroupKeyRepair: repairRequests.add,
      );

      failListener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-fail',
            keyGeneration: 2,
            encryptedKey: 'key-despite-bridge-fail',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      final saved = await groupRepo.getLatestKey('group-fail');
      expect(saved, isNotNull);
      expect(saved!.encryptedKey, 'old-key');
      expect(saved.keyGeneration, 1);
      expect(await groupRepo.getKeyByGeneration('group-fail', 2), isNull);
      expect(repairRequests, hasLength(1));
      expect(repairRequests.single.groupId, 'group-fail');
      expect(repairRequests.single.keyEpoch, 2);
      expect(
        repairRequests.single.reason,
        groupKeyRepairReasonKeyUpdateApplyFailed,
      );

      expect(failUpdateKeyBridge.commandLog, contains('message.decrypt'));
      expect(failUpdateKeyBridge.commandLog, contains('group:updateKey'));
      expect(
        flowEvents.where(
          (event) =>
              event['event'] == 'GROUP_KEY_UPDATE_LISTENER_UPDATE_KEY_FAILED',
        ),
        hasLength(1),
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] == 'GROUP_KEY_UPDATE_LISTENER_RECOVERY_REQUESTED',
        ),
        hasLength(1),
      );

      failListener.dispose();
    },
  );

  test(
    'BB-002 group:updateKey NOT_INITIALIZED keeps current key unchanged',
    () async {
      await saveActiveGroup('group-bb002-key');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-bb002-key',
          keyGeneration: 1,
          encryptedKey: 'old-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final notInitializedBridge = _UpdateKeyFailBridge(
        errorCode: 'NOT_INITIALIZED',
      );
      final notInitializedListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: notInitializedBridge,
        getOwnMlKemSecretKey: () async => 'my-secret-key',
      );

      notInitializedListener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-bb002-key',
            keyGeneration: 2,
            encryptedKey: 'key-before-native-init',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      final saved = await groupRepo.getLatestKey('group-bb002-key');
      expect(saved, isNotNull);
      expect(saved!.encryptedKey, 'old-key');
      expect(saved.keyGeneration, 1);
      expect(await groupRepo.getKeyByGeneration('group-bb002-key', 2), isNull);
      expect(notInitializedBridge.commandLog, contains('group:updateKey'));

      notInitializedListener.dispose();
    },
  );

  test(
    'BB-013 group:updateKey timeout does not save or promote the next group key',
    () async {
      await saveActiveGroup('group-bb013-key-timeout');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-bb013-key-timeout',
          keyGeneration: 1,
          encryptedKey: 'old-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final timeoutBridge = _UpdateKeyTimeoutBridge();
      final timeoutListener = GroupKeyUpdateListener(
        groupKeyUpdateStream: controller.stream,
        groupRepo: groupRepo,
        bridge: timeoutBridge,
        getOwnMlKemSecretKey: () async => 'my-secret-key',
      );

      timeoutListener.start();

      controller.add(
        makeMessage(
          validEnvelope(
            groupId: 'group-bb013-key-timeout',
            keyGeneration: 2,
            encryptedKey: 'key-after-timeout',
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);

      final saved = await groupRepo.getLatestKey('group-bb013-key-timeout');
      expect(saved, isNotNull);
      expect(saved!.encryptedKey, 'old-key');
      expect(saved.keyGeneration, 1);
      expect(
        await groupRepo.getKeyByGeneration('group-bb013-key-timeout', 2),
        isNull,
      );
      expect(timeoutBridge.commandLog, contains('group:updateKey'));

      timeoutListener.dispose();
    },
  );
}

class _UpdateKeyTimeoutBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:updateKey') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw TimeoutException('Simulated group:updateKey timeout');
    }
    return super.send(message);
  }
}

/// A PassthroughCryptoBridge that returns {ok: false} for group:updateKey
/// but handles encrypt/decrypt normally.
class _UpdateKeyFailBridge extends PassthroughCryptoBridge {
  final String errorCode;

  _UpdateKeyFailBridge({this.errorCode = 'UPDATE_KEY_FAILED'});

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:updateKey') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return jsonEncode({'ok': false, 'errorCode': errorCode});
    }
    return super.send(message);
  }
}

class _DelayedUpdateKeyBridge extends PassthroughCryptoBridge {
  final Completer<String> _updateCompleter;

  _DelayedUpdateKeyBridge(this._updateCompleter);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:updateKey') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      return _updateCompleter.future;
    }
    return super.send(message);
  }
}

class _FakeEventLog {
  final entries = <Map<String, Object?>>[];
  final _payloadBySourceEventId = <String, String>{};

  Future<Map<String, Object?>> append({
    required String groupId,
    required String eventType,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> payload,
    DateTime? createdAt,
  }) async {
    final canonical = canonicalizeGroupEventLogPayload(payload);
    final existing = _payloadBySourceEventId[sourceEventId];
    if (existing != null && existing != canonical) {
      throw GroupEventLogTamperException('conflicting replay');
    }
    _payloadBySourceEventId[sourceEventId] = canonical;
    final entry = {
      'groupId': groupId,
      'eventType': eventType,
      'sourcePeerId': sourcePeerId,
      'sourceEventId': sourceEventId,
      'sourceTimestamp': sourceTimestamp,
      'payload': payload,
    };
    if (existing == null) {
      entries.add(entry);
    }
    return entry;
  }
}
