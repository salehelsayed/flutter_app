@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/core/bridge/fake_bridge.dart';
import '../test/core/services/fake_p2p_service.dart';
import '../test/features/identity/domain/repositories/fake_identity_repository.dart';
import '../test/shared/fakes/in_memory_contact_repository.dart';
import '../test/shared/fakes/in_memory_group_message_repository.dart';
import '../test/shared/fakes/in_memory_group_repository.dart';
import '../test/shared/fakes/in_memory_media_attachment_repository.dart';

const _groupId = 'announcement-platform-group';
const _messageId = 'announcement-platform-message';
const _attachmentId = 'announcement-platform-attachment';
const _readerPeerId = 'announcement-platform-reader';

class _LifecycleMessageRepository extends InMemoryGroupMessageRepository
    implements GroupPrivateMediaLifecycleRepository {
  @override
  Future<bool> advanceGroupPrivateMediaClock(
    String messageId, {
    required int nowMs,
  }) async {
    final current = await getMessage(messageId);
    if (current == null) return false;
    await saveMessage(current.copyWith(mediaLastCheckedAt: nowMs));
    return true;
  }

  @override
  Future<bool> anchorOutgoingGroupPrivateMediaCustody(
    String messageId, {
    required int nowMs,
  }) async {
    final current = await getMessage(messageId);
    if (current == null || current.isIncoming) return false;
    await saveMessage(
      current.copyWith(mediaReceivedAt: nowMs, mediaLastCheckedAt: nowMs),
    );
    return true;
  }

  @override
  Future<bool> completeGroupPrivateMediaCleanup(String messageId) async {
    final current = await getMessage(messageId);
    if (current == null || !current.mediaCleanupPending) return false;
    await saveMessage(current.copyWith(mediaCleanupPending: false));
    return true;
  }

  @override
  Future<bool> consumeGroupPrivateMedia(
    String messageId, {
    required int nowMs,
  }) async {
    final current = await getMessage(messageId);
    if (current == null || current.mediaConsumedAt != null) return false;
    await saveMessage(
      current.copyWith(
        mediaConsumedAt: nowMs,
        mediaLastCheckedAt: nowMs,
        mediaCleanupPending: true,
      ),
    );
    return true;
  }

  @override
  Future<List<GroupMessage>> loadActiveGroupPrivateMediaDisappearing({
    int limit = 100,
  }) async => const <GroupMessage>[];

  @override
  Future<GroupMessage?> loadGroupPrivateMediaMessage(String messageId) =>
      getMessage(messageId);

  @override
  Future<List<GroupMessage>> loadGroupPrivateMediaRecoveryCandidates({
    int limit = 100,
  }) async => const <GroupMessage>[];

  @override
  Future<int?> loadNextGroupPrivateMediaExpiryAtMs() async => null;

  @override
  Future<bool> rotateGroupPrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) async => getMessage(messageId).then((message) => message != null);
}

class _LifecycleMediaRepository extends InMemoryMediaAttachmentRepository
    implements
        GroupPrivateMediaCleanupRepository,
        GroupPrivateMediaCleanupRuntime {
  final MediaAttachmentLifecycleLock _lifecycleLock =
      MediaAttachmentLifecycleLock();

  @override
  MediaAttachmentLifecycleLock get groupPrivateMediaLifecycleLock =>
      _lifecycleLock;

  @override
  Future<bool> deleteGroupPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  }) async {
    final rows = await getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    return rows.any((attachment) => attachment.id == attachmentId);
  }

  @override
  Future<int> deleteGroupPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) async {
    final rows = await getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    if (!rows.any((attachment) => attachment.id == attachmentId)) return 0;
    return deleteAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
  }

  @override
  Future<List<GroupPrivateMediaLifecycleAttachmentMetadata>>
  loadGroupPrivateMediaLifecycleAttachmentMetadata(String messageId) async {
    final rows = await getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    return rows
        .map(
          (attachment) => GroupPrivateMediaLifecycleAttachmentMetadata(
            id: attachment.id,
            messageId: attachment.messageId,
            mime: attachment.mime,
            size: attachment.size,
            downloadStatus: attachment.downloadStatus,
            localPath: attachment.localPath,
          ),
        )
        .toList(growable: false);
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  int attempts = 80,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail(reason);
}

Future<Map<String, Object?>> _pumpUntilProtectionState(
  WidgetTester tester,
  PrivateMediaProtectionCoordinator coordinator,
  bool Function(Map<String, Object?> state) condition, {
  required String reason,
}) async {
  for (var attempt = 0; attempt < 80; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final state = await coordinator.debugGetState();
    if (condition(state)) return state;
  }
  fail(reason);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'APL-08 protected announcement wired route applies shared Android capture safeguards',
    (tester) async {
      if (!Platform.isAndroid) {
        fail('APL-08 is the controllable Android Plan-242 platform proof');
      }

      final mediaFileManager = MediaFileManager();
      final canonicalRelative = mediaFileManager.relativePathForAttachment(
        contactPeerId: _groupId,
        blobId: _attachmentId,
        mime: 'image/png',
      );
      final canonicalAbsolute = await mediaFileManager.resolveStoredPath(
        canonicalRelative,
      );
      final image = File(canonicalAbsolute);
      await image.parent.create(recursive: true);
      await image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
        flush: true,
      );
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final contentHash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
        image.path,
      );

      final messageRepository = _LifecycleMessageRepository();
      final mediaRepository = _LifecycleMediaRepository();
      final groupRepository = InMemoryGroupRepository();
      final contactRepository = InMemoryContactRepository();
      final bridge = FakeBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: _readerPeerId,
          relayState: 'online',
        ),
      );
      addTearDown(p2pService.dispose);

      final group = GroupModel(
        id: _groupId,
        name: 'Protected announcements',
        type: GroupType.announcement,
        topicName: 'announcement-platform-topic',
        createdAt: DateTime.utc(2026, 7, 12),
        createdBy: 'announcement-platform-admin',
        myRole: GroupRole.member,
      );
      await groupRepository.saveGroup(group);
      await groupRepository.saveMember(
        GroupMember(
          groupId: _groupId,
          peerId: _readerPeerId,
          username: 'Reader',
          role: MemberRole.reader,
          publicKey: 'reader-public-key',
          mlKemPublicKey: 'reader-mlkem-public-key',
          joinedAt: DateTime.utc(2026, 7, 12, 9),
        ),
      );
      await groupRepository.saveMember(
        GroupMember(
          groupId: _groupId,
          peerId: 'announcement-platform-admin',
          username: 'SECRET announcement admin',
          role: MemberRole.admin,
          publicKey: 'admin-public-key',
          mlKemPublicKey: 'admin-mlkem-public-key',
          joinedAt: DateTime.utc(2026, 7, 12, 8),
        ),
      );
      await groupRepository.saveKey(
        GroupKeyInfo(
          groupId: _groupId,
          keyGeneration: 1,
          encryptedKey: 'announcement-platform-key',
          createdAt: DateTime.utc(2026, 7, 12, 8),
        ),
      );

      await messageRepository.saveMessage(
        GroupMessage(
          id: _messageId,
          groupId: _groupId,
          senderPeerId: 'announcement-platform-admin',
          senderUsername: 'SECRET announcement admin',
          text: 'SECRET protected announcement caption',
          timestamp: DateTime.utc(2026, 7, 12, 10),
          status: 'delivered',
          isIncoming: true,
          privateMediaPolicy: const GroupPrivateMediaPolicy.protected(),
          mediaReceivedAt: 100,
          createdAt: DateTime.utc(2026, 7, 12, 10),
        ),
      );
      await mediaRepository.saveAttachment(
        MediaAttachment(
          id: _attachmentId,
          messageId: _messageId,
          mime: 'image/png',
          size: await image.length(),
          mediaType: 'image',
          localPath: canonicalRelative,
          downloadStatus: 'done',
          createdAt: '2026-07-12T10:00:00.000Z',
          contentHash: contentHash,
          encryptionKeyBase64: 'announcement-platform-encryption-key',
          encryptionNonce: 'announcement-platform-encryption-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        ),
        owner: MediaOwnerLane.group,
      );

      final identityRepository = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: _readerPeerId,
            publicKey: 'reader-public-key',
            privateKey: 'reader-private-key',
            mlKemPublicKey: 'reader-mlkem-public-key',
          ),
        );
      final listener = GroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: messageRepository,
        bridge: bridge,
        getSelfPeerId: () async => _readerPeerId,
        mediaAttachmentRepo: mediaRepository,
        mediaFileManager: mediaFileManager,
      );
      addTearDown(listener.dispose);

      final coordinator = PrivateMediaProtectionCoordinator.sharedPlatform();
      final before = await coordinator.debugGetState();
      expect(before['activeOwnerCount'], 0);
      expect(before['secureApplied'], isFalse);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepository,
            msgRepo: messageRepository,
            groupMessageListener: listener,
            bridge: bridge,
            identityRepo: identityRepository,
            contactRepo: contactRepository,
            p2pService: p2pService,
            mediaAttachmentRepo: mediaRepository,
            mediaFileManager: mediaFileManager,
          ),
        ),
      );

      final openButton = find.byKey(
        const ValueKey('group-private-open-$_messageId'),
      );
      await _pumpUntil(
        tester,
        () => openButton.evaluate().length == 1,
        reason: 'announcement reader never received the private-media route',
      );
      final conversation = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(conversation.group.type, GroupType.announcement);
      expect(conversation.group.myRole, GroupRole.member);
      expect(conversation.canWrite, isFalse);
      expect(find.text('SECRET protected announcement caption'), findsNothing);

      Future<void> openAnnouncementRoute() async {
        await tester.tap(openButton);
        await _pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('group-private-media-viewer'))
                  .evaluate()
                  .length ==
              1,
          reason: 'announcement tap did not push the shared private viewer',
        );
        final viewerRoot = find.byKey(
          const ValueKey('group-private-media-viewer'),
        );
        final typedViewerFinder = find.descendant(
          of: viewerRoot,
          matching: find.byType(FullScreenTypedMediaViewer),
        );
        expect(typedViewerFinder, findsOneWidget);
        final typedViewer = tester.widget<FullScreenTypedMediaViewer>(
          typedViewerFinder,
        );
        expect(typedViewer.privacyMinimized, isTrue);
        expect(typedViewer.items, hasLength(1));
        expect(typedViewer.items.single.owner, MediaOwnerLane.group);
        expect(typedViewer.items.single.protection.isProtected, isTrue);
        expect(typedViewer.items.single.capabilities.allowed, isEmpty);
        await _pumpUntilProtectionState(
          tester,
          coordinator,
          (state) =>
              state['activeOwnerCount'] == 1 && state['secureApplied'] == true,
          reason: 'announcement viewer never acquired Android FLAG_SECURE',
        );
        final routeContext = tester.element(viewerRoot);
        final l10n = AppLocalizations.of(routeContext)!;
        expect(
          find.descendant(
            of: viewerRoot,
            matching: find.text(l10n.group_private_media_notification_body),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: viewerRoot,
            matching: find.text(l10n.private_media_android_capture_limit),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: viewerRoot,
            matching: find.text(l10n.private_media_general_capture_limit),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: viewerRoot,
            matching: find.text('SECRET announcement admin'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: viewerRoot,
            matching: find.text('SECRET protected announcement caption'),
          ),
          findsNothing,
        );
      }

      await openAnnouncementRoute();
      final privateViewer = find.byKey(
        const ValueKey('group-private-media-viewer'),
      );
      final privateViewerBack = find.descendant(
        of: privateViewer,
        matching: find.byIcon(Icons.arrow_back),
      );
      expect(privateViewerBack, findsOneWidget);
      await tester.tap(privateViewerBack);
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('group-private-media-viewer'))
            .evaluate()
            .isEmpty,
        reason: 'normal announcement route exit did not close the viewer',
      );
      await _pumpUntilProtectionState(
        tester,
        coordinator,
        (state) =>
            state['activeOwnerCount'] == 0 && state['secureApplied'] == false,
        reason: 'normal announcement route exit retained FLAG_SECURE ownership',
      );

      await openAnnouncementRoute();
      expect(
        await coordinator.debugInjectEvent(
          PrivateMediaProtectionDebugEvent.background,
        ),
        isTrue,
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('group-private-media-viewer'))
            .evaluate()
            .isEmpty,
        reason: 'Android background event did not cover and close the route',
      );
      await _pumpUntilProtectionState(
        tester,
        coordinator,
        (state) =>
            state['activeOwnerCount'] == 0 && state['secureApplied'] == false,
        reason: 'background exit retained Android FLAG_SECURE ownership',
      );

      expect(find.text('SECRET protected announcement caption'), findsNothing);
    },
  );
}
