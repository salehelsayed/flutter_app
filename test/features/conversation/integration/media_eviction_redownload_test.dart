// 229 TC-229-09: evicted rows never auto-loop on reopen; an explicit
// re-download settles truthfully (done or terminal unavailable after relay
// expiry) in the direct lane AND the shared group/announcement lane.
//
// Registered in ONE_TO_ONE_TESTS, ONE_TO_ONE_HOST_TESTS and GROUP_TESTS —
// this one file owns both lane fixtures.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/test_user.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

const _validHash =
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

class _StreamGroupMessageListener extends GroupMessageListener {
  _StreamGroupMessageListener(this._externalStream)
      : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpGroupMsgRepo());

  final Stream<GroupMessage> _externalStream;

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpGroupMsgRepo implements GroupMessageRepository {
  @override
  Future<int> transitionSendingToFailed() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

int _downloadCount(FakeBridge bridge) => bridge.commandLog
    .where((command) => command == 'media:download')
    .length;

/// Bridge whose relay copy has expired: every media:download answers the
/// honest "not found" that must settle a terminal `download_failed`.
FakeBridge _expiredRelayBridge() => FakeBridge(
      initialResponses: {
        'media:download': {'ok': false, 'errorMessage': 'blob not found'},
      },
    );

Future<void> _pumpWithRealIo(WidgetTester tester,
    {required Future<bool> Function() until}) async {
  for (var i = 0; i < 80 && !await until(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(installFakeJustAudioPlatform);

  MediaAttachment evictedAttachment(String id, String messageId) =>
      MediaAttachment(
        id: id,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        downloadStatus: kMediaDownloadStatusEvicted,
        downloadRetryCount: 0,
        contentHash: _validHash,
        encryptionKeyBase64: 'key-fixture',
        encryptionNonce: 'nonce-fixture',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        createdAt: '2026-07-10T09:00:00.000Z',
      );

  testWidgets('direct evicted media waits for explicit retry', (tester) async {
    final network = FakeP2PNetwork();
    final mediaRepo = InMemoryMediaAttachmentRepository();
    final viewer = TestUser.create(
      peerId: 'peer-viewer',
      username: 'Viewer',
      network: network,
      mediaAttachmentRepo: mediaRepo,
    );
    final bridge = _expiredRelayBridge();
    final identityRepo = FakeIdentityRepository()
      ..seed(FakeIdentityRepository.makeIdentity(peerId: 'peer-viewer'));
    final contact = ContactModel(
      peerId: 'peer-sender',
      publicKey: 'pk-sender',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Sender',
      signature: 'sig-sender',
      scannedAt: '2026-07-01T00:00:00.000Z',
    );
    const messageId = 'msg-evict-direct';
    final sentAt = '2026-07-09T10:00:00.000Z';
    await viewer.messageRepo.saveMessage(
      ConversationMessage(
        id: messageId,
        contactPeerId: contact.peerId,
        senderPeerId: contact.peerId,
        text: 'evicted letter',
        timestamp: sentAt,
        status: 'delivered',
        isIncoming: true,
        createdAt: sentAt,
      ),
    );
    await mediaRepo.saveAttachment(
      evictedAttachment('att-evict-direct', messageId),
      owner: MediaOwnerLane.direct,
    );

    Future<void> pumpScreen() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: identityRepo,
            messageRepo: viewer.messageRepo,
            chatMessageListener: ChatMessageListener(
              chatMessageStream: const Stream.empty(),
              messageRepo: viewer.messageRepo,
              contactRepo: viewer.contactRepo,
            ),
            p2pService: viewer.p2pService,
            bridge: bridge,
            contactRepo: viewer.contactRepo,
            mediaAttachmentRepo: mediaRepo,
            mediaFileManager: FakeMediaFileManager(),
            micPermissionGateway: FakeMicPermissionGateway(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
    }

    // First open: zero transfers for the evicted row.
    await pumpScreen();
    expect(_downloadCount(bridge), 0,
        reason: 'an evicted row must not auto-download on open');

    // Reopen: still zero — no auto loop.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScreen();
    expect(_downloadCount(bridge), 0,
        reason: 'reopening the lane must not re-arm the evicted row');

    // Explicit user action transfers exactly once; the expired relay answer
    // settles the honest terminal state.
    const retryKey = ValueKey(
      'evicted-media-retry-msg-evict-direct-att-evict-direct',
    );
    expect(find.byKey(retryKey), findsOneWidget);
    await tester.tap(find.byKey(retryKey));
    await _pumpWithRealIo(tester, until: () async {
      if (_downloadCount(bridge) < 1) return false;
      final rows = await mediaRepo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      return rows.single.downloadStatus == kMediaDownloadStatusDownloadFailed;
    });
    expect(_downloadCount(bridge), 1,
        reason: 'the explicit retry transfers exactly once');
    final persisted = await mediaRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.direct,
    );
    expect(
      persisted.single.downloadStatus,
      kMediaDownloadStatusDownloadFailed,
      reason: 'relay expiry settles terminal, never a retry loop',
    );

    // Reopen once more: the terminal row makes zero further transfers.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScreen();
    expect(_downloadCount(bridge), 1,
        reason: 'a terminal row must never re-arm recovery');
  });

  testWidgets(
      'group and announcement evicted media settle terminal expiry without '
      'an auto loop', (tester) async {
    final lanes = [
      (kind: 'discussion', type: GroupType.chat, role: GroupRole.admin),
      // Read-only announcement member: retry works without compose
      // permission.
      (kind: 'announcement', type: GroupType.announcement, role: GroupRole.member),
    ];
    for (final lane in lanes) {
      final network = FakeP2PNetwork();
      final mediaRepo = InMemoryMediaAttachmentRepository();
      final user = TestUser.create(
        peerId: 'peer-viewer-${lane.kind}',
        username: 'Viewer',
        network: network,
        mediaAttachmentRepo: mediaRepo,
      );
      final bridge = _expiredRelayBridge();
      final groupRepo = InMemoryGroupRepository();
      final msgRepo = InMemoryGroupMessageRepository();
      final contactRepo = InMemoryContactRepository();
      final identityRepo = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'peer-viewer-${lane.kind}',
          ),
        );
      final group = GroupModel(
        id: 'group-evict-${lane.kind}',
        name: 'Evict ${lane.kind}',
        type: lane.type,
        topicName: 'topic-evict-${lane.kind}',
        description: 'evicted media lane',
        createdAt: DateTime.utc(2026, 7, 1),
        createdBy: 'peer-owner',
        myRole: lane.role,
      );
      await groupRepo.saveGroup(group);
      final messageId = 'msg-evict-${lane.kind}';
      final attachmentId = 'att-evict-${lane.kind}';
      await msgRepo.saveMessage(
        GroupMessage(
          id: messageId,
          groupId: group.id,
          senderPeerId: 'peer-owner',
          senderUsername: 'Owner',
          text: 'evicted ${lane.kind} letter',
          timestamp: DateTime.utc(2026, 7, 9, 10),
          status: 'sent',
          isIncoming: true,
          createdAt: DateTime.utc(2026, 7, 9, 10),
        ),
      );
      await mediaRepo.saveAttachment(
        evictedAttachment(attachmentId, messageId),
        owner: MediaOwnerLane.group,
      );

      final messageStream = StreamController<GroupMessage>.broadcast();
      addTearDown(messageStream.close);

      Future<void> pumpGroupScreen() async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupConversationWired(
              group: group,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              groupMessageListener: _StreamGroupMessageListener(
                messageStream.stream,
              ),
              bridge: bridge,
              identityRepo: identityRepo,
              contactRepo: contactRepo,
              p2pService: user.p2pService,
              mediaAttachmentRepo: mediaRepo,
              mediaFileManager: FakeMediaFileManager(),
              micPermissionGateway: FakeMicPermissionGateway(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Open + reopen: zero transfers for the evicted row.
      await pumpGroupScreen();
      expect(_downloadCount(bridge), 0,
          reason: '${lane.kind}: evicted must not auto-download on open');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpGroupScreen();
      expect(_downloadCount(bridge), 0,
          reason: '${lane.kind}: reopen must not re-arm the evicted row');

      // Explicit retry (reachable even for a read-only announcement member)
      // transfers exactly once and settles the honest terminal state.
      final retryKey = ValueKey(
        'evicted-media-retry-$messageId-$attachmentId',
      );
      expect(find.byKey(retryKey), findsOneWidget,
          reason: '${lane.kind}: the removed state keeps an explicit retry');
      await tester.tap(find.byKey(retryKey));
      await _pumpWithRealIo(tester, until: () async {
        if (_downloadCount(bridge) < 1) return false;
        final rows = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        return rows.single.downloadStatus ==
            kMediaDownloadStatusDownloadFailed;
      });
      expect(_downloadCount(bridge), 1,
          reason: '${lane.kind}: one action, one transfer');
      final persisted = await mediaRepo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.group,
      );
      expect(
        persisted.single.downloadStatus,
        kMediaDownloadStatusDownloadFailed,
        reason: '${lane.kind}: relay expiry settles terminal',
      );

      // Final reopen: terminal stays quiet.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpGroupScreen();
      expect(_downloadCount(bridge), 1,
          reason: '${lane.kind}: no auto loop after terminal expiry');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
