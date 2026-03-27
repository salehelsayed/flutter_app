import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

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
}) {
  return GroupMessage(
    id: id,
    groupId: 'group-1',
    senderPeerId: 'peer-1',
    senderUsername: 'Alice',
    text: text,
    timestamp: DateTime.parse(timestampIso),
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
    }),
    inboxStored: false,
    inboxRetryPayload:
        inboxRetryPayload ??
        jsonEncode({
          'groupId': 'group-1',
          'message': jsonEncode({
            'groupId': 'group-1',
            'senderId': 'peer-1',
            'senderUsername': 'Alice',
            'keyEpoch': 0,
            'text': text,
            'timestamp': timestampIso,
            'messageId': id,
          }),
          'recipientPeerIds': ['peer-2'],
          'pushTitle': 'Test Group',
          'pushBody': 'Alice: $text',
        }),
  );
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

    setUp(() {
      identityRepo = FakeIdentityRepository();
      msgRepo = InMemoryGroupMessageRepository();
      groupRepo = InMemoryGroupRepository();
      mediaRepo = InMemoryMediaAttachmentRepository();
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': true, 'messageId': 'msg-1', 'topicPeers': 1},
        },
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
      'retries a failed text row even when inboxRetryPayload was cleared after inbox success',
      () async {
        identityRepo.seed(_makeIdentity());
        await groupRepo.saveGroup(_makeGroup());
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
        final saved = await msgRepo.getMessage('msg-media-pending');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        final attachments = await mediaRepo.getAttachmentsForMessage(
          'msg-media-pending',
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.downloadStatus, 'upload_pending');
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
  });
}
