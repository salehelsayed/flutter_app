import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

IdentityModel _makeIdentity({String peerId = 'peer-1'}) {
  return IdentityModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    privateKey: 'sk-$peerId',
    mnemonic12:
        'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
    username: 'Alice',
    createdAt: '2026-01-15T12:00:00.000Z',
    updatedAt: '2026-01-15T12:00:00.000Z',
  );
}

GroupModel _makeGroup({
  String id = 'group-1',
  GroupType type = GroupType.chat,
  GroupRole myRole = GroupRole.member,
}) {
  return GroupModel(
    id: id,
    name: 'Test Group',
    type: type,
    topicName: 'topic-1',
    createdAt: DateTime.utc(2026, 1, 15, 12),
    createdBy: 'peer-admin',
    myRole: myRole,
  );
}

GroupMessage _makeFailedGroupMessage({
  required String id,
  required String text,
  required String timestampIso,
  String? inboxRetryPayload,
  String? quotedMessageId,
  List<Map<String, Object?>> media = const [],
}) {
  final messageJson = {
    'groupId': 'group-1',
    'senderId': 'peer-1',
    'senderUsername': 'Alice',
    'keyEpoch': 0,
    'text': text,
    'timestamp': timestampIso,
    'messageId': id,
    ...quotedMessageId == null
        ? const <String, Object?>{}
        : {'quotedMessageId': quotedMessageId},
    if (media.isNotEmpty) 'media': media,
  };
  return GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: 'peer-1',
    senderUsername: 'Alice',
    text: text,
    timestamp: DateTime.parse(timestampIso),
    quotedMessageId: quotedMessageId,
    keyGeneration: 0,
    status: 'failed',
    isIncoming: false,
    createdAt: DateTime.parse(timestampIso),
    wireEnvelope: jsonEncode({
      'groupId': 'group-1',
      'text': text,
      'senderPeerId': 'peer-1',
      'senderUsername': 'Alice',
      'messageId': id,
      ...quotedMessageId == null
          ? const <String, Object?>{}
          : {'quotedMessageId': quotedMessageId},
      if (media.isNotEmpty) 'media': media,
    }),
    inboxStored: false,
    inboxRetryPayload:
        inboxRetryPayload ??
        jsonEncode({
          'groupId': 'group-1',
          'message': jsonEncode(messageJson),
          'recipientPeerIds': ['peer-2'],
          'pushTitle': 'Test Group',
          'pushBody': 'Alice: $text',
        }),
  );
}

List<Map<String, dynamic>> _publishedGroupPayloads(FakeBridge bridge) {
  return bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .where((message) => message['cmd'] == 'group:publish')
      .map((message) => (message['payload'] as Map).cast<String, dynamic>())
      .toList();
}

MediaAttachment _makeAttachment({
  required String id,
  required String messageId,
  required String downloadStatus,
  String mime = 'image/jpeg',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 4096,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: 'media/group-1/$id.jpg',
    downloadStatus: downloadStatus,
    contentHash: _validContentHash,
    encryptionKeyBase64: 'key-$id',
    encryptionNonce: 'nonce-$id',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    createdAt: '2026-01-15T12:00:00.000Z',
  );
}

class _FailFirstPublishBridge extends FakeBridge {
  var _publishCalls = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      _publishCalls++;
      if (_publishCalls == 1) {
        throw Exception('Simulated publish failure');
      }
    }

    return super.send(message);
  }
}

void main() {
  group('retryFailedGroupMessages', () {
    late FakeIdentityRepository identityRepo;
    late InMemoryGroupMessageRepository msgRepo;
    late InMemoryGroupRepository groupRepo;
    late InMemoryMediaAttachmentRepository mediaRepo;
    late FakeBridge bridge;

    setUp(() async {
      identityRepo = FakeIdentityRepository();
      msgRepo = InMemoryGroupMessageRepository();
      groupRepo = InMemoryGroupRepository();
      mediaRepo = InMemoryMediaAttachmentRepository();
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': true, 'messageId': 'msg-1', 'topicPeers': 1},
        },
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 0,
          encryptedKey: 'encrypted-key-gen-0',
          createdAt: DateTime.parse('2026-01-15T12:00:00.000Z'),
        ),
      );
    });

    test('returns 0 when identity is null', () async {
      final count = await retryFailedGroupMessages(
        groupMsgRepo: msgRepo,
        groupRepo: groupRepo,
        identityRepo: identityRepo,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(count, 0);
      expect(bridge.commandLog, isEmpty);
    });

    test(
      'emits RETRY_FAILED_GROUP_MESSAGES_TIMING with total and skipped counts',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-retry-1',
            text: 'Retry me',
            timestampIso: '2026-01-15T12:00:00.000Z',
          ),
        );

        final events = await captureFlowEvents(() async {
          await retryFailedGroupMessages(
            groupMsgRepo: msgRepo,
            groupRepo: groupRepo,
            identityRepo: identityRepo,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
          );
        });

        final start = events.firstWhere(
          (event) => event['event'] == 'RETRY_FAILED_GROUP_MESSAGES_START',
        );
        expect(start['details'], isEmpty);

        final found = events.firstWhere(
          (event) => event['event'] == 'RETRY_FAILED_GROUP_MESSAGES_FOUND',
        );
        expect(found['details']['count'], 1);

        final messageSuccess = events.firstWhere(
          (event) =>
              event['event'] == 'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_SUCCESS',
        );
        expect(messageSuccess['details']['messageId'], 'msg-retr');
        expect(messageSuccess['details']['result'], 'success');

        final complete = events.firstWhere(
          (event) => event['event'] == 'RETRY_FAILED_GROUP_MESSAGES_COMPLETE',
        );
        expect(complete['details']['total'], 1);
        expect(complete['details']['succeeded'], 1);
        expect(complete['details']['skippedUnsupported'], 0);

        final timing = events.lastWhere(
          (event) => event['event'] == 'RETRY_FAILED_GROUP_MESSAGES_TIMING',
        );
        expect(timing['details']['outcome'], 'complete');
        expect(timing['details']['total'], 1);
        expect(timing['details']['succeeded'], 1);
        expect(timing['details']['skippedUnsupported'], 0);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test(
      'retries a text-only failed row in place using the original ids',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-retry-1',
            text: 'Retry me',
            timestampIso: '2026-01-15T12:00:00.000Z',
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 1);
        final saved = await msgRepo.getMessage('msg-retry-1');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.timestamp, DateTime.parse('2026-01-15T12:00:00.000Z'));
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
      },
    );

    test(
      'does not replay a failed text row after sender was removed locally',
      () async {
        identityRepo.seed(_makeIdentity(peerId: 'peer-1'));
        await groupRepo.saveGroup(_makeGroup());
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            joinedAt: DateTime.utc(2026, 1, 15, 12),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-2',
            joinedAt: DateTime.utc(2026, 1, 15, 12, 1),
          ),
        );
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-stale-retry',
            text: 'Retry after removal',
            timestampIso: '2026-01-15T12:00:00.000Z',
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 0);
        final saved = await msgRepo.getMessage('msg-stale-retry');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(bridge.commandLog, isEmpty);
      },
    );

    test(
      'retries a zero-peer plus inbox-fail row through the failed-message retry owner',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-1',
            username: 'Alice',
            role: MemberRole.writer,
            publicKey: 'pk-peer-1',
            joinedAt: DateTime.utc(2026, 1, 15, 12),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-2',
            joinedAt: DateTime.utc(2026, 1, 15, 12, 1),
          ),
        );
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-zero-owner',
          'topicPeers': 0,
        };

        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-zero-owner',
            text: 'Retry zero-peer owner',
            timestampIso: '2026-01-15T12:00:00.000Z',
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 1);
        final saved = await msgRepo.getMessage('msg-zero-owner');
        expect(saved, isNotNull);
        expect(saved!.id, 'msg-zero-owner');
        expect(saved.status, 'sent');
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);
        expect(saved.wireEnvelope, isNull);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxStore').length,
          1,
        );
      },
    );

    test(
      'DE-008 retry of timeout-owned failed row reuses message id and clears invisible failed state',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-1',
            username: 'Alice',
            role: MemberRole.writer,
            publicKey: 'pk-peer-1',
            joinedAt: DateTime.utc(2026, 1, 15, 12),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-2',
            joinedAt: DateTime.utc(2026, 1, 15, 12, 1),
          ),
        );
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-de008-timeout-owned',
          'topicPeers': 1,
        };
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-de008-timeout-owned',
            text: 'Retry timeout-owned row',
            timestampIso: '2026-01-15T12:00:00.000Z',
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 1);
        final saved = await msgRepo.getMessage('msg-de008-timeout-owned');
        expect(saved, isNotNull);
        expect(saved!.id, 'msg-de008-timeout-owned');
        expect(saved.status, 'sent');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);

        final page = await msgRepo.getMessagesPage('group-1');
        expect(page.map((message) => message.id), ['msg-de008-timeout-owned']);
        expect(page.single.status, 'sent');
        expect(await msgRepo.getFailedOutgoingMessages(), isEmpty);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          hasLength(1),
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
          hasLength(1),
        );
      },
    );

    test(
      'retries a failed text row even when inboxRetryPayload was cleared after inbox success',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-1',
            username: 'Alice',
            role: MemberRole.writer,
            publicKey: 'pk-peer-1',
            joinedAt: DateTime.utc(2026, 1, 15, 12),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-2',
            joinedAt: DateTime.utc(2026, 1, 15, 12, 1),
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-inbox-ok',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Retry me from wireEnvelope',
            timestamp: DateTime.parse('2026-01-15T12:00:00.000Z'),
            keyGeneration: 0,
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.parse('2026-01-15T12:00:00.000Z'),
            wireEnvelope: jsonEncode({
              'groupId': 'group-1',
              'text': 'Retry me from wireEnvelope',
              'senderPeerId': 'peer-1',
              'senderUsername': 'Alice',
              'messageId': 'msg-inbox-ok',
            }),
            inboxStored: true,
            inboxRetryPayload: null,
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 1);
        final saved = await msgRepo.getMessage('msg-inbox-ok');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.wireEnvelope, isNull);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
      },
    );

    test(
      'retries a failed media row from persisted done attachments when inboxRetryPayload was cleared after inbox success',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-media-done',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Retry media from attachments',
            timestamp: DateTime.parse('2026-01-15T12:00:00.000Z'),
            keyGeneration: 0,
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.parse('2026-01-15T12:00:00.000Z'),
            wireEnvelope: jsonEncode({
              'groupId': 'group-1',
              'text': 'Retry media from attachments',
              'senderPeerId': 'peer-1',
              'senderUsername': 'Alice',
              'messageId': 'msg-media-done',
              'media': [
                {'id': 'att-media-done'},
              ],
            }),
            inboxStored: true,
            inboxRetryPayload: null,
          ),
        );
        await mediaRepo.saveAttachment(
          _makeAttachment(
            id: 'att-media-done',
            messageId: 'msg-media-done',
            downloadStatus: 'done',
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 1);
        final saved = await msgRepo.getMessage('msg-media-done');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.timestamp, DateTime.parse('2026-01-15T12:00:00.000Z'));
        expect(saved.wireEnvelope, isNull);
        final attachments = await mediaRepo.getAttachmentsForMessage(
          'msg-media-done',
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.id, 'att-media-done');
        expect(attachments.single.downloadStatus, 'done');
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
      },
    );

    test(
      'retries a failed GIF row from persisted done attachments with image/gif preserved',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-gif-done',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: '',
            timestamp: DateTime.parse('2026-01-15T12:00:00.000Z'),
            keyGeneration: 0,
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.parse('2026-01-15T12:00:00.000Z'),
            wireEnvelope: jsonEncode({
              'groupId': 'group-1',
              'text': '',
              'senderPeerId': 'peer-1',
              'senderUsername': 'Alice',
              'messageId': 'msg-gif-done',
              'media': [
                {'id': 'att-gif-done', 'mime': 'image/gif'},
              ],
            }),
            inboxStored: true,
            inboxRetryPayload: null,
          ),
        );
        await mediaRepo.saveAttachment(
          _makeAttachment(
            id: 'att-gif-done',
            messageId: 'msg-gif-done',
            downloadStatus: 'done',
            mime: 'image/gif',
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 1);
        final saved = await msgRepo.getMessage('msg-gif-done');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        final publishMsg = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        expect(publishMsg, contains('"mime":"image/gif"'));
      },
    );

    test(
      'deterministic restart retry publishes text quote and media rows in persisted order',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());

        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-quote-later',
            text: 'Reply after restart',
            timestampIso: '2026-01-15T12:02:00.000Z',
            quotedMessageId: 'msg-root',
          ),
        );
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-media-middle',
            text: 'Photo after restart',
            timestampIso: '2026-01-15T12:01:00.000Z',
            media: [
              {'id': 'att-media-middle', 'mime': 'image/jpeg'},
            ],
          ),
        );
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-alpha-text',
            text: 'First after restart',
            timestampIso: '2026-01-15T12:01:00.000Z',
          ),
        );
        await mediaRepo.saveAttachment(
          _makeAttachment(
            id: 'att-media-middle',
            messageId: 'msg-media-middle',
            downloadStatus: 'done',
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 3);
        final publishPayloads = _publishedGroupPayloads(bridge);
        expect(
          publishPayloads.map((payload) => payload['messageId']).toList(),
          ['msg-alpha-text', 'msg-media-middle', 'msg-quote-later'],
        );
        expect(publishPayloads[0]['text'], 'First after restart');
        expect(publishPayloads[1]['text'], 'Photo after restart');
        expect(
          (publishPayloads[1]['media'] as List).cast<Map>().single['id'],
          'att-media-middle',
        );
        expect(publishPayloads[2]['quotedMessageId'], 'msg-root');

        final alpha = await msgRepo.getMessage('msg-alpha-text');
        final media = await msgRepo.getMessage('msg-media-middle');
        final quote = await msgRepo.getMessage('msg-quote-later');
        expect(alpha!.status, 'sent');
        expect(media!.status, 'sent');
        expect(quote!.status, 'sent');
        expect(quote.timestamp, DateTime.parse('2026-01-15T12:02:00.000Z'));
        expect(quote.quotedMessageId, 'msg-root');

        final attachments = await mediaRepo.getAttachmentsForMessage(
          'msg-media-middle',
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.id, 'att-media-middle');
        expect(attachments.single.downloadStatus, 'done');
      },
    );

    test(
      'skips rows whose persisted media attachments are still upload_pending',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-media-pending',
            text: 'Retry later after upload recovery',
            timestampIso: '2026-01-15T12:00:00.000Z',
            inboxRetryPayload: jsonEncode({
              'groupId': 'group-1',
              'message': jsonEncode({
                'groupId': 'group-1',
                'senderId': 'peer-1',
                'senderUsername': 'Alice',
                'keyEpoch': 0,
                'text': 'Retry later after upload recovery',
                'timestamp': '2026-01-15T12:00:00.000Z',
                'messageId': 'msg-media-pending',
                'media': [
                  {'id': 'att-media-pending'},
                ],
              }),
            }),
          ),
        );
        await mediaRepo.saveAttachment(
          _makeAttachment(
            id: 'att-media-pending',
            messageId: 'msg-media-pending',
            downloadStatus: 'upload_pending',
          ),
        );

        late int count;
        final events = await captureFlowEvents(() async {
          count = await retryFailedGroupMessages(
            groupMsgRepo: msgRepo,
            groupRepo: groupRepo,
            identityRepo: identityRepo,
            bridge: bridge,
            mediaAttachmentRepo: mediaRepo,
          );
        });

        expect(count, 0);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );
        final saved = await msgRepo.getMessage('msg-media-pending');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        final attachments = await mediaRepo.getAttachmentsForMessage(
          'msg-media-pending',
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.downloadStatus, 'upload_pending');

        final skipped = events.firstWhere(
          (event) =>
              event['event'] ==
              'RETRY_FAILED_GROUP_MESSAGES_MESSAGE_SKIPPED_UNSUPPORTED',
        );
        expect(skipped['details']['messageId'], 'msg-medi');
        expect(skipped['details']['reason'], 'incomplete_media_attachments');

        final timing = events.lastWhere(
          (event) => event['event'] == 'RETRY_FAILED_GROUP_MESSAGES_TIMING',
        );
        expect(timing['details']['outcome'], 'complete');
        expect(timing['details']['total'], 1);
        expect(timing['details']['succeeded'], 0);
        expect(timing['details']['skippedUnsupported'], 1);
      },
    );

    test(
      'skips media retry rows when no resendable persisted attachments exist',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-media',
            text: 'Retry later',
            timestampIso: '2026-01-15T12:00:00.000Z',
            inboxRetryPayload: jsonEncode({
              'groupId': 'group-1',
              'message': jsonEncode({
                'groupId': 'group-1',
                'senderId': 'peer-1',
                'senderUsername': 'Alice',
                'keyEpoch': 0,
                'text': 'Retry later',
                'timestamp': '2026-01-15T12:00:00.000Z',
                'messageId': 'msg-media',
                'media': [
                  {'id': 'media-1'},
                ],
              }),
            }),
          ),
        );

        final count = await retryFailedGroupMessages(
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 0);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );
      },
    );

    test('continues after a per-message publish error', () async {
      identityRepo.seed(_makeIdentity());
      await groupRepo.saveGroup(_makeGroup());
      await msgRepo.saveMessage(
        _makeFailedGroupMessage(
          id: 'msg-fail-1',
          text: 'First retry',
          timestampIso: '2026-01-15T12:00:00.000Z',
        ),
      );
      await msgRepo.saveMessage(
        _makeFailedGroupMessage(
          id: 'msg-fail-2',
          text: 'Second retry',
          timestampIso: '2026-01-15T12:01:00.000Z',
        ),
      );

      final failingBridge = _FailFirstPublishBridge();

      final count = await retryFailedGroupMessages(
        groupMsgRepo: msgRepo,
        groupRepo: groupRepo,
        identityRepo: identityRepo,
        bridge: failingBridge,
        mediaAttachmentRepo: mediaRepo,
      );

      expect(count, 1);
      expect((await msgRepo.getMessage('msg-fail-1'))!.status, 'failed');
      expect((await msgRepo.getMessage('msg-fail-2'))!.status, 'sent');
    });

    test(
      'retryFailedGroupMessage only retries the requested failed media row',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-targeted',
            text: 'Retry only me',
            timestampIso: '2026-01-15T12:00:00.000Z',
            inboxRetryPayload: jsonEncode({
              'groupId': 'group-1',
              'message': jsonEncode({
                'groupId': 'group-1',
                'senderId': 'peer-1',
                'senderUsername': 'Alice',
                'keyEpoch': 0,
                'text': 'Retry only me',
                'timestamp': '2026-01-15T12:00:00.000Z',
                'messageId': 'msg-targeted',
                'media': [
                  {'id': 'att-targeted'},
                ],
              }),
            }),
          ),
        );
        await msgRepo.saveMessage(
          _makeFailedGroupMessage(
            id: 'msg-untouched',
            text: 'Leave me failed',
            timestampIso: '2026-01-15T12:01:00.000Z',
            inboxRetryPayload: jsonEncode({
              'groupId': 'group-1',
              'message': jsonEncode({
                'groupId': 'group-1',
                'senderId': 'peer-1',
                'senderUsername': 'Alice',
                'keyEpoch': 0,
                'text': 'Leave me failed',
                'timestamp': '2026-01-15T12:01:00.000Z',
                'messageId': 'msg-untouched',
                'media': [
                  {'id': 'att-untouched'},
                ],
              }),
            }),
          ),
        );
        await mediaRepo.saveAttachment(
          _makeAttachment(
            id: 'att-targeted',
            messageId: 'msg-targeted',
            downloadStatus: 'done',
          ),
        );
        await mediaRepo.saveAttachment(
          _makeAttachment(
            id: 'att-untouched',
            messageId: 'msg-untouched',
            downloadStatus: 'done',
          ),
        );

        final count = await retryFailedGroupMessage(
          messageId: 'msg-targeted',
          groupMsgRepo: msgRepo,
          groupRepo: groupRepo,
          identityRepo: identityRepo,
          bridge: bridge,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(count, 1);
        expect((await msgRepo.getMessage('msg-targeted'))!.status, 'sent');
        expect((await msgRepo.getMessage('msg-untouched'))!.status, 'failed');
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
      },
    );
  });
}
