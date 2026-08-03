import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_message_local_deletions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/secure_storage/fake_secure_key_store.dart';

import 'package:flutter_app/features/groups/application/handle_incoming_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

List<Map<String, dynamic>> _gird003Media({
  required String id,
  required String createdAt,
  String contentHash = _validContentHash,
  String encryptionKeyBase64 = 'gird003-key-fixture',
  String encryptionNonce = 'gird003-nonce-fixture',
}) {
  return [
    {
      'id': id,
      'mime': 'image/png',
      'size': 4096,
      'mediaType': 'image',
      'contentHash': contentHash,
      'encryptionKeyBase64': encryptionKeyBase64,
      'encryptionNonce': encryptionNonce,
      'encryptionScheme': 'blob_aes_256_gcm_v1',
      'downloadStatus': 'pending',
      'createdAt': createdAt,
    },
  ];
}

class _CountingGroupRepository extends InMemoryGroupRepository {
  var getGroupCalls = 0;
  var getMemberCalls = 0;

  @override
  Future<GroupModel?> getGroup(String id) async {
    getGroupCalls++;
    return super.getGroup(id);
  }

  @override
  Future<GroupMember?> getMember(String groupId, String peerId) async {
    getMemberCalls++;
    return super.getMember(groupId, peerId);
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

class _GuardedRecordingMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository
    implements GroupGuardedMediaAttachmentSave {
  bool allowGuardedSave = true;
  int guardedSaveCalls = 0;

  @override
  Future<bool> saveGroupAttachmentGuarded(
    MediaAttachment attachment, {
    required String groupId,
  }) async {
    guardedSaveCalls++;
    if (!allowGuardedSave) return false;
    await saveAttachment(attachment, owner: MediaOwnerLane.group);
    return true;
  }
}

class _LogicalMediaRetryRaceRepository
    extends _GuardedRecordingMediaAttachmentRepository {
  bool removeCanonicalMediaAfterNextBatchLookup = false;

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    final result = await super.getAttachmentsForMessages(
      messageIds,
      owner: owner,
    );
    if (removeCanonicalMediaAfterNextBatchLookup) {
      removeCanonicalMediaAfterNextBatchLookup = false;
      for (final messageId in messageIds) {
        await super.deleteAttachmentsForMessage(messageId, owner: owner);
      }
    }
    return result;
  }
}

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-admin',
    myRole: GroupRole.admin,
  );

  final testMember = GroupMember(
    groupId: 'group-1',
    peerId: 'peer-sender',
    username: 'Sender',
    role: MemberRole.writer,
    joinedAt: DateTime.now().toUtc(),
  );

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(testMember);
  });

  Future<void> saveRemovalCutoff({
    required String removedPeerId,
    required DateTime removedAt,
  }) {
    return msgRepo.saveMessage(
      GroupMessage(
        id:
            'sys-member_removed:group-1:$removedPeerId:peer-admin:'
            '${removedAt.microsecondsSinceEpoch}',
        groupId: 'group-1',
        senderPeerId: 'peer-admin',
        senderUsername: 'Admin',
        text: 'Admin removed $removedPeerId',
        timestamp: removedAt,
        status: 'delivered',
        isIncoming: true,
        createdAt: removedAt,
      ),
    );
  }

  test('handles incoming message successfully', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello from sender!',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(result, isNotNull);
    expect(result!.text, 'Hello from sender!');
    expect(result.isIncoming, true);
    expect(result.senderPeerId, 'peer-sender');
    expect(result.transportPeerId, 'peer-sender');
  });

  test(
    'TC-330-02 display custody is staged before canonical save and ready after media',
    () async {
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final order = <String>[];

      final outcome = await handleIncomingGroupMessageDetailed(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        mediaAttachmentRepo: mediaRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'custody ordering',
        timestamp: '2026-08-02T20:00:00.000Z',
        messageId: 'msg-330-order',
        media: _gird003Media(
          id: 'att-330-order',
          createdAt: '2026-08-02T20:00:00.000Z',
        ),
        stageNotificationDisplayCustody: (message) async {
          expect(await msgRepo.getMessage(message.id), isNull);
          expect(
            await mediaRepo.getAttachmentsForMessage(
              message.id,
              owner: MediaOwnerLane.group,
            ),
            isEmpty,
          );
          order.add('stage');
        },
        markNotificationDisplayCustodyReady: (message) async {
          expect(await msgRepo.getMessage(message.id), isNotNull);
          expect(
            await mediaRepo.getAttachmentsForMessage(
              message.id,
              owner: MediaOwnerLane.group,
            ),
            hasLength(1),
          );
          order.add('ready');
        },
      );

      expect(outcome, isA<IncomingGroupMessageDelivered>());
      expect(order, ['stage', 'ready']);
    },
  );

  test(
    'TC-330-02 failed display-custody stage aborts canonical mutation',
    () async {
      await expectLater(
        handleIncomingGroupMessageDetailed(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'must not persist',
          timestamp: '2026-08-02T20:01:00.000Z',
          messageId: 'msg-330-stage-fails',
          stageNotificationDisplayCustody: (_) async {
            throw StateError('stage unavailable');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(await msgRepo.getMessage('msg-330-stage-fails'), isNull);
    },
  );

  test(
    'TC-330 exact message identity is normalized before custody and persistence',
    () async {
      final custodyIds = <String>[];
      final outcome = await handleIncomingGroupMessageDetailed(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'normalized identity',
        timestamp: '2026-08-03T04:05:00.000Z',
        messageId: '  msg-normalized-before-ack  ',
        stageNotificationDisplayCustody: (message) async {
          custodyIds.add('stage:${message.id}');
        },
        markNotificationDisplayCustodyReady: (message) async {
          custodyIds.add('ready:${message.id}');
        },
      );

      expect(outcome, isA<IncomingGroupMessageDelivered>());
      final delivered = (outcome as IncomingGroupMessageDelivered).message;
      expect(delivered.id, 'msg-normalized-before-ack');
      expect(custodyIds, const <String>[
        'stage:msg-normalized-before-ack',
        'ready:msg-normalized-before-ack',
      ]);
      expect(await msgRepo.getMessage('msg-normalized-before-ack'), isNotNull);
      expect(await msgRepo.getMessage('  msg-normalized-before-ack  '), isNull);
    },
  );

  test(
    'ML-016 incoming member message falls back to group member label when sender username is empty',
    () async {
      final sentAt = DateTime.now().toUtc();
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-dana',
          username: 'Dana',
          role: MemberRole.writer,
          joinedAt: sentAt.subtract(const Duration(seconds: 1)),
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: '   ',
        keyEpoch: 1,
        text: 'ML-016 non-contact member delivery',
        timestamp: sentAt.toIso8601String(),
        selfPeerId: 'peer-dana',
        messageId: 'ml016-member-label',
      );

      expect(result, isNotNull);
      expect(result!.isIncoming, isTrue);
      expect(result.senderPeerId, 'peer-sender');
      expect(result.senderUsername, 'Sender');

      final stored = await msgRepo.getMessage('ml016-member-label');
      expect(stored, isNotNull);
      expect(stored!.senderUsername, 'Sender');
      expect(stored.text, 'ML-016 non-contact member delivery');
      expect(stored.keyGeneration, 1);
    },
  );

  test(
    'RA-013 accepts incoming message when local peer is an active same-account device',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final sentAt = DateTime.now().toUtc();

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'device-charlie-phone',
              transportPeerId: 'device-charlie-phone',
              deviceSigningPublicKey: 'charlie-phone-signing-key',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-charlie-tablet',
              transportPeerId: 'device-charlie-tablet',
              deviceSigningPublicKey: 'charlie-tablet-signing-key',
            ),
          ],
          joinedAt: sentAt.subtract(const Duration(seconds: 1)),
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 2,
        text: 'RA-013 post tablet accept',
        timestamp: sentAt.toIso8601String(),
        selfPeerId: 'device-charlie-tablet',
        messageId: 'ra013-secondary-device-receive',
      );

      expect(result, isNotNull);
      expect(result!.senderPeerId, 'peer-sender');
      expect(result.isIncoming, isTrue);
      expect(result.status, 'delivered');
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_LOCAL_MEMBERSHIP_MISSING',
        ),
        isFalse,
      );
      expect(
        (await msgRepo.getMessage('ra013-secondary-device-receive'))!.text,
        'RA-013 post tablet accept',
      );
    },
  );

  test(
    'RA-013 applies account removal window when local peer is a same-account device',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final originalAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 20),
      );
      final removedAt = originalAt.add(const Duration(minutes: 3));
      final rejoinedAt = removedAt.add(const Duration(minutes: 2));

      await saveRemovalCutoff(
        removedPeerId: 'peer-charlie',
        removedAt: removedAt,
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'device-charlie-tablet',
              transportPeerId: 'device-charlie-tablet',
              deviceSigningPublicKey: 'charlie-tablet-signing-key',
            ),
          ],
          joinedAt: rejoinedAt,
        ),
      );

      final removedWindowReplay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 2,
        text: 'RA-013 removed window replay',
        timestamp: removedAt.add(const Duration(seconds: 30)).toIso8601String(),
        selfPeerId: 'device-charlie-tablet',
        messageId: 'ra013-secondary-device-removed-window',
      );

      expect(removedWindowReplay, isNull);
      expect(
        await msgRepo.getMessage('ra013-secondary-device-removed-window'),
        isNull,
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_LOCAL_REMOVED_INTERVAL_REPLAY_REJECTED',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'MS002 rejects transport peer mismatch before persistence or event log',
    () async {
      final eventLog = _FakeEventLog();
      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'spoofed',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'ms002-spoof',
        transportPeerId: 'peer-attacker',
        appendGroupEventLogEntry: eventLog.append,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('ms002-spoof'), isNull);
      expect(eventLog.entries, isEmpty);
    },
  );

  test(
    'SV-004 forged sender transport identity is rejected before persistence or event log',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final eventLog = _FakeEventLog();

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Forged Sender',
        keyEpoch: 1,
        text: 'SV-004 forged message',
        timestamp: DateTime.utc(2026, 5, 14, 4, 32).toIso8601String(),
        messageId: 'sv004-forged-transport',
        transportPeerId: 'peer-attacker',
        senderDeviceId: 'peer-attacker',
        appendGroupEventLogEntry: eventLog.append,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('sv004-forged-transport'), isNull);
      expect(await msgRepo.getLatestMessage('group-1'), isNull);
      expect(eventLog.entries, isEmpty);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_UNBOUND_DEVICE_REJECTED',
        ),
        isTrue,
      );
    },
  );

  test(
    'SV-011 valid key nonmember sender is rejected before persistence or event log',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final eventLog = _FakeEventLog();
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'sv011-current-group-key',
          createdAt: DateTime.utc(2026, 5, 14, 4),
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-valid-key-nonmember',
        senderUsername: 'Key Holder',
        keyEpoch: 1,
        text: 'SV-011 nonmember with valid key',
        timestamp: DateTime.utc(2026, 5, 14, 4).toIso8601String(),
        messageId: 'sv011-valid-key-nonmember',
        transportPeerId: 'peer-valid-key-nonmember',
        senderDeviceId: 'peer-valid-key-nonmember',
        appendGroupEventLogEntry: eventLog.append,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('sv011-valid-key-nonmember'), isNull);
      expect(await msgRepo.getLatestMessage('group-1'), isNull);
      expect(eventLog.entries, isEmpty);
      expect(await groupRepo.getLatestKey('group-1'), isNotNull);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
                  'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_SENDER_REJECTED' &&
              (event['details'] as Map<String, dynamic>)['keyEpoch'] == 1,
        ),
        isTrue,
      );
    },
  );

  test('MS002 stores verified transport peer id on accepted message', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'bound sender',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      messageId: 'ms002-bound',
      transportPeerId: 'peer-sender',
    );

    expect(result, isNotNull);
    expect(result!.transportPeerId, 'peer-sender');
    final stored = await msgRepo.getMessage('ms002-bound');
    expect(stored, isNotNull);
    expect(stored!.senderPeerId, 'peer-sender');
    expect(stored.transportPeerId, 'peer-sender');
  });

  test('records incoming message in tamper-evident event log', () async {
    final eventLog = _FakeEventLog();
    final timestamp = DateTime.utc(2026, 4, 30, 12).toIso8601String();

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 3,
      text: 'Logged message',
      timestamp: timestamp,
      messageId: 'msg-log-1',
      quotedMessageId: 'msg-parent-1',
      appendGroupEventLogEntry: eventLog.append,
    );

    expect(result, isNotNull);
    expect(eventLog.entries, hasLength(1));
    expect(eventLog.entries.single['eventType'], 'message');
    expect(eventLog.entries.single['sourceEventId'], 'msg-log-1');
    final payload = eventLog.entries.single['payload'] as Map<String, Object?>;
    expect(payload['text'], 'Logged message');
    expect(payload['keyEpoch'], 3);
    expect(payload['quotedMessageId'], 'msg-parent-1');
    expect(payload['transportPeerId'], 'peer-sender');
  });

  test(
    'event log rejects tampered duplicate before stored message changes',
    () async {
      final eventLog = _FakeEventLog();
      final timestamp = DateTime.utc(2026, 4, 30, 12).toIso8601String();

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Original',
        timestamp: timestamp,
        messageId: 'msg-replay-1',
        appendGroupEventLogEntry: eventLog.append,
      );

      expect(
        () => handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'Tampered',
          timestamp: timestamp,
          messageId: 'msg-replay-1',
          appendGroupEventLogEntry: eventLog.append,
        ),
        throwsA(isA<GroupEventLogTamperException>()),
      );

      final stored = await msgRepo.getMessage('msg-replay-1');
      expect(stored, isNotNull);
      expect(stored!.text, 'Original');
      expect(msgRepo.count, 1);
    },
  );

  test('persists same-self delivery as local sent history', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Synced from another device',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      selfPeerId: 'peer-sender',
    );

    expect(result, isNotNull);
    expect(result!.isIncoming, isFalse);
    expect(result.status, 'sent');
    expect(await msgRepo.getUnreadCount('group-1'), 0);
  });

  test(
    'DE-005 self echo reconciles pending outbound row without creating incoming duplicate',
    () async {
      const messageId = 'de005-self-echo';
      final localTimestamp = DateTime.utc(2026, 5, 11, 10);
      final createdAt = localTimestamp.subtract(const Duration(seconds: 2));
      await msgRepo.saveMessage(
        GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          senderUsername: 'Sender',
          text: 'Local pending text',
          timestamp: localTimestamp,
          keyGeneration: 1,
          status: 'pending',
          isIncoming: false,
          createdAt: createdAt,
          wireEnvelope: '{"cmd":"group:publish"}',
          inboxStored: false,
          inboxRetryPayload: '{"cmd":"group:inboxStore"}',
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: 'Local pending text',
        timestamp: localTimestamp
            .add(const Duration(seconds: 5))
            .toIso8601String(),
        selfPeerId: 'peer-sender',
        transportPeerId: 'peer-sender',
        messageId: messageId,
      );

      expect(result, isNotNull);
      expect(result!.id, messageId);
      expect(result.isIncoming, isFalse);
      expect(result.status, 'sent');

      final saved = await msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      expect(saved!.isIncoming, isFalse);
      expect(saved.status, 'sent');
      expect(saved.text, 'Local pending text');
      expect(saved.timestamp, localTimestamp);
      expect(saved.createdAt, createdAt);
      expect(saved.wireEnvelope, isNull);
      expect(saved.inboxStored, isFalse);
      expect(saved.inboxRetryPayload, '{"cmd":"group:inboxStore"}');
      expect(msgRepo.count, 1);
      expect(await msgRepo.getUnreadCount('group-1'), 0);
    },
  );

  test(
    // 210b: a self echo is positive proof the message reached the network, so
    // it must also settle a 'queued_offline' row (clock → tick) instead of
    // being rejected as a duplicate — e.g. a peer that subscribed during the
    // publish settle window echoes back before the repush pass settles the row.
    'DE-005/210b self echo reconciles queued_offline outbound row to sent',
    () async {
      const messageId = 'de005-self-echo-queued-offline';
      final localTimestamp = DateTime.utc(2026, 5, 11, 10);
      final createdAt = localTimestamp.subtract(const Duration(seconds: 2));
      await msgRepo.saveMessage(
        GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          senderUsername: 'Sender',
          text: 'Local queued offline text',
          timestamp: localTimestamp,
          keyGeneration: 1,
          status: 'queued_offline',
          isIncoming: false,
          createdAt: createdAt,
          inboxStored: false,
          inboxRetryPayload: '{"cmd":"group:inboxStore"}',
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: 'Local queued offline text',
        timestamp: localTimestamp
            .add(const Duration(seconds: 5))
            .toIso8601String(),
        selfPeerId: 'peer-sender',
        transportPeerId: 'peer-sender',
        messageId: messageId,
      );

      expect(result, isNotNull);
      expect(result!.id, messageId);
      expect(result.isIncoming, isFalse);
      expect(result.status, 'sent');

      final saved = await msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      expect(saved!.isIncoming, isFalse);
      expect(saved.status, 'sent');
      expect(msgRepo.count, 1);
      expect(await msgRepo.getUnreadCount('group-1'), 0);
    },
  );

  test(
    'DE-005 self echo ignores mismatched transport identity without promoting outbound row',
    () async {
      const messageId = 'de005-self-echo-transport-mismatch';
      final localTimestamp = DateTime.utc(2026, 5, 11, 10, 1);
      await msgRepo.saveMessage(
        GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender-device',
          senderUsername: 'Sender',
          text: 'Local pending text',
          timestamp: localTimestamp,
          keyGeneration: 1,
          status: 'pending',
          isIncoming: false,
          createdAt: localTimestamp,
          wireEnvelope: '{"cmd":"group:publish"}',
          inboxRetryPayload: '{"cmd":"group:inboxStore"}',
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: 'Local pending text',
        timestamp: localTimestamp.toIso8601String(),
        selfPeerId: 'peer-sender',
        transportPeerId: 'peer-attacker-device',
        messageId: messageId,
      );

      expect(result, isNull);
      final saved = await msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      expect(saved!.status, 'pending');
      expect(saved.isIncoming, isFalse);
      expect(saved.transportPeerId, 'peer-sender-device');
      expect(saved.wireEnvelope, '{"cmd":"group:publish"}');
      expect(msgRepo.count, 1);
    },
  );

  test(
    'GIRD-001 same-id self replay repairs in-doubt failed outgoing row',
    () async {
      const messageId = 'gird001-self-replay-repairs-failed';
      final localTimestamp = DateTime.utc(2026, 5, 31, 12);
      final createdAt = localTimestamp.subtract(const Duration(seconds: 3));
      await msgRepo.saveMessage(
        GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          transportPeerId: 'peer-sender',
          senderUsername: 'Sender',
          text: 'GIRD-001 in-doubt failed text',
          timestamp: localTimestamp,
          keyGeneration: 1,
          status: 'failed',
          isIncoming: false,
          createdAt: createdAt,
          wireEnvelope: '{"cmd":"group:publish"}',
          inboxStored: false,
          inboxRetryPayload: '{"cmd":"group:inboxStore"}',
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: 'GIRD-001 in-doubt failed text',
        timestamp: localTimestamp
            .add(const Duration(seconds: 5))
            .toIso8601String(),
        selfPeerId: 'peer-sender',
        transportPeerId: 'peer-sender',
        messageId: messageId,
      );

      expect(result, isNotNull);
      expect(result!.id, messageId);
      expect(result.isIncoming, isFalse);
      expect(result.status, 'sent');

      final saved = await msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      expect(saved!.isIncoming, isFalse);
      expect(saved.status, 'sent');
      expect(saved.text, 'GIRD-001 in-doubt failed text');
      expect(saved.timestamp, localTimestamp);
      expect(saved.createdAt, createdAt);
      expect(saved.wireEnvelope, isNull);
      expect(saved.inboxStored, isFalse);
      expect(saved.inboxRetryPayload, '{"cmd":"group:inboxStore"}');
      expect(msgRepo.count, 1);
      expect(await msgRepo.getUnreadCount('group-1'), 0);
      final failedIds = (await msgRepo.getFailedOutgoingMessages())
          .map((row) => row.id)
          .toSet();
      expect(failedIds, isNot(contains(messageId)));
    },
  );

  test(
    'strips dangerous bidi controls and preserves safe markers on incoming save',
    () async {
      const rawText = 'Hello\u202E\u200E world';
      const sanitizedText = 'Hello\u200E world';

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: rawText,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      expect(result, isNotNull);
      expect(result!.text, sanitizedText);

      final saved = await msgRepo.getMessage(result.id);
      expect(saved, isNotNull);
      expect(saved!.text, sanitizedText);
      expect(saved.text, isNot(contains('\u202E')));
    },
  );

  test('ignores message for unknown group', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'nonexistent-group',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(result, isNull);
  });

  test('saves message to repo', () async {
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Test message',
      timestamp: DateTime.now().toUtc().toIso8601String(),
    );

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.text, 'Test message');
  });

  test(
    'duplicate by messageId skips repeated group and member lookups',
    () async {
      final countingRepo = _CountingGroupRepository();
      await countingRepo.saveGroup(testGroup);
      await countingRepo.saveMember(testMember);
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'msg-duplicate-fast-path',
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          senderUsername: 'Sender',
          text: 'Existing message',
          timestamp: DateTime.now().toUtc(),
          status: 'delivered',
          isIncoming: true,
          createdAt: DateTime.now().toUtc(),
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: countingRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Existing message',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-duplicate-fast-path',
      );

      expect(result, isNull);
      expect(countingRepo.getGroupCalls, 0);
      expect(countingRepo.getMemberCalls, 0);
    },
  );

  test(
    'identity diagnostic captures successful incoming row evidence',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      const messageId = 'identity-diagnostic-success';
      final ts = DateTime.utc(2026, 6, 5, 12).toIso8601String();

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Identity diagnostic text',
        timestamp: ts,
        messageId: messageId,
        deliverySource: 'live',
      );

      expect(result, isNotNull);
      final success = flowEvents.singleWhere(
        (event) => event['event'] == 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
      );
      final details = success['details'] as Map<String, dynamic>;
      expect(details['messageId'], messageId);
      expect(details['localRowId'], messageId);
      expect(details['candidateLocalRowId'], messageId);
      expect(details['rawMessageId'], messageId);
      expect(details['groupId'], 'group-1');
      expect(details['senderId'], 'peer-sender');
      expect(details['text'], 'Identity diagnostic text');
      expect(details['timestamp'], ts);
      expect(details['rowTimestamp'], ts);
      expect(details['createdAt'], result!.createdAt.toIso8601String());
      expect(details['incoming'], true);
      expect(details['deliverySource'], 'live');
      expect(details.containsKey('dedupeBy'), isFalse);
      expect(details.containsKey('existingLocalRowId'), isFalse);
    },
  );

  test(
    'identity diagnostic captures exact messageId duplicate evidence',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final existingCreatedAt = DateTime.utc(2026, 6, 5, 12, 1);
      final existingTimestamp = DateTime.utc(2026, 6, 5, 12, 0);
      await msgRepo.saveMessage(
        GroupMessage(
          id: 'identity-diagnostic-duplicate',
          groupId: 'group-1',
          senderPeerId: 'peer-sender',
          senderUsername: 'Sender',
          text: 'Existing duplicate text',
          timestamp: existingTimestamp,
          status: 'delivered',
          isIncoming: true,
          createdAt: existingCreatedAt,
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Existing duplicate text',
        timestamp: existingTimestamp.toIso8601String(),
        messageId: 'identity-diagnostic-duplicate',
        deliverySource: 'replay',
      );

      expect(result, isNull);
      final duplicate = flowEvents.singleWhere(
        (event) => event['event'] == 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
      );
      final details = duplicate['details'] as Map<String, dynamic>;
      expect(details['dedupeBy'], 'messageId');
      expect(details['messageId'], 'identity-diagnostic-duplicate');
      expect(details['localRowId'], 'identity-diagnostic-duplicate');
      expect(details['existingLocalRowId'], 'identity-diagnostic-duplicate');
      expect(details['candidateLocalRowId'], 'identity-diagnostic-duplicate');
      expect(details['rawMessageId'], 'identity-diagnostic-duplicate');
      expect(details['groupId'], 'group-1');
      expect(details['senderId'], 'peer-sender');
      expect(details['text'], 'Existing duplicate text');
      expect(details['timestamp'], existingTimestamp.toIso8601String());
      expect(details['rowTimestamp'], existingTimestamp.toIso8601String());
      expect(details['createdAt'], existingCreatedAt.toIso8601String());
      expect(details['incoming'], true);
      expect(details['deliverySource'], 'replay');
    },
  );

  test('persists quotedMessageId from incoming payload', () async {
    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Reply in group',
      timestamp: DateTime.now().toUtc().toIso8601String(),
      quotedMessageId: 'msg-parent-1',
    );

    expect(result, isNotNull);
    expect(result!.quotedMessageId, 'msg-parent-1');

    final saved = await msgRepo.getMessage(result.id);
    expect(saved, isNotNull);
    expect(saved!.quotedMessageId, 'msg-parent-1');
  });

  test(
    'rejects messages from unknown members without storing a ghost row',
    () async {
      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'unknown-peer',
        senderUsername: 'Unknown',
        keyEpoch: 0,
        text: 'Hello from unknown',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-unknown-peer',
      );

      expect(result, isNull);
      expect(msgRepo.count, 0);
      expect(await msgRepo.getMessage('msg-unknown-peer'), isNull);
    },
  );

  test(
    'refreshes stored member username from later incoming group traffic',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-sender',
          username: 'Old Name',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Fresh Name',
        keyEpoch: 0,
        text: 'Name refresh',
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );

      expect(result, isNotNull);
      final refreshedMember = await groupRepo.getMember(
        'group-1',
        'peer-sender',
      );
      expect(refreshedMember, isNotNull);
      expect(refreshedMember!.username, 'Fresh Name');
      expect(result!.senderUsername, 'Fresh Name');
    },
  );

  test(
    'accepts removed-sender message when it predates the persisted removal cutoff',
    () async {
      final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      await saveRemovalCutoff(
        removedPeerId: 'peer-removed',
        removedAt: removedAt,
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 0,
        text: 'Sent before cutoff',
        timestamp: removedAt
            .subtract(const Duration(milliseconds: 1))
            .toIso8601String(),
        messageId: 'msg-before-cutoff',
      );

      expect(result, isNotNull);
      expect(result!.text, 'Sent before cutoff');
      expect(result.id, 'msg-before-cutoff');
    },
  );

  test(
    'rejects removed-sender message when it is at the persisted removal cutoff',
    () async {
      final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      await saveRemovalCutoff(
        removedPeerId: 'peer-removed',
        removedAt: removedAt,
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 0,
        text: 'Sent at cutoff',
        timestamp: removedAt.toIso8601String(),
        messageId: 'msg-at-cutoff',
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-at-cutoff'), isNull);
    },
  );

  test(
    'GM-013 accepts before-cutoff removed-sender traffic and emits after-cutoff rejection event',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      const sharedMessageId = 'gm013-charlie-boundary';
      final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      final beforeSentAt = removedAt.subtract(const Duration(milliseconds: 1));
      await saveRemovalCutoff(
        removedPeerId: 'peer-charlie',
        removedAt: removedAt,
      );

      final before = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-charlie',
        senderUsername: 'Charlie',
        keyEpoch: 0,
        text: 'GM-013 before cutoff',
        timestamp: beforeSentAt.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(before, isNotNull);
      expect(before!.id, sharedMessageId);
      expect(before.timestamp, beforeSentAt);

      final after = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-charlie',
        senderUsername: 'Charlie',
        keyEpoch: 0,
        text: 'GM-013 at cutoff',
        timestamp: removedAt.toIso8601String(),
        messageId: 'gm013-charlie-at-cutoff',
      );
      expect(after, isNull);
      expect(await msgRepo.getMessage('gm013-charlie-at-cutoff'), isNull);

      final replayAfterCutoff = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-charlie',
        senderUsername: 'Charlie',
        keyEpoch: 0,
        text: 'GM-013 after cutoff replay',
        timestamp: removedAt.add(const Duration(seconds: 1)).toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(replayAfterCutoff, isNull);

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.text, 'GM-013 before cutoff');
      expect(saved.timestamp, beforeSentAt);
      expect(
        (await msgRepo.getMessagesPage(
          'group-1',
        )).where((message) => message.id == sharedMessageId),
        hasLength(1),
      );

      final rejectionEvents = flowEvents
          .where(
            (event) =>
                event['event'] ==
                'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
          )
          .toList(growable: false);
      expect(rejectionEvents, hasLength(1));
      final details = rejectionEvents.single['details'] as Map<String, dynamic>;
      expect(details['cutoffAt'], removedAt.toIso8601String());
    },
  );

  test(
    'rejects unknown sender when persisted removal cutoff belongs to another peer',
    () async {
      await saveRemovalCutoff(
        removedPeerId: 'peer-other',
        removedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-new',
        senderUsername: 'New sender',
        keyEpoch: 0,
        text: 'Hello from future member',
        timestamp: DateTime.utc(2026, 4, 5, 12, 0, 1).toIso8601String(),
        messageId: 'msg-new-sender',
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-new-sender'), isNull);
    },
  );

  test(
    'SV-002 removed old-key publish does not mutate timeline or unread state',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final removedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 10),
      );
      await saveRemovalCutoff(
        removedPeerId: 'peer-removed',
        removedAt: removedAt,
      );
      await msgRepo.markAsRead('group-1');
      final removalRow = await msgRepo.getLatestMessage('group-1');
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 2,
          encryptedKey: 'sv002-current-key',
          createdAt: removedAt.add(const Duration(seconds: 1)),
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 1,
        text: 'SV-002 removed old-key publish',
        timestamp: removedAt.add(const Duration(seconds: 2)).toIso8601String(),
        messageId: 'sv002-removed-old-key',
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('sv002-removed-old-key'), isNull);
      expect((await msgRepo.getLatestMessage('group-1'))!.id, removalRow!.id);
      expect(await msgRepo.getUnreadCount('group-1'), 0);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
        ),
        isTrue,
      );
    },
  );

  test(
    'UP-004 excludes removed-window unread and clears post-readd unread on open',
    () async {
      final joinedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 20),
      );
      final removedAt = joinedAt.add(const Duration(minutes: 5));
      final readdedAt = removedAt.add(const Duration(minutes: 5));
      final charlie = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-charlie',
        username: 'Charlie',
        role: MemberRole.writer,
        joinedAt: joinedAt,
      );

      await groupRepo.saveMember(testMember.copyWith(joinedAt: joinedAt));
      await groupRepo.saveMember(charlie);

      final beforeRemoval = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: 'UP-004 before removal unread',
        timestamp: removedAt
            .subtract(const Duration(seconds: 30))
            .toIso8601String(),
        selfPeerId: 'peer-charlie',
        messageId: 'up004-before-removal',
      );

      expect(beforeRemoval, isNotNull);
      expect(await msgRepo.getUnreadCount('group-1'), 1);

      await msgRepo.markAsRead('group-1');
      expect(await msgRepo.getUnreadCount('group-1'), 0);

      await saveRemovalCutoff(
        removedPeerId: 'peer-charlie',
        removedAt: removedAt,
      );
      await msgRepo.markAsRead('group-1');
      await groupRepo.saveMember(charlie.copyWith(joinedAt: readdedAt));

      final removedWindow = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 2,
        text: 'UP-004 removed-window message',
        timestamp: removedAt.add(const Duration(seconds: 30)).toIso8601String(),
        selfPeerId: 'peer-charlie',
        messageId: 'up004-removed-window',
      );

      expect(removedWindow, isNull);
      expect(await msgRepo.getMessage('up004-removed-window'), isNull);
      expect(await msgRepo.getUnreadCount('group-1'), 0);

      final postReadd = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 2,
        text: 'UP-004 post-readd unread',
        timestamp: readdedAt.add(const Duration(seconds: 30)).toIso8601String(),
        selfPeerId: 'peer-charlie',
        messageId: 'up004-post-readd',
      );

      expect(postReadd, isNotNull);
      expect(await msgRepo.getUnreadCount('group-1'), 1);

      await msgRepo.markAsRead('group-1');
      expect(await msgRepo.getUnreadCount('group-1'), 0);
    },
  );

  test(
    'RA-014 rejects old-key post-readd sender message and accepts later current epoch',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final removedAt = DateTime.utc(2026, 4, 5, 12, 0);
      final readdedAt = removedAt.add(const Duration(minutes: 2));
      await saveRemovalCutoff(
        removedPeerId: 'peer-sender',
        removedAt: removedAt,
      );
      await groupRepo.saveMember(testMember.copyWith(joinedAt: readdedAt));
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'ra014-old-key',
          createdAt: removedAt.subtract(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 3,
          encryptedKey: 'ra014-current-key',
          createdAt: readdedAt,
        ),
      );

      final stale = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: 'RA-014 stale old-key post-readd',
        timestamp: readdedAt.add(const Duration(seconds: 1)).toIso8601String(),
        messageId: 'ra014-stale-old-key',
      );

      expect(stale, isNull);
      expect(await msgRepo.getMessage('ra014-stale-old-key'), isNull);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_STALE_EPOCH_AFTER_READD_REJECTED',
        ),
        isTrue,
      );

      final current = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 3,
        text: 'RA-014 current epoch after rejection',
        timestamp: readdedAt.add(const Duration(seconds: 2)).toIso8601String(),
        messageId: 'ra014-current-epoch',
      );

      expect(current, isNotNull);
      expect(current!.keyGeneration, 3);
      expect(
        (await msgRepo.getMessage('ra014-current-epoch'))!.text,
        'RA-014 current epoch after rejection',
      );
    },
  );

  test(
    'accepts a message that predates the persisted dissolve cutoff',
    () async {
      await groupRepo.updateGroup(
        testGroup.copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
          dissolvedBy: 'peer-admin',
        ),
      );

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Sent before dissolve',
        timestamp: DateTime.utc(2026, 4, 5, 11, 59, 59).toIso8601String(),
        messageId: 'msg-before-dissolve',
      );

      expect(result, isNotNull);
      expect(result!.id, 'msg-before-dissolve');
    },
  );

  test('rejects a message at or after the persisted dissolve cutoff', () async {
    final dissolvedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
    await groupRepo.updateGroup(
      testGroup.copyWith(
        isDissolved: true,
        dissolvedAt: dissolvedAt,
        dissolvedBy: 'peer-admin',
      ),
    );

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Too late',
      timestamp: dissolvedAt.toIso8601String(),
      messageId: 'msg-after-dissolve',
    );

    expect(result, isNull);
    expect(await msgRepo.getMessage('msg-after-dissolve'), isNull);
  });

  test('deduplicates identical incoming messages', () async {
    final ts = DateTime.now().toUtc().toIso8601String();

    final result1 = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello!',
      timestamp: ts,
    );
    expect(result1, isNotNull);

    // Second call with same fields
    final result2 = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Hello!',
      timestamp: ts,
    );
    expect(result2, isNull); // duplicate → skipped
    expect(msgRepo.count, 1); // still only 1 message
  });

  test(
    'identity diagnostic captures legacy id-less content duplicate',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final ts = DateTime.utc(2026, 6, 5, 12, 2).toIso8601String();

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Legacy id-less diagnostic',
        timestamp: ts,
        deliverySource: 'live',
      );
      final duplicate = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Legacy id-less diagnostic',
        timestamp: ts,
        deliverySource: 'replay',
      );

      expect(first, isNotNull);
      expect(duplicate, isNull);
      expect(msgRepo.count, 1);

      final duplicateEvent = flowEvents.singleWhere(
        (event) => event['event'] == 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
      );
      final details = duplicateEvent['details'] as Map<String, dynamic>;
      expect(details['dedupeBy'], 'content');
      expect(details['messageId'], first!.id);
      expect(details['localRowId'], first.id);
      expect(details['existingLocalRowId'], first.id);
      expect(details.containsKey('rawMessageId'), isFalse);
      expect(details.containsKey('candidateLocalRowId'), isFalse);
      expect(details['groupId'], 'group-1');
      expect(details['senderId'], 'peer-sender');
      expect(details['text'], 'Legacy id-less diagnostic');
      expect(details['timestamp'], ts);
      expect(details['rowTimestamp'], ts);
      expect(details['createdAt'], first.createdAt.toIso8601String());
      expect(details['incoming'], true);
      expect(details['deliverySource'], 'replay');
    },
  );

  test(
    'PGC-007 identity diagnostic distinct stable message IDs with same content and timestamp both persist',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final ts = DateTime.utc(2026, 5, 23, 12).toIso8601String();

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'PGC-007 collision text',
        timestamp: ts,
        messageId: 'pgc007-stable-id-1',
      );
      final second = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'PGC-007 collision text',
        timestamp: ts,
        messageId: 'pgc007-stable-id-2',
      );

      expect(first, isNotNull);
      expect(first!.id, 'pgc007-stable-id-1');
      expect(second, isNotNull);
      expect(second!.id, 'pgc007-stable-id-2');
      expect(msgRepo.count, 2);

      final page = await msgRepo.getMessagesPage('group-1');
      expect(page, hasLength(2));
      expect(
        page.map((message) => message.id),
        containsAll(['pgc007-stable-id-1', 'pgc007-stable-id-2']),
      );

      final successEvents = flowEvents
          .where(
            (event) => event['event'] == 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
          )
          .toList();
      expect(successEvents, hasLength(2));
      expect(
        successEvents
            .map(
              (event) =>
                  (event['details'] as Map<String, dynamic>)['messageId'],
            )
            .toSet(),
        {'pgc007-stable-id-1', 'pgc007-stable-id-2'},
      );
      expect(
        flowEvents.where(
          (event) => event['event'] == 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE',
        ),
        isEmpty,
      );
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_LOGICAL_DELIVERY_MATCH',
        ),
        isEmpty,
      );
    },
  );

  test(
    'logical delivery convergence skips divergent stable id replay with shared logicalDeliveryId',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));
      final mediaRepo = InMemoryMediaAttachmentRepository();

      final ts = DateTime.utc(2026, 6, 5, 12, 6).toIso8601String();

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Shared logical delivery body',
        timestamp: ts,
        messageId: 'logical-local-row-a',
        logicalDeliveryId: 'logical-delivery-shared-1',
        deliverySource: 'live',
      );
      final second = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Shared logical delivery body',
        timestamp: ts,
        messageId: 'logical-local-row-b',
        logicalDeliveryId: 'logical-delivery-shared-1',
        quotedMessageId: 'logical-parent-row',
        media: _gird003Media(
          id: 'logical-delivery-media-1',
          createdAt: DateTime.utc(2026, 6, 5, 12, 6, 1).toIso8601String(),
        ),
        mediaAttachmentRepo: mediaRepo,
        deliverySource: 'replay',
      );

      expect(first, isNotNull);
      expect(second, isNull);
      expect(msgRepo.count, 1);
      expect(first!.logicalDeliveryId, 'logical-delivery-shared-1');
      expect(await msgRepo.getMessage('logical-local-row-b'), isNull);

      final canonical = await msgRepo.getMessage('logical-local-row-a');
      expect(canonical, isNotNull);
      expect(canonical!.logicalDeliveryId, 'logical-delivery-shared-1');
      expect(canonical.quotedMessageId, 'logical-parent-row');
      expect(
        await mediaRepo.getAttachmentsForMessage(
          'logical-local-row-a',
          owner: MediaOwnerLane.group,
        ),
        hasLength(1),
      );
      expect(
        await mediaRepo.getAttachmentsForMessage(
          'logical-local-row-b',
          owner: MediaOwnerLane.group,
        ),
        isEmpty,
      );

      final duplicateEvent = flowEvents.singleWhere(
        (event) =>
            event['event'] == 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE' &&
            (event['details'] as Map<String, dynamic>)['dedupeBy'] ==
                'logicalDeliveryId',
      );
      final details = duplicateEvent['details'] as Map<String, dynamic>;
      expect(details['dedupeBy'], 'logicalDeliveryId');
      expect(details['rawMessageId'], 'logical-local-row-b');
      expect(details['candidateLocalRowId'], 'logical-local-row-b');
      expect(details['logicalDeliveryId'], 'logical-delivery-shared-1');
      expect(details['messageId'], 'logical-local-row-a');
      expect(details['localRowId'], 'logical-local-row-a');
      expect(details['existingLocalRowId'], 'logical-local-row-a');
      expect(details['quotedMessageId'], 'logical-parent-row');
      expect(details['groupId'], 'group-1');
      expect(details['senderId'], 'peer-sender');
      expect(details['text'], 'Shared logical delivery body');
      expect(details['timestamp'], ts);
      expect(details['rowTimestamp'], ts);
      expect(details['incoming'], true);
      expect(details['deliverySource'], 'replay');

      final successEvents = flowEvents
          .where(
            (event) => event['event'] == 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
          )
          .toList();
      expect(successEvents, hasLength(1));
    },
  );

  test(
    'TC-330-P1 ordinary logical duplicate returns its canonical notification identity',
    () async {
      final timestamp = DateTime.utc(2026, 8, 3, 12, 10).toIso8601String();
      final first = await handleIncomingGroupMessageDetailed(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Canonical custody',
        timestamp: timestamp,
        messageId: 'canonical-custody-id',
        logicalDeliveryId: 'logical-custody-id',
      );
      expect(first, isA<IncomingGroupMessageDelivered>());

      final duplicate = await handleIncomingGroupMessageDetailed(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Canonical custody',
        timestamp: timestamp,
        messageId: 'reminted-custody-alias',
        logicalDeliveryId: 'logical-custody-id',
      );

      expect(duplicate, isA<IncomingGroupMessageDuplicate>());
      final canonicalDuplicate = duplicate as IncomingGroupMessageDuplicate;
      expect(canonicalDuplicate.canonicalMessage.id, 'canonical-custody-id');
      expect(canonicalDuplicate.persistedAttachmentIds, isEmpty);
      expect(await msgRepo.getMessage('reminted-custody-alias'), isNull);
    },
  );

  test(
    'GFR-001 logical delivery replay keeps one receiver-visible row',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final ts = DateTime.utc(2026, 6, 5, 12, 7).toIso8601String();

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'GFR-001 shared logical delivery body',
        timestamp: ts,
        messageId: 'gfr001-receiver-row-a',
        logicalDeliveryId: 'gfr001-logical-delivery-shared',
        deliverySource: 'live',
      );
      final second = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'GFR-001 shared logical delivery body',
        timestamp: ts,
        messageId: 'gfr001-receiver-row-b',
        logicalDeliveryId: 'gfr001-logical-delivery-shared',
        deliverySource: 'replay',
      );

      expect(first, isNotNull);
      expect(second, isNull);
      expect(msgRepo.count, 1);
      expect(await msgRepo.getMessage('gfr001-receiver-row-b'), isNull);

      final canonical = await msgRepo.getMessage('gfr001-receiver-row-a');
      expect(canonical, isNotNull);
      expect(canonical!.logicalDeliveryId, 'gfr001-logical-delivery-shared');
      expect(canonical.text, 'GFR-001 shared logical delivery body');
      expect(canonical.isIncoming, true);

      final duplicateEvent = flowEvents.singleWhere(
        (event) =>
            event['event'] == 'GROUP_HANDLE_INCOMING_MSG_DUPLICATE' &&
            (event['details'] as Map<String, dynamic>)['dedupeBy'] ==
                'logicalDeliveryId',
      );
      final details = duplicateEvent['details'] as Map<String, dynamic>;
      expect(details['messageId'], 'gfr001-receiver-row-a');
      expect(details['rawMessageId'], 'gfr001-receiver-row-b');
      expect(details['logicalDeliveryId'], 'gfr001-logical-delivery-shared');

      final successEvents = flowEvents
          .where(
            (event) => event['event'] == 'GROUP_HANDLE_INCOMING_MSG_SUCCESS',
          )
          .toList();
      expect(successEvents, hasLength(1));
    },
  );

  test(
    'PGC-007 event-log path keeps distinct stable message IDs despite same content',
    () async {
      final eventLog = _FakeEventLog();
      final ts = DateTime.utc(2026, 5, 23, 12, 1).toIso8601String();

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'PGC-007 event-log collision text',
        timestamp: ts,
        messageId: 'pgc007-event-log-id-1',
        appendGroupEventLogEntry: eventLog.append,
      );
      final second = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'PGC-007 event-log collision text',
        timestamp: ts,
        messageId: 'pgc007-event-log-id-2',
        appendGroupEventLogEntry: eventLog.append,
      );

      expect(first, isNotNull);
      expect(first!.id, 'pgc007-event-log-id-1');
      expect(second, isNotNull);
      expect(second!.id, 'pgc007-event-log-id-2');
      expect(msgRepo.count, 2);
      expect(eventLog.entries, hasLength(2));
      expect(
        eventLog.entries.map((entry) => entry['sourceEventId']),
        containsAll(['pgc007-event-log-id-1', 'pgc007-event-log-id-2']),
      );

      final page = await msgRepo.getMessagesPage('group-1');
      expect(page, hasLength(2));
      expect(
        page.map((message) => message.id),
        containsAll(['pgc007-event-log-id-1', 'pgc007-event-log-id-2']),
      );
    },
  );

  test(
    'deduplicates messages after sanitizing invisible bidi controls',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();

      final result1 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Hello world',
        timestamp: ts,
      );
      expect(result1, isNotNull);

      final result2 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Hello\u200B world',
        timestamp: ts,
      );

      expect(result2, isNull);
      expect(msgRepo.count, 1);
    },
  );

  test('allows messages with different text or timestamp', () async {
    final ts1 = DateTime(2026, 1, 1).toUtc().toIso8601String();
    final ts2 = DateTime(2026, 1, 2).toUtc().toIso8601String();

    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'A',
      timestamp: ts1,
    );
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'B',
      timestamp: ts1,
    ); // different text
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'A',
      timestamp: ts2,
    ); // different time

    expect(msgRepo.count, 3); // all unique
  });

  test(
    'MS003 far future incoming timestamp is clamped to receive time',
    () async {
      final beforeReceive = DateTime.now().toUtc();
      final farFuture = beforeReceive.add(const Duration(days: 2));

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Future-skewed message',
        timestamp: farFuture.toIso8601String(),
        messageId: 'msg-future-skew',
      );
      final afterReceive = DateTime.now().toUtc();

      expect(result, isNotNull);
      expect(result!.timestamp.isBefore(farFuture), isTrue);
      expect(
        result.timestamp.isAfter(
          beforeReceive.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        result.timestamp.isBefore(afterReceive.add(const Duration(seconds: 1))),
        isTrue,
      );

      final saved = await msgRepo.getMessage('msg-future-skew');
      expect(saved, isNotNull);
      expect(saved!.timestamp, result.timestamp);
    },
  );

  test(
    'MS003 past current and near future timestamps retain chronological order',
    () async {
      final base = DateTime.now().toUtc();
      final past = base.subtract(const Duration(minutes: 3));
      final nearFuture = base.add(const Duration(minutes: 3));

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Current clock',
        timestamp: base.toIso8601String(),
        messageId: 'msg-clock-current',
      );
      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Past clock',
        timestamp: past.toIso8601String(),
        messageId: 'msg-clock-past',
      );
      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Near future clock',
        timestamp: nearFuture.toIso8601String(),
        messageId: 'msg-clock-near-future',
      );

      final page = await msgRepo.getMessagesPage('group-1');
      expect(page.map((message) => message.id), [
        'msg-clock-past',
        'msg-clock-current',
        'msg-clock-near-future',
      ]);
      expect(
        (await msgRepo.getLatestMessage('group-1'))!.id,
        'msg-clock-near-future',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Phase 6: messageId-based dedupe tests
  // ---------------------------------------------------------------------------
  test(
    'deduplicates by messageId when pubsub and group inbox deliver same message',
    () async {
      final ts = DateTime.now().toUtc().toIso8601String();
      const sharedMessageId = 'msg-shared-123';

      // First delivery (e.g. from pubsub).
      final result1 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Hello!',
        timestamp: ts,
        messageId: sharedMessageId,
      );
      expect(result1, isNotNull);
      expect(result1!.id, sharedMessageId);

      // Second delivery (e.g. from group inbox drain) with the same messageId.
      final result2 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Hello!',
        timestamp: ts,
        messageId: sharedMessageId,
      );
      expect(
        result2,
        isNull,
        reason: 'Duplicate by messageId should be skipped',
      );
      expect(msgRepo.count, 1, reason: 'Only one message should be saved');
    },
  );

  test('duplicate replay enriches a missing quotedMessageId', () async {
    const sharedMessageId = 'msg-quote-repair';
    final ts = DateTime.now().toUtc().toIso8601String();

    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Sparse live copy',
      timestamp: ts,
      messageId: sharedMessageId,
    );

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'Sparse live copy',
      timestamp: ts,
      messageId: sharedMessageId,
      quotedMessageId: 'msg-parent-1',
    );

    expect(result, isNull, reason: 'Replay is still a duplicate delivery');

    final saved = await msgRepo.getMessage(sharedMessageId);
    expect(saved, isNotNull);
    expect(saved!.quotedMessageId, 'msg-parent-1');
  });

  test(
    'duplicate replay with the same messageId ignores a tampered timestamp',
    () async {
      const sharedMessageId = 'msg-replay-timestamp-tampered';
      final originalTimestamp = DateTime.utc(2026, 4, 5, 11, 59, 59);
      final tamperedTimestamp = originalTimestamp.add(
        const Duration(minutes: 5),
      );

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Replay-resistant message',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Replay-resistant message',
        timestamp: tamperedTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );

      expect(
        replay,
        isNull,
        reason: 'Replayed messageId must still deduplicate',
      );

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.timestamp, originalTimestamp);
      expect(saved.text, 'Replay-resistant message');
      expect(msgRepo.count, 1);
    },
  );

  test(
    'duplicate replay with the same messageId ignores conflicting content',
    () async {
      const sharedMessageId = 'msg-replay-content-tampered';
      final originalTimestamp = DateTime.utc(2026, 4, 5, 12, 30, 0);

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Trusted live content',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Tampered inbox content',
        timestamp: originalTimestamp
            .add(const Duration(minutes: 1))
            .toIso8601String(),
        messageId: sharedMessageId,
      );

      expect(replay, isNull);

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.text, 'Trusted live content');
      expect(saved.timestamp, originalTimestamp);
      expect(msgRepo.count, 1);
    },
  );

  test(
    'SV-010 duplicate message id from different sender cannot overwrite valid row',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      const sharedMessageId = 'sv010-shared-message-id';
      final originalTimestamp = DateTime.utc(2026, 5, 14, 4, 0);

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Trusted Alice row',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      final conflict = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-bob',
        senderUsername: 'Bob',
        keyEpoch: 0,
        text: 'Bob poison row',
        timestamp: originalTimestamp
            .add(const Duration(minutes: 1))
            .toIso8601String(),
        messageId: sharedMessageId,
        quotedMessageId: 'bob-quote-poison',
      );

      expect(conflict, isNull);
      expect(msgRepo.count, 1);

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.senderPeerId, 'peer-sender');
      expect(saved.senderUsername, 'Sender');
      expect(saved.text, 'Trusted Alice row');
      expect(saved.timestamp, originalTimestamp);
      expect(saved.quotedMessageId, isNull);
      expect(
        flowEvents.any(
          (event) =>
              event['event'] ==
              'GROUP_HANDLE_INCOMING_MSG_DUPLICATE_ID_CONFLICT_REJECTED',
        ),
        isTrue,
      );
    },
  );

  test('duplicate replay saves missing media attachments', () async {
    final mediaRepo = InMemoryMediaAttachmentRepository();
    const sharedMessageId = 'msg-media-repair';
    final ts = DateTime.now().toUtc().toIso8601String();
    final media = [
      {
        'id': 'blob-repair-1',
        'mime': 'image/png',
        'size': 2048,
        'mediaType': 'image',
        'contentHash': _validContentHash,
        'encryptionKeyBase64': 'key-fixture',
        'encryptionNonce': 'nonce-fixture',
        'encryptionScheme': 'blob_aes_256_gcm_v1',
        'downloadStatus': 'pending',
        'createdAt': ts,
      },
    ];

    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: '',
      timestamp: ts,
      messageId: sharedMessageId,
      mediaAttachmentRepo: mediaRepo,
    );

    expect(mediaRepo.count, 0);

    final result = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: '',
      timestamp: ts,
      messageId: sharedMessageId,
      media: media,
      mediaAttachmentRepo: mediaRepo,
    );

    expect(result, isNull, reason: 'Replay is still a duplicate delivery');
    expect(mediaRepo.count, 1);

    final attachments = await mediaRepo.getAttachmentsForMessage(
      sharedMessageId,
      owner: MediaOwnerLane.group,
    );
    expect(attachments, hasLength(1));
    expect(attachments.first.id, 'blob-repair-1');
  });

  test('duplicate group inbox replay does not resave media', () async {
    final mediaRepo = InMemoryMediaAttachmentRepository();
    final ts = DateTime.now().toUtc().toIso8601String();
    const sharedMessageId = 'msg-media-dup';

    final media = [
      {
        'id': 'blob-dup-test',
        'mime': 'image/png',
        'size': 1000,
        'mediaType': 'image',
        'contentHash': _validContentHash,
        'encryptionKeyBase64': 'key-fixture',
        'encryptionNonce': 'nonce-fixture',
        'encryptionScheme': 'blob_aes_256_gcm_v1',
        'downloadStatus': 'pending',
        'createdAt': ts,
      },
    ];

    // First delivery — message and media saved.
    await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'With media',
      timestamp: ts,
      messageId: sharedMessageId,
      media: media,
      mediaAttachmentRepo: mediaRepo,
    );
    expect(msgRepo.count, 1);
    expect(mediaRepo.count, 1);

    // Second delivery — same messageId, should be deduplicated.
    final result2 = await handleIncomingGroupMessage(
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      senderId: 'peer-sender',
      senderUsername: 'Sender',
      keyEpoch: 0,
      text: 'With media',
      timestamp: ts,
      messageId: sharedMessageId,
      media: media,
      mediaAttachmentRepo: mediaRepo,
    );
    expect(result2, isNull);
    expect(mediaRepo.count, 1, reason: 'Media should not be saved again');
  });

  test(
    'P269 detailed duplicate outcome reports exact persisted media across every dedupe branch',
    () async {
      final sentAt = DateTime.utc(2026, 7, 20, 12);

      Future<(InMemoryGroupRepository, InMemoryGroupMessageRepository)>
      createFixture() async {
        final groups = InMemoryGroupRepository();
        final messages = InMemoryGroupMessageRepository();
        await groups.saveGroup(
          GroupModel(
            id: 'group-1',
            name: 'P269 group',
            type: GroupType.chat,
            topicName: 'p269-topic',
            createdAt: sentAt.subtract(const Duration(hours: 2)),
            createdBy: 'peer-admin',
            myRole: GroupRole.admin,
          ),
        );
        for (final peerId in const ['peer-sender', 'peer-self']) {
          await groups.saveMember(
            GroupMember(
              groupId: 'group-1',
              peerId: peerId,
              username: peerId == 'peer-self' ? 'Self' : 'Sender',
              role: MemberRole.writer,
              joinedAt: sentAt.subtract(const Duration(hours: 1)),
            ),
          );
        }
        return (groups, messages);
      }

      GroupMessage canonicalMessage(
        String id, {
        String senderId = 'peer-sender',
        String text = 'P269 duplicate',
        String status = 'delivered',
        bool isIncoming = true,
        String? logicalDeliveryId,
      }) {
        return GroupMessage(
          id: id,
          groupId: 'group-1',
          senderPeerId: senderId,
          transportPeerId: senderId,
          senderUsername: senderId == 'peer-self' ? 'Self' : 'Sender',
          text: text,
          timestamp: sentAt,
          logicalDeliveryId: logicalDeliveryId,
          keyGeneration: 0,
          status: status,
          isIncoming: isIncoming,
          createdAt: sentAt,
        );
      }

      Future<IncomingGroupMessageDetailedOutcome> handleDetailed({
        required InMemoryGroupRepository groups,
        required InMemoryGroupMessageRepository messages,
        required String text,
        String senderId = 'peer-sender',
        String? selfPeerId,
        String? messageId,
        String? logicalDeliveryId,
        String? quotedMessageId,
        List<Map<String, dynamic>>? media,
        MediaAttachmentRepository? mediaRepository,
        AppendGroupEventLogEntry? appendEvent,
      }) {
        return handleIncomingGroupMessageDetailed(
          groupRepo: groups,
          msgRepo: messages,
          groupId: 'group-1',
          senderId: senderId,
          senderUsername: senderId == 'peer-self' ? 'Self' : 'Sender',
          keyEpoch: 0,
          text: text,
          timestamp: sentAt.toIso8601String(),
          selfPeerId: selfPeerId,
          transportPeerId: senderId,
          messageId: messageId,
          logicalDeliveryId: logicalDeliveryId,
          quotedMessageId: quotedMessageId,
          media: media,
          mediaAttachmentRepo: mediaRepository,
          appendGroupEventLogEntry: appendEvent,
          nowUtc: () => sentAt.add(const Duration(minutes: 1)),
        );
      }

      // New rows and reconciled self echoes remain deliveries, preserving the
      // nullable wrapper's two non-null behaviors.
      final (newGroups, newMessages) = await createFixture();
      final newDelivery = await handleDetailed(
        groups: newGroups,
        messages: newMessages,
        text: 'P269 new delivery',
        messageId: 'p269-new-delivery',
      );
      expect(newDelivery, isA<IncomingGroupMessageDelivered>());
      expect(
        (newDelivery as IncomingGroupMessageDelivered).message.id,
        'p269-new-delivery',
      );

      final (selfGroups, selfMessages) = await createFixture();
      await selfMessages.saveMessage(
        canonicalMessage(
          'p269-self-echo',
          senderId: 'peer-self',
          text: 'P269 self echo',
          status: 'pending',
          isIncoming: false,
        ),
      );
      final selfEcho = await handleDetailed(
        groups: selfGroups,
        messages: selfMessages,
        senderId: 'peer-self',
        selfPeerId: 'peer-self',
        text: 'P269 self echo',
        messageId: 'p269-self-echo',
      );
      expect(selfEcho, isA<IncomingGroupMessageDelivered>());
      expect(
        (selfEcho as IncomingGroupMessageDelivered).message.status,
        'sent',
      );
      expect(selfEcho.message.isIncoming, isFalse);

      // Exit 1: the no-event-log same-ID fast path reports only the newly
      // committed blob, never an ID that was already attached.
      final (fastGroups, fastMessages) = await createFixture();
      const fastCanonicalId = 'p269-fast-canonical';
      await fastMessages.saveMessage(
        canonicalMessage(fastCanonicalId, text: 'P269 fast duplicate'),
      );
      final fastMedia = _GuardedRecordingMediaAttachmentRepository();
      final existingFastWire = _gird003Media(
        id: 'p269-fast-existing',
        createdAt: sentAt.toIso8601String(),
      );
      final newFastWire = _gird003Media(
        id: 'p269-fast-new',
        createdAt: sentAt.add(const Duration(seconds: 1)).toIso8601String(),
      );
      await fastMedia.saveAttachment(
        MediaAttachment.fromJson(
          existingFastWire.single,
        ).copyWith(messageId: fastCanonicalId),
        owner: MediaOwnerLane.group,
      );
      final fastOutcome = await handleDetailed(
        groups: fastGroups,
        messages: fastMessages,
        text: 'P269 fast duplicate',
        messageId: fastCanonicalId,
        quotedMessageId: 'p269-fast-quote',
        media: [...existingFastWire, ...newFastWire],
        mediaRepository: fastMedia,
      );
      expect(fastOutcome, isA<IncomingGroupMessageDuplicateEnriched>());
      final fastEnriched = fastOutcome as IncomingGroupMessageDuplicateEnriched;
      expect(fastEnriched.canonicalMessage.id, fastCanonicalId);
      expect(fastEnriched.persistedAttachmentIds, {'p269-fast-new'});
      expect(fastMedia.guardedSaveCalls, 1);
      expect(
        (await fastMedia.getAttachmentsForMessage(
          fastCanonicalId,
          owner: MediaOwnerLane.group,
        )).map((attachment) => attachment.id).toSet(),
        {'p269-fast-existing', 'p269-fast-new'},
      );
      expect(
        (await fastMessages.getMessage(fastCanonicalId))?.quotedMessageId,
        'p269-fast-quote',
      );

      final identicalThirdReplay = await handleDetailed(
        groups: fastGroups,
        messages: fastMessages,
        text: 'P269 fast duplicate',
        messageId: fastCanonicalId,
        quotedMessageId: 'p269-fast-quote',
        media: [...existingFastWire, ...newFastWire],
        mediaRepository: fastMedia,
      );
      expect(identicalThirdReplay, isA<IncomingGroupMessageIgnored>());
      expect(fastMedia.guardedSaveCalls, 1);

      // Exit 2: installing event-log tamper gating moves the same stable-ID
      // replay to the post-log branch, which reports its committed media.
      final (eventGroups, eventMessages) = await createFixture();
      const eventCanonicalId = 'p269-event-canonical';
      await eventMessages.saveMessage(
        canonicalMessage(eventCanonicalId, text: 'P269 event duplicate'),
      );
      final eventMedia = _GuardedRecordingMediaAttachmentRepository();
      final eventLog = _FakeEventLog();
      final eventOutcome = await handleDetailed(
        groups: eventGroups,
        messages: eventMessages,
        text: 'P269 event duplicate',
        messageId: eventCanonicalId,
        media: _gird003Media(
          id: 'p269-event-new',
          createdAt: sentAt.toIso8601String(),
        ),
        mediaRepository: eventMedia,
        appendEvent: eventLog.append,
      );
      expect(eventOutcome, isA<IncomingGroupMessageDuplicateEnriched>());
      final eventEnriched =
          eventOutcome as IncomingGroupMessageDuplicateEnriched;
      expect(eventEnriched.canonicalMessage.id, eventCanonicalId);
      expect(eventEnriched.persistedAttachmentIds, {'p269-event-new'});
      expect(eventLog.entries, hasLength(1));

      // Exit 3: a reminted wire message ID with a stable logical-delivery ID
      // persists media under the original canonical parent.
      final (logicalGroups, logicalMessages) = await createFixture();
      const logicalCanonicalId = 'p269-logical-canonical';
      await logicalMessages.saveMessage(
        canonicalMessage(
          logicalCanonicalId,
          text: 'P269 logical duplicate',
          logicalDeliveryId: 'p269-logical-delivery',
        ),
      );
      final logicalMedia = _GuardedRecordingMediaAttachmentRepository();
      final logicalOutcome = await handleDetailed(
        groups: logicalGroups,
        messages: logicalMessages,
        text: 'P269 logical duplicate',
        messageId: 'p269-logical-reminted',
        logicalDeliveryId: 'p269-logical-delivery',
        media: _gird003Media(
          id: 'p269-logical-new',
          createdAt: sentAt.toIso8601String(),
        ),
        mediaRepository: logicalMedia,
      );
      expect(logicalOutcome, isA<IncomingGroupMessageDuplicateEnriched>());
      final logicalEnriched =
          logicalOutcome as IncomingGroupMessageDuplicateEnriched;
      expect(logicalEnriched.canonicalMessage.id, logicalCanonicalId);
      expect(logicalEnriched.persistedAttachmentIds, {'p269-logical-new'});
      expect(await logicalMessages.getMessage('p269-logical-reminted'), isNull);
      expect(
        (await logicalMedia.getAttachmentsForMessage(
          logicalCanonicalId,
          owner: MediaOwnerLane.group,
        )).single.messageId,
        logicalCanonicalId,
      );

      // Exit 4: strict media-identity discovery can race local deletion. The
      // batch result authorizes the canonical parent, then the exact missing
      // attachment is restored and reported rather than the reminted row.
      final (retryGroups, retryMessages) = await createFixture();
      final retryMedia = _LogicalMediaRetryRaceRepository();
      final retryWire = _gird003Media(
        id: 'p269-media-retry-blob',
        createdAt: sentAt.toIso8601String(),
      );
      final seededRetry = await handleIncomingGroupMessage(
        groupRepo: retryGroups,
        msgRepo: retryMessages,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'P269 media retry duplicate',
        timestamp: sentAt.toIso8601String(),
        transportPeerId: 'peer-sender',
        messageId: 'p269-media-retry-canonical',
        media: retryWire,
        mediaAttachmentRepo: retryMedia,
        nowUtc: () => sentAt.add(const Duration(minutes: 1)),
      );
      expect(seededRetry, isNotNull);
      retryMedia.guardedSaveCalls = 0;
      retryMedia.removeCanonicalMediaAfterNextBatchLookup = true;
      final retryOutcome = await handleDetailed(
        groups: retryGroups,
        messages: retryMessages,
        text: 'P269 media retry duplicate',
        messageId: 'p269-media-retry-reminted',
        media: retryWire,
        mediaRepository: retryMedia,
      );
      expect(retryOutcome, isA<IncomingGroupMessageDuplicateEnriched>());
      final retryEnriched =
          retryOutcome as IncomingGroupMessageDuplicateEnriched;
      expect(retryEnriched.canonicalMessage.id, 'p269-media-retry-canonical');
      expect(retryEnriched.persistedAttachmentIds, {'p269-media-retry-blob'});
      expect(retryMedia.guardedSaveCalls, 1);
      expect(
        (await retryMedia.getAttachmentsForMessage(
          'p269-media-retry-canonical',
          owner: MediaOwnerLane.group,
        )).single.messageId,
        'p269-media-retry-canonical',
      );

      // A guarded refusal made no durable change and therefore cannot be
      // presented to the listener as enrichment.
      final (guardGroups, guardMessages) = await createFixture();
      const guardCanonicalId = 'p269-guard-canonical';
      await guardMessages.saveMessage(
        canonicalMessage(guardCanonicalId, text: 'P269 guard duplicate'),
      );
      guardMessages.failSaveMessageIds.add(guardCanonicalId);
      final refusedMedia = _GuardedRecordingMediaAttachmentRepository()
        ..allowGuardedSave = false;
      final guardOutcome = await handleDetailed(
        groups: guardGroups,
        messages: guardMessages,
        text: 'P269 guard duplicate',
        messageId: guardCanonicalId,
        quotedMessageId: 'p269-guard-refused-quote',
        media: _gird003Media(
          id: 'p269-guard-refused',
          createdAt: sentAt.toIso8601String(),
        ),
        mediaRepository: refusedMedia,
      );
      expect(guardOutcome, isA<IncomingGroupMessageIgnored>());
      expect(refusedMedia.guardedSaveCalls, 1);
      expect(refusedMedia.count, 0);
      expect(guardMessages.count, 1);
      expect(
        (await guardMessages.getMessage(guardCanonicalId))?.quotedMessageId,
        isNull,
        reason: 'a refused attachment guard cannot leave a quote-only write',
      );

      // Exit 5: id-less content matching is deliberately too weak to
      // authorize media attachment writes, even when a heuristic row exists.
      final (contentGroups, contentMessages) = await createFixture();
      final contentParent = await handleIncomingGroupMessage(
        groupRepo: contentGroups,
        msgRepo: contentMessages,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'P269 content duplicate',
        timestamp: sentAt.toIso8601String(),
        nowUtc: () => sentAt.add(const Duration(minutes: 1)),
      );
      expect(contentParent, isNotNull);
      final contentMedia = _GuardedRecordingMediaAttachmentRepository();
      final contentOutcome = await handleDetailed(
        groups: contentGroups,
        messages: contentMessages,
        text: 'P269 content duplicate',
        media: _gird003Media(
          id: 'p269-content-must-not-save',
          createdAt: sentAt.toIso8601String(),
        ),
        mediaRepository: contentMedia,
      );
      expect(contentOutcome, isA<IncomingGroupMessageIgnored>());
      expect(contentMedia.guardedSaveCalls, 0);
      expect(contentMedia.count, 0);
      expect(contentMessages.count, 1);
    },
  );

  test(
    'replayed removed-sender message after cutoff does not overwrite the accepted pre-cutoff row',
    () async {
      const sharedMessageId = 'msg-removed-replay-cutoff';
      final removedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      final originalTimestamp = removedAt.subtract(
        const Duration(milliseconds: 1),
      );

      await saveRemovalCutoff(
        removedPeerId: 'peer-removed',
        removedAt: removedAt,
      );

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 0,
        text: 'Sent before cutoff',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-removed',
        senderUsername: 'Removed',
        keyEpoch: 0,
        text: 'Sent before cutoff',
        timestamp: removedAt.add(const Duration(seconds: 1)).toIso8601String(),
        messageId: sharedMessageId,
      );

      expect(replay, isNull);

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.timestamp, originalTimestamp);
      expect(
        (await msgRepo.getMessagesPage(
          'group-1',
        )).where((message) => message.id == sharedMessageId),
        hasLength(1),
      );
    },
  );

  test(
    'replayed message after dissolve cutoff does not overwrite the accepted pre-dissolve row',
    () async {
      const sharedMessageId = 'msg-dissolve-replay-cutoff';
      final dissolvedAt = DateTime.utc(2026, 4, 5, 12, 0, 0);
      final originalTimestamp = dissolvedAt.subtract(
        const Duration(seconds: 1),
      );

      await groupRepo.updateGroup(
        testGroup.copyWith(
          isDissolved: true,
          dissolvedAt: dissolvedAt,
          dissolvedBy: 'peer-admin',
        ),
      );

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Sent before dissolve',
        timestamp: originalTimestamp.toIso8601String(),
        messageId: sharedMessageId,
      );
      expect(first, isNotNull);

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Sent before dissolve',
        timestamp: dissolvedAt
            .add(const Duration(seconds: 1))
            .toIso8601String(),
        messageId: sharedMessageId,
      );

      expect(replay, isNull);

      final saved = await msgRepo.getMessage(sharedMessageId);
      expect(saved, isNotNull);
      expect(saved!.timestamp, originalTimestamp);
      expect(
        (await msgRepo.getMessagesPage(
          'group-1',
        )).where((message) => message.id == sharedMessageId),
        hasLength(1),
      );
    },
  );

  test(
    'SV-006 replay dedupes same epoch and rejects removed-interval after readd',
    () async {
      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      const duplicateMessageId = 'sv006-same-epoch-replay';
      const removedReplayMessageId = 'sv006-removed-window-replay';
      const currentMessageId = 'sv006-current-after-readd';
      const selfPeerId = 'peer-recipient';
      final originalAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 20),
      );
      final removedAt = originalAt.add(const Duration(minutes: 3));
      final rejoinedAt = removedAt.add(const Duration(minutes: 2));

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: selfPeerId,
          username: 'Recipient',
          role: MemberRole.writer,
          joinedAt: originalAt.subtract(const Duration(minutes: 1)),
        ),
      );

      final first = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: 'SV-006 original same epoch',
        timestamp: originalAt.toIso8601String(),
        messageId: duplicateMessageId,
        selfPeerId: selfPeerId,
      );
      expect(first, isNotNull);

      final replay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 1,
        text: 'SV-006 conflicting replay body',
        timestamp: originalAt.add(const Duration(minutes: 1)).toIso8601String(),
        messageId: duplicateMessageId,
        selfPeerId: selfPeerId,
      );
      expect(replay, isNull);

      final savedDuplicate = await msgRepo.getMessage(duplicateMessageId);
      expect(savedDuplicate, isNotNull);
      expect(savedDuplicate!.text, 'SV-006 original same epoch');
      expect(savedDuplicate.timestamp, originalAt);
      expect(
        (await msgRepo.getMessagesPage(
          'group-1',
        )).where((message) => message.id == duplicateMessageId),
        hasLength(1),
      );

      await saveRemovalCutoff(removedPeerId: selfPeerId, removedAt: removedAt);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: selfPeerId,
          username: 'Recipient',
          role: MemberRole.writer,
          joinedAt: rejoinedAt,
        ),
      );

      final removedReplay = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 2,
        text: 'SV-006 removed-window replay',
        timestamp: removedAt.add(const Duration(seconds: 30)).toIso8601String(),
        messageId: removedReplayMessageId,
        selfPeerId: selfPeerId,
      );
      expect(removedReplay, isNull);
      expect(await msgRepo.getMessage(removedReplayMessageId), isNull);
      expect(
        flowEvents.where(
          (event) =>
              event['event'] ==
                  'GROUP_HANDLE_INCOMING_MSG_LOCAL_REMOVED_INTERVAL_REPLAY_REJECTED' ||
              event['event'] ==
                  'GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN',
        ),
        isNotEmpty,
      );

      final current = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 3,
        text: 'SV-006 current after readd',
        timestamp: rejoinedAt.add(const Duration(seconds: 1)).toIso8601String(),
        messageId: currentMessageId,
        selfPeerId: selfPeerId,
      );
      expect(current, isNotNull);
      expect(
        (await msgRepo.getMessage(currentMessageId))!.text,
        'SV-006 current after readd',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Media attachment tests
  // ---------------------------------------------------------------------------
  group('media attachments', () {
    late InMemoryMediaAttachmentRepository mediaRepo;

    setUp(() {
      mediaRepo = InMemoryMediaAttachmentRepository();
    });

    test('saves media attachments when media list provided', () async {
      final media = [
        {
          'id': 'blob-1',
          'mime': 'image/jpeg',
          'size': 12345,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Check this out',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNotNull);
      expect(mediaRepo.count, 1);

      // Verify attachment has the message's ID
      final attachments = await mediaRepo.getAttachmentsForMessage(
        result!.id,
        owner: MediaOwnerLane.group,
      );
      expect(attachments.length, 1);
      expect(attachments.first.mime, 'image/jpeg');
    });

    test('creates MediaAttachment with downloadStatus pending', () async {
      final media = [
        {
          'id': 'blob-2',
          'mime': 'audio/mp4',
          'size': 5000,
          'mediaType': 'audio',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Voice note',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNotNull);
      final pending = await mediaRepo.getPendingDownloads();
      expect(pending.length, 1);
      expect(pending.first.downloadStatus, 'pending');
    });

    // 228: the group incoming path must persist media under the GROUP lane —
    // every saveAttachment call carries MediaOwnerLane.group, never direct.
    // Announcement-backed groups are still the GROUP lane: there is no third
    // lane, so both the chat-type and announcement-type fixtures must record
    // MediaOwnerLane.group.
    test('incoming media save passes group owner', () async {
      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-announce-1',
          name: 'Announcement Group',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-1',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-announce-1',
          peerId: 'peer-sender',
          username: 'Sender',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final recordedLanes = <MediaOwnerLane?>[];
      mediaRepo.onSaveAttachment = (att) => recordedLanes.add(att.ownerLane);

      List<Map<String, dynamic>> mediaFor(String blobId) => [
        {
          'id': blobId,
          'mime': 'image/jpeg',
          'size': 12345,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final chatResult = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Chat-group media',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        media: mediaFor('blob-owner-chat'),
        mediaAttachmentRepo: mediaRepo,
      );
      final announcementResult = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-announce-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Announcement-group media',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        media: mediaFor('blob-owner-announce'),
        mediaAttachmentRepo: mediaRepo,
      );

      expect(chatResult, isNotNull);
      expect(announcementResult, isNotNull);
      expect(recordedLanes, hasLength(2));
      expect(
        recordedLanes.toSet(),
        {MediaOwnerLane.group},
        reason:
            'every group incoming media save must pass the group lane — '
            'announcements included, never direct or a third lane',
      );
      // Lane-scoped read-back: the direct lane must never see these rows.
      expect(
        await mediaRepo.getAttachmentsForMessage(
          chatResult!.id,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      expect(
        await mediaRepo.getAttachmentsForMessage(
          announcementResult!.id,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      expect(
        (await mediaRepo.getAttachmentsForMessage(
          announcementResult.id,
          owner: MediaOwnerLane.group,
        )).single.id,
        'blob-owner-announce',
      );
    });

    test(
      'GIRD-003 distinct-id group image retry with same media identity keeps one recipient row',
      () async {
        const originalMessageId = 'gird003-original';
        const remintedMessageId = 'gird003-reminted';
        final sentAt = DateTime.utc(2026, 5, 31, 13, 15);
        final media = _gird003Media(
          id: 'blob-gird003-shared',
          createdAt: sentAt.toIso8601String(),
        );

        final first = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 3,
          text: '',
          timestamp: sentAt.toIso8601String(),
          messageId: originalMessageId,
          quotedMessageId: 'gird003-parent',
          media: media,
          mediaAttachmentRepo: mediaRepo,
        );
        final duplicate = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 3,
          text: '',
          timestamp: sentAt.toIso8601String(),
          messageId: remintedMessageId,
          quotedMessageId: 'gird003-parent',
          media: media,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(first, isNotNull);
        expect(duplicate, isNull);
        expect(msgRepo.count, 1);
        expect(await msgRepo.getMessage(originalMessageId), isNotNull);
        expect(await msgRepo.getMessage(remintedMessageId), isNull);

        final originalAttachments = await mediaRepo.getAttachmentsForMessage(
          originalMessageId,
          owner: MediaOwnerLane.group,
        );
        final duplicateAttachments = await mediaRepo.getAttachmentsForMessage(
          remintedMessageId,
          owner: MediaOwnerLane.group,
        );
        expect(originalAttachments, hasLength(1));
        expect(originalAttachments.single.id, 'blob-gird003-shared');
        expect(originalAttachments.single.messageId, originalMessageId);
        expect(duplicateAttachments, isEmpty);
        expect(mediaRepo.count, 1);
      },
    );

    test(
      'GIRD-003 intentional separate image sends with distinct media identity both persist',
      () async {
        const firstMessageId = 'gird003-intentional-first';
        const secondMessageId = 'gird003-intentional-second';
        final firstSentAt = DateTime.utc(2026, 5, 31, 13, 20);
        final secondSentAt = firstSentAt.add(const Duration(seconds: 30));

        final first = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 3,
          text: 'same image again',
          timestamp: firstSentAt.toIso8601String(),
          messageId: firstMessageId,
          media: _gird003Media(
            id: 'blob-gird003-intentional-a',
            createdAt: firstSentAt.toIso8601String(),
          ),
          mediaAttachmentRepo: mediaRepo,
        );
        final second = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 3,
          text: 'same image again',
          timestamp: secondSentAt.toIso8601String(),
          messageId: secondMessageId,
          media: _gird003Media(
            id: 'blob-gird003-intentional-b',
            createdAt: secondSentAt.toIso8601String(),
          ),
          mediaAttachmentRepo: mediaRepo,
        );

        expect(first, isNotNull);
        expect(second, isNotNull);
        expect(msgRepo.count, 2);

        final firstAttachments = await mediaRepo.getAttachmentsForMessage(
          firstMessageId,
          owner: MediaOwnerLane.group,
        );
        final secondAttachments = await mediaRepo.getAttachmentsForMessage(
          secondMessageId,
          owner: MediaOwnerLane.group,
        );
        expect(firstAttachments, hasLength(1));
        expect(firstAttachments.single.id, 'blob-gird003-intentional-a');
        expect(secondAttachments, hasLength(1));
        expect(secondAttachments.single.id, 'blob-gird003-intentional-b');
        expect(mediaRepo.count, 2);
      },
    );

    test(
      'rejects invalid live media before saving message or attachment',
      () async {
        final media = [
          {
            'id': 'blob-dangerous',
            'mime': 'text/html',
            'size': 5000,
            'mediaType': 'file',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'downloadStatus': 'pending',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ];

        final result = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'Dangerous media',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          messageId: 'msg-dangerous-media',
          media: media,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, isNull);
        expect(await msgRepo.getMessage('msg-dangerous-media'), isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
      },
    );

    test('rejects incoming mediaType mismatches before storage', () async {
      final media = [
        {
          'id': 'blob-mismatch',
          'mime': 'image/jpeg',
          'size': 5000,
          'mediaType': 'video',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Mismatch media',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-mismatch-media',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-mismatch-media'), isNull);
      expect(mediaRepo.count, 0);
    });

    test(
      'rejects oversized live media before saving message or attachment',
      () async {
        final media = [
          {
            'id': 'blob-oversized-live',
            'mime': 'image/jpeg',
            'size': kGroupMediaPerAttachmentLimitBytes + 1,
            'mediaType': 'image',
            'contentHash': _validContentHash,
            'encryptionKeyBase64': 'key-fixture',
            'encryptionNonce': 'nonce-fixture',
            'encryptionScheme': 'blob_aes_256_gcm_v1',
            'downloadStatus': 'pending',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        ];

        final result = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'Oversized media',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          messageId: 'msg-oversized-live',
          media: media,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, isNull);
        expect(await msgRepo.getMessage('msg-oversized-live'), isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
      },
    );

    test('rejects total-over-limit live media before storage', () async {
      final media = [
        {
          'id': 'blob-total-1',
          'mime': 'image/jpeg',
          'size': kGroupMediaTotalMessageLimitBytes,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'id': 'blob-total-2',
          'mime': 'image/png',
          'size': 1,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Too much media',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-total-oversized-live',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-total-oversized-live'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects malformed media descriptors before storage', () async {
      final media = [
        {
          'id': 'blob-malformed',
          'mime': 42,
          'size': 5000,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Malformed media',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-malformed-media',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-malformed-media'), isNull);
      expect(mediaRepo.count, 0);
    });

    test(
      'GPL-04C explicit policy plus corrupt descriptor persists unsupported without attachment',
      () async {
        final result = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: '',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          messageId: 'msg-corrupt-private-media',
          privateMediaPolicyFields: const {
            'mediaPolicyVersion': 1,
            'mediaLifecycle': 'viewOnce',
            'mediaDurationSeconds': null,
            'mediaProtected': true,
          },
          media: [
            {
              'id': 'blob-corrupt-private-media',
              'mime': 42,
              'size': 5000,
              'mediaType': 'image',
              'contentHash': _validContentHash,
              'encryptionKeyBase64': 'key-fixture',
              'encryptionNonce': 'nonce-fixture',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, isNotNull);
        expect(result!.id, 'msg-corrupt-private-media');
        expect(
          result.privateMediaPolicy,
          const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1),
        );
        expect(
          (await msgRepo.getMessage(
            'msg-corrupt-private-media',
          ))!.privateMediaPolicy,
          const GroupPrivateMediaPolicy.unsupported(sourceVersion: 1),
        );
        expect(mediaRepo.count, 0);
      },
    );

    test('rejects malformed media size before storage', () async {
      final media = [
        {
          'id': 'blob-bad-size',
          'mime': 'image/png',
          'size': '5000',
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Malformed media size',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-malformed-media-size',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-malformed-media-size'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects missing content hash before storage', () async {
      final media = [
        {
          'id': 'blob-missing-hash',
          'mime': 'image/png',
          'size': 5000,
          'mediaType': 'image',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Missing hash',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-missing-content-hash',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-missing-content-hash'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects malformed content hash before storage', () async {
      final media = [
        {
          'id': 'blob-bad-hash',
          'mime': 'image/png',
          'size': 5000,
          'mediaType': 'image',
          'contentHash': 'not-a-sha256',
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Bad hash',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-bad-content-hash',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-bad-content-hash'), isNull);
      expect(mediaRepo.count, 0);
    });

    test('rejects missing media encryption metadata before storage', () async {
      final media = [
        {
          'id': 'blob-missing-encryption',
          'mime': 'image/png',
          'size': 5000,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'downloadStatus': 'pending',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      ];

      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Missing encryption',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        messageId: 'msg-missing-media-encryption',
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNull);
      expect(await msgRepo.getMessage('msg-missing-media-encryption'), isNull);
      expect(mediaRepo.count, 0);
    });

    test(
      'duplicate replay with oversized media does not enrich existing sparse message',
      () async {
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-duplicate-oversized',
            groupId: 'group-1',
            senderPeerId: 'peer-sender',
            senderUsername: 'Sender',
            text: 'Existing message',
            timestamp: DateTime.now().toUtc(),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final result = await handleIncomingGroupMessage(
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'Existing message',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          messageId: 'msg-duplicate-oversized',
          media: [
            {
              'id': 'blob-duplicate-oversized',
              'mime': 'image/jpeg',
              'size': kGroupMediaPerAttachmentLimitBytes + 1,
              'mediaType': 'image',
              'contentHash': _validContentHash,
              'encryptionKeyBase64': 'key-fixture',
              'encryptionNonce': 'nonce-fixture',
              'encryptionScheme': 'blob_aes_256_gcm_v1',
              'downloadStatus': 'pending',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            },
          ],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, isNull);
        expect(mediaRepo.count, 0);
      },
    );

    test('handles message without media (backward compat)', () async {
      final result = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Plain text',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, isNotNull);
      expect(mediaRepo.count, 0);
    });

    test('ignores duplicate messages — does not re-save media', () async {
      final ts = DateTime.now().toUtc().toIso8601String();
      final media = [
        {
          'id': 'blob-dup',
          'mime': 'image/png',
          'size': 1000,
          'mediaType': 'image',
          'contentHash': _validContentHash,
          'encryptionKeyBase64': 'key-fixture',
          'encryptionNonce': 'nonce-fixture',
          'encryptionScheme': 'blob_aes_256_gcm_v1',
          'downloadStatus': 'pending',
          'createdAt': ts,
        },
      ];

      await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Duplicate test',
        timestamp: ts,
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      // Second call with same content — should be duplicate
      final result2 = await handleIncomingGroupMessage(
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        senderId: 'peer-sender',
        senderUsername: 'Sender',
        keyEpoch: 0,
        text: 'Duplicate test',
        timestamp: ts,
        media: media,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result2, isNull); // duplicate
      expect(mediaRepo.count, 1); // only saved once
    });
  });

  // ---------------------------------------------------------------------
  // 235 (TC-235-09): the final attachment write verifies the exact
  // (group_id, message_id) parent and the deletion journal INSIDE its own
  // transaction — production DB helpers, not fakes.
  // ---------------------------------------------------------------------
  group('235 guarded incoming media persistence', () {
    late Database db;
    late FakeSecureKeyStore keyStore;
    late GroupMessageRepositoryImpl realMsgRepo;
    late MediaAttachmentRepositoryImpl realMediaRepo;
    late InMemoryGroupRepository liveGroupRepo;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      await runProductionOnCreate(db, currentIdentityDatabaseVersion);
      keyStore = FakeSecureKeyStore();
      realMsgRepo = GroupMessageRepositoryImpl(
        dbInsertGroupMessage: (row) => dbInsertGroupMessage(db, row),
        dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) =>
            dbLoadGroupMessagesPage(db, groupId, limit: limit, offset: offset),
        dbLoadGroupMessage: (id) => dbLoadGroupMessage(db, id),
        dbLoadLatestGroupMessage: (groupId) =>
            dbLoadLatestGroupMessage(db, groupId),
        dbUpdateGroupMessageStatus: (id, status) =>
            dbUpdateGroupMessageStatus(db, id, status),
        dbCountGroupMessages: (groupId) => dbCountGroupMessages(db, groupId),
        dbCountUnreadGroupMessages: (groupId) =>
            dbCountUnreadGroupMessages(db, groupId),
        dbCountTotalUnreadGroupMessages: () =>
            dbCountTotalUnreadGroupMessages(db),
        dbMarkGroupMessagesAsRead: (groupId) =>
            dbMarkGroupMessagesAsRead(db, groupId),
        dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(db, id),
        dbExistsGroupMessageByContent:
            (groupId, senderPeerId, text, timestamp) =>
                dbExistsGroupMessageByContent(
                  db,
                  groupId,
                  senderPeerId,
                  text,
                  timestamp,
                ),
        dbDeleteGroupMessagesForGroup: (groupId) =>
            dbDeleteGroupMessagesForGroup(db, groupId),
        dbLoadGroupThreadSummaries: (groupIds) =>
            dbLoadGroupThreadSummaries(db, groupIds),
        dbLoadGroupMessageLocalDeletionFn: (messageId) =>
            dbLoadGroupMessageLocalDeletion(db, messageId),
      );
      realMediaRepo = MediaAttachmentRepositoryImpl(
        dbSaveMediaAttachmentPreservingLocalState: (row) =>
            dbSaveMediaAttachmentPreservingLocalState(db, row),
        dbLoadMediaForMessage: (messageId, ownerLane) =>
            dbLoadMediaForMessage(db, messageId, ownerLane: ownerLane),
        dbLoadMediaById: (id) => dbLoadMediaById(db, id),
        dbLoadMediaForMessages: (messageIds, ownerLane) =>
            dbLoadMediaForMessages(db, messageIds, ownerLane: ownerLane),
        dbUpdateMediaLocalPath: (id, localPath, downloadStatus) =>
            dbUpdateMediaLocalPath(db, id, localPath, downloadStatus),
        dbUpdateMediaDownloadStatus: (id, downloadStatus) =>
            dbUpdateMediaDownloadStatus(db, id, downloadStatus),
        dbDeleteMediaForMessage: (messageId, ownerLane) =>
            dbDeleteMediaForMessage(db, messageId, ownerLane: ownerLane),
        dbDeleteMediaForContact: (contactPeerId) =>
            dbDeleteMediaForContact(db, contactPeerId),
        dbMarkUploadPendingAttachmentsFailedForMessage:
            (messageId, ownerLane) =>
                dbMarkUploadPendingAttachmentsFailedForMessage(
                  db,
                  messageId,
                  ownerLane: ownerLane,
                ),
        dbLoadPendingMediaDownloads: () => dbLoadPendingMediaDownloads(db),
        dbLoadUploadPendingAttachments:
            ({int limit = 25, required String ownerLane}) =>
                dbLoadUploadPendingAttachments(
                  db,
                  limit: limit,
                  ownerLane: ownerLane,
                ),
        dbSetMediaBookmarked: (id, bookmarked) =>
            dbSetMediaBookmarked(db, id, bookmarked: bookmarked),
        dbUpdateMediaPlaybackPosition: (id, positionMs) =>
            dbUpdateMediaPlaybackPosition(db, id, positionMs),
        dbLoadMediaLibraryPage:
            ({
              required String scopeKind,
              required String scopeId,
              required List<String> mediaTypes,
              required bool bookmarkedOnly,
              required bool incomingOnly,
              required int limit,
              String? afterTimestamp,
              String? afterMessageId,
              String? afterAttachmentId,
            }) => dbLoadMediaLibraryPage(
              db,
              scopeKind: scopeKind,
              scopeId: scopeId,
              mediaTypes: mediaTypes,
              bookmarkedOnly: bookmarkedOnly,
              incomingOnly: incomingOnly,
              limit: limit,
              afterTimestamp: afterTimestamp,
              afterMessageId: afterMessageId,
              afterAttachmentId: afterAttachmentId,
            ),
        dbSaveGroupMediaAttachmentGuarded: (row, {required String groupId}) =>
            dbSaveGroupMediaAttachmentGuarded(db, row, groupId: groupId),
        secureKeyStore: keyStore,
        lifecycleLock: MediaAttachmentLifecycleLock(),
      );
      liveGroupRepo = InMemoryGroupRepository();
      for (final groupId in ['group-a', 'group-b']) {
        final group = GroupModel(
          id: groupId,
          name: 'Group $groupId',
          type: GroupType.chat,
          topicName: 'topic-$groupId',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        );
        await liveGroupRepo.saveGroup(group);
        await dbInsertGroup(db, group.toMap());
        await liveGroupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'peer-sender',
            username: 'Sender',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 7, 1),
          ),
        );
      }
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'GMA-09 transactional parent and journal guard closes save delete race',
      () async {
        // Group A receives msg-shared with media, then deletes it for me —
        // the tombstone (message_id-keyed) now silently rejects ANY same-ID
        // parent insert.
        await handleIncomingGroupMessage(
          groupRepo: liveGroupRepo,
          msgRepo: realMsgRepo,
          mediaAttachmentRepo: realMediaRepo,
          groupId: 'group-a',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'group A original',
          timestamp: '2026-07-10T10:00:00.000Z',
          messageId: 'msg-shared',
          media: _gird003Media(
            id: 'att-group-a',
            createdAt: '2026-07-10T10:00:00.000Z',
          ),
        );
        expect(
          await realMediaRepo.getAttachmentsForMessage(
            'msg-shared',
            owner: MediaOwnerLane.group,
          ),
          hasLength(1),
        );
        final prepared = await dbPrepareGroupMediaDeleteForMe(
          db,
          groupId: 'group-a',
          messageId: 'msg-shared',
          operationId: 'op-a',
        );
        expect(prepared.outcome, GroupMediaDeletePrepareOutcome.prepared);

        // Group B now receives the SAME message id. The parent insert is
        // silently rejected by group A's tombstone — so the guarded final
        // write must refuse every attachment: zero rows, zero secure keys.
        await handleIncomingGroupMessage(
          groupRepo: liveGroupRepo,
          msgRepo: realMsgRepo,
          mediaAttachmentRepo: realMediaRepo,
          groupId: 'group-b',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'group B same-ID message',
          timestamp: '2026-07-10T10:05:00.000Z',
          messageId: 'msg-shared',
          media: _gird003Media(
            id: 'att-group-b',
            createdAt: '2026-07-10T10:05:00.000Z',
          ),
        );
        expect(
          (await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: ['msg-shared'],
          )),
          isEmpty,
          reason: 'the tombstone rejected the group-B parent',
        );
        final rowsAfterB = await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['att-group-b'],
        );
        expect(
          rowsAfterB,
          isEmpty,
          reason: 'no unjournaled attachment row for a rejected parent',
        );
        expect(
          await keyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('att-group-b'),
          ),
          isFalse,
          reason: 'the refused save compensates its own key write',
        );

        // An active journal reserves its attachment ID against re-save even
        // under a LIVE parent: incoming media whose blob id is journaled must
        // not re-acquire a row or key.
        await db.insert('group_media_deletion_journal', {
          'attachment_id': 'att-reserved',
          'operation_id': 'op-r',
          'message_id': 'msg-old-deleted',
          'group_id': 'group-b',
          'operation_intent': 'delete_for_me',
          'normalized_mime': 'image/png',
          'canonical_relative_path': null,
          'created_at': '2026-07-10T09:00:00.000Z',
        });
        await handleIncomingGroupMessage(
          groupRepo: liveGroupRepo,
          msgRepo: realMsgRepo,
          mediaAttachmentRepo: realMediaRepo,
          groupId: 'group-b',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'live parent, reserved attachment',
          timestamp: '2026-07-10T10:10:00.000Z',
          messageId: 'msg-live',
          media: _gird003Media(
            id: 'att-reserved',
            createdAt: '2026-07-10T10:10:00.000Z',
          ),
        );
        expect(
          (await db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: ['msg-live'],
          )),
          hasLength(1),
          reason: 'the live parent itself is saved',
        );
        expect(
          (await db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: ['att-reserved'],
          )),
          isEmpty,
          reason: 'a journal reservation blocks the attachment re-save',
        );
        expect(
          await keyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('att-reserved'),
          ),
          isFalse,
        );

        // A normal incoming message under a live parent still persists media
        // through the guarded path (the guard is not a blanket refusal).
        await handleIncomingGroupMessage(
          groupRepo: liveGroupRepo,
          msgRepo: realMsgRepo,
          mediaAttachmentRepo: realMediaRepo,
          groupId: 'group-b',
          senderId: 'peer-sender',
          senderUsername: 'Sender',
          keyEpoch: 0,
          text: 'plain delivery',
          timestamp: '2026-07-10T10:15:00.000Z',
          messageId: 'msg-plain',
          media: _gird003Media(
            id: 'att-plain',
            createdAt: '2026-07-10T10:15:00.000Z',
          ),
        );
        final plainRows = await db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: ['att-plain'],
        );
        expect(plainRows, hasLength(1));
        expect(plainRows.single['owner_lane'], 'group');
        expect(
          await keyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('att-plain'),
          ),
          isTrue,
        );
      },
    );
  });
}
