import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/build_received_media_forward.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/handle_delivery_receipt_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_screen.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/repositories/fake_media_attachment_repository.dart';
import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late Directory tempDir;
  late File sourceFile;
  late ConversationMessage message;
  late FakeMediaAttachmentRepository mediaRepo;

  setUp(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
    tempDir = Directory.systemTemp.createTempSync('conversation_forward_ui_');
    sourceFile = File('${tempDir.path}/source.jpg')..writeAsBytesSync([1]);
    final attachment = MediaAttachment(
      id: 'attachment-1',
      messageId: 'message-1',
      mime: 'image/jpeg',
      size: 1,
      mediaType: 'image',
      localPath: sourceFile.path,
      downloadStatus: 'done',
      createdAt: '2026-07-10T10:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );
    message = ConversationMessage(
      id: 'message-1',
      contactPeerId: 'contact-1',
      senderPeerId: 'contact-1',
      text: 'editable source caption',
      timestamp: '2026-07-10T10:00:00.000Z',
      status: 'delivered',
      isIncoming: true,
      createdAt: '2026-07-10T10:00:00.000Z',
      media: [attachment],
    );
    mediaRepo = FakeMediaAttachmentRepository()..seed([attachment]);
  });

  tearDown(() {
    UploadWakeLockController.debugReset();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpFrames(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    required String reason,
    int attempts = 80,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      await tester.pump(const Duration(milliseconds: 25));
      if (condition()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(condition(), isTrue, reason: reason);
  }

  Widget app({
    required Locale locale,
    required DirectReceivedMediaForwardHandler onForward,
    GlobalKey<NavigatorState>? navigatorKey,
    List<ConversationMessage>? screenMessages,
  }) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConversationScreen(
          contactPeerId: 'contact-1',
          contactUsername: 'Alice',
          connectionDate: 'July 10, 2026',
          ownPeerId: 'self',
          messages: screenMessages ?? [message],
          initialLoadDone: true,
          onSend: (_) {},
          onBack: () {},
          onForwardMedia: onForward,
        ),
      ),
    );
  }

  testWidgets(
    'real delivery receipt keeps forwarded image/video card and viewers mounted',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler(
        kPrivateMediaProtectionEventChannel,
        (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
      );
      messenger.setMockMessageHandler(
        kPictureInPictureEventChannel,
        (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
      );
      addTearDown(() {
        messenger.setMockMessageHandler(
          kPrivateMediaProtectionEventChannel,
          null,
        );
        messenger.setMockMessageHandler(kPictureInPictureEventChannel, null);
      });
      final fixture = (await tester.runAsync(
        MediaRepositoryRealDbFixture.create,
      ))!;
      addTearDown(fixture.dispose);
      final imagePath = '${tempDir.path}/forwarded-output.png';
      final videoPath = '${tempDir.path}/forwarded-output.mp4';
      File(imagePath).writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      File(videoPath).writeAsBytesSync(const [0, 0, 0, 24]);
      const forwardedMessageId = 'forwarded-output-message';
      final forwarded = ConversationMessage(
        id: forwardedMessageId,
        contactPeerId: 'contact-1',
        senderPeerId: 'self',
        text: '',
        timestamp: '2026-07-10T11:00:00.000Z',
        status: 'inboxed',
        isIncoming: false,
        createdAt: '2026-07-10T11:00:00.000Z',
        transport: 'inbox',
        wireEnvelope: '{"type":"chat_message","version":"2"}',
        isForwarded: true,
        media: [
          MediaAttachment(
            id: 'forwarded-output-image',
            messageId: forwardedMessageId,
            mime: 'image/png',
            size: File(imagePath).lengthSync(),
            mediaType: 'image',
            localPath: imagePath,
            downloadStatus: 'done',
            createdAt: '2026-07-10T11:00:00.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
          MediaAttachment(
            id: 'forwarded-output-video',
            messageId: forwardedMessageId,
            mime: 'video/mp4',
            size: File(videoPath).lengthSync(),
            mediaType: 'video',
            localPath: videoPath,
            downloadStatus: 'done',
            createdAt: '2026-07-10T11:00:01.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
        ],
      );
      const deletedMessageId = 'deleted-output-message';
      final deleteCandidate = ConversationMessage(
        id: deletedMessageId,
        contactPeerId: 'contact-1',
        senderPeerId: 'self',
        text: 'delete candidate',
        timestamp: '2026-07-10T10:59:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-07-10T10:59:00.000Z',
        media: [
          MediaAttachment(
            id: 'deleted-output-image',
            messageId: deletedMessageId,
            mime: 'image/png',
            size: File(imagePath).lengthSync(),
            mediaType: 'image',
            localPath: imagePath,
            downloadStatus: 'done',
            createdAt: '2026-07-10T10:59:00.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
          MediaAttachment(
            id: 'deleted-output-video',
            messageId: deletedMessageId,
            mime: 'video/mp4',
            size: File(videoPath).lengthSync(),
            mediaType: 'video',
            localPath: videoPath,
            downloadStatus: 'done',
            createdAt: '2026-07-10T10:59:01.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
        ],
      );
      const retainedDeletedMessageId = 'retained-deleted-output-message';
      final retainedDeleted = ConversationMessage(
        id: retainedDeletedMessageId,
        contactPeerId: 'contact-1',
        senderPeerId: 'self',
        text: '',
        timestamp: '2026-07-10T10:58:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-07-10T10:58:00.000Z',
        deletedAt: '2026-07-10T10:58:30.000Z',
        deletedByPeerId: 'self',
        media: [
          MediaAttachment(
            id: 'retained-deleted-output-image',
            messageId: retainedDeletedMessageId,
            mime: 'image/png',
            size: File(imagePath).lengthSync(),
            mediaType: 'image',
            localPath: imagePath,
            downloadStatus: 'done',
            createdAt: '2026-07-10T10:58:00.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
          MediaAttachment(
            id: 'retained-deleted-output-video',
            messageId: retainedDeletedMessageId,
            mime: 'video/mp4',
            size: File(videoPath).lengthSync(),
            mediaType: 'video',
            localPath: videoPath,
            downloadStatus: 'done',
            createdAt: '2026-07-10T10:58:01.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
        ],
      );
      await tester.runAsync(() async {
        for (final candidate in [retainedDeleted, deleteCandidate, forwarded]) {
          await fixture.messageRepo.saveMessage(candidate);
          for (final attachment in candidate.media) {
            await fixture.repo.saveAttachment(
              attachment,
              owner: MediaOwnerLane.direct,
            );
          }
        }
      });

      final identities = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity(peerId: 'self'));
      final contacts = InMemoryContactRepository();
      const contact = ContactModel(
        peerId: 'contact-1',
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'contact-signature',
        scannedAt: '2026-07-10T09:00:00.000Z',
      );
      await contacts.addContact(contact);
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: fixture.messageRepo,
        contactRepo: contacts,
        bridge: FakeBridge(),
      );
      addTearDown(listener.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: identities,
            messageRepo: fixture.messageRepo,
            chatMessageListener: listener,
            p2pService: FakeP2PService(),
            bridge: FakeBridge(),
            contactRepo: contacts,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: FakeMediaFileManager(),
            imageProcessor: _testImageProcessor(),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () {
          final screens = find.byType(ConversationScreen);
          return screens.evaluate().isNotEmpty &&
              tester
                  .widget<ConversationScreen>(screens)
                  .messages
                  .any((candidate) => candidate.id == forwardedMessageId);
        },
        reason: 'the real DB message page must hydrate before receipt apply',
      );

      ConversationMessage visibleMessage([String id = forwardedMessageId]) =>
          tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .singleWhere((candidate) => candidate.id == id);

      expect(visibleMessage(retainedDeletedMessageId).isDeleted, isTrue);
      expect(
        visibleMessage(retainedDeletedMessageId).media,
        isEmpty,
        reason: 'cold/reopen load must not project retained deleted media rows',
      );
      final retainedDeletedRows = (await tester.runAsync(
        () => fixture.repo.getAttachmentsForMessage(
          retainedDeletedMessageId,
          owner: MediaOwnerLane.direct,
        ),
      ))!;
      expect(
        retainedDeletedRows,
        hasLength(2),
        reason:
            'the regression requires deliberately retained image/video rows',
      );
      expect(
        find.byKey(
          const ValueKey(
            'media-grid-cell-retained-deleted-output-message-retained-deleted-output-image',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey(
            'media-grid-cell-retained-deleted-output-message-retained-deleted-output-video',
          ),
        ),
        findsNothing,
      );

      expect(visibleMessage().status, 'inboxed');
      expect(
        visibleMessage().media.map((attachment) => attachment.id),
        <String>['forwarded-output-image', 'forwarded-output-video'],
      );
      expect(
        find.byKey(const ValueKey('direct-forwarded-marker')),
        findsOneWidget,
      );

      await tester.runAsync(
        () => handleDeliveryReceipt(
          message: ChatMessage(
            from: 'contact-1',
            to: 'self',
            content: jsonEncode({
              'type': 'delivery_receipt',
              'version': '1',
              'payload': {
                'messageIds': [forwardedMessageId],
                'ts': '2026-07-10T11:01:00.000Z',
              },
            }),
            timestamp: '2026-07-10T11:01:00.000Z',
            isIncoming: true,
          ),
          messageRepo: fixture.messageRepo,
        ),
      );
      await pumpUntil(
        tester,
        () =>
            visibleMessage().status == 'delivered' &&
            visibleMessage().media.length == 2,
        reason: 'receipt status must merge without erasing hydrated media',
      );

      expect(visibleMessage().status, 'delivered');
      expect(
        visibleMessage().media.map((attachment) => attachment.id),
        <String>['forwarded-output-image', 'forwarded-output-video'],
      );
      expect(
        find.byKey(const ValueKey('direct-forwarded-marker')),
        findsOneWidget,
      );
      final canonical = (await tester.runAsync(
        () => fixture.messageRepo.getMessage(forwardedMessageId),
      ))!;
      expect(canonical.status, 'delivered');
      expect(canonical.wireEnvelope, isNull);
      expect(
        canonical.media,
        isEmpty,
        reason: 'row snapshots must not retain transient local paths',
      );
      final storedAttachments = (await tester.runAsync(
        () => fixture.repo.getAttachmentsForMessage(
          forwardedMessageId,
          owner: MediaOwnerLane.direct,
        ),
      ))!;
      expect(storedAttachments, hasLength(2));

      final imageCell = find.byKey(
        const ValueKey(
          'media-grid-cell-forwarded-output-message-forwarded-output-image',
        ),
      );
      final videoCell = find.byKey(
        const ValueKey(
          'media-grid-cell-forwarded-output-message-forwarded-output-video',
        ),
      );
      final deletedImageCell = find.byKey(
        const ValueKey(
          'media-grid-cell-deleted-output-message-deleted-output-image',
        ),
      );
      final deletedVideoCell = find.byKey(
        const ValueKey(
          'media-grid-cell-deleted-output-message-deleted-output-video',
        ),
      );
      expect(imageCell, findsOneWidget);
      expect(videoCell, findsOneWidget);
      expect(deletedImageCell, findsOneWidget);
      expect(deletedVideoCell, findsOneWidget);

      for (final (index, cell) in [imageCell, videoCell].indexed) {
        await tester.ensureVisible(cell);
        await tester.tap(cell);
        await pumpUntil(
          tester,
          () => find.byType(FullScreenTypedMediaViewer).evaluate().isNotEmpty,
          reason: 'the persisted ${index == 0 ? 'image' : 'video'} must open',
        );
        final viewer = tester.widget<FullScreenTypedMediaViewer>(
          find.byType(FullScreenTypedMediaViewer),
        );
        expect(viewer.initialIndex, index);
        expect(viewer.items.map((item) => item.attachmentId), <String>[
          'forwarded-output-image',
          'forwarded-output-video',
        ]);
        expect(viewer.items.map((item) => item.localPath), <String>[
          imagePath,
          videoPath,
        ]);
        Navigator.of(
          tester.element(find.byType(FullScreenTypedMediaViewer)),
        ).pop();
        await pumpFrames(tester);
      }

      final deleteCanonical = (await tester.runAsync(
        () => fixture.messageRepo.getMessage(deletedMessageId),
      ))!;
      await tester.runAsync(() async {
        await fixture.repo.deleteAttachmentsForMessage(
          deletedMessageId,
          owner: MediaOwnerLane.direct,
        );
        await fixture.messageRepo.saveMessage(
          deleteCanonical.copyWith(
            text: '',
            deletedAt: '2026-07-10T11:02:00.000Z',
            deletedByPeerId: 'self',
            media: const <MediaAttachment>[],
          ),
        );
        await fixture.messageRepo.updateMessageStatus(
          deletedMessageId,
          'failed',
        );
      });
      await pumpUntil(
        tester,
        () =>
            visibleMessage(deletedMessageId).isDeleted &&
            visibleMessage(deletedMessageId).status == 'delivered' &&
            visibleMessage(deletedMessageId).media.isEmpty,
        reason:
            'durable delete intent and cleared media must outrank a later '
            'generic status event',
      );
      expect(visibleMessage(deletedMessageId).status, 'delivered');
      expect(deletedImageCell, findsNothing);
      expect(deletedVideoCell, findsNothing);
      expect(imageCell, findsOneWidget);
      expect(videoCell, findsOneWidget);

      await tester.runAsync(
        () => fixture.messageRepo.saveMessage(
          canonical.copyWith(
            privateMediaPolicy: const PrivateMediaPolicy.protected(),
            privateMediaState: PrivateMediaLifecycleState.consumed,
            media: const <MediaAttachment>[],
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => visibleMessage().media.isEmpty,
        reason: 'private terminal authority must clear visible media',
      );
      expect(visibleMessage().media, isEmpty);
      expect(imageCell, findsNothing);
      expect(videoCell, findsNothing);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
      final privateCanonical = (await tester.runAsync(
        () => fixture.messageRepo.getMessage(forwardedMessageId),
      ))!;
      expect(privateCanonical.media, isEmpty);
    },
  );

  testWidgets(
    'forward action launches existing picker with editable source caption',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      var tokenCounter = 0;
      String? launchedCurrentAttachmentId;
      await tester.pumpWidget(
        app(
          locale: const Locale('en'),
          navigatorKey: navigatorKey,
          onForward: (messageId, {currentAttachmentId}) async {
            launchedCurrentAttachmentId = currentAttachmentId;
            final draft = await BuildReceivedMediaForward(
              loadParentMessage: (_) async => message,
              mediaAttachmentRepository: mediaRepo,
              operationTokenFactory: () => 'operation-${++tokenCounter}',
              validateCanonicalPlaintext:
                  ({required attachment, required ownerScopeId}) async {
                    final path = attachment.localPath!;
                    return File(path).existsSync()
                        ? CanonicalGroupMediaPlaintextValidationResult.valid(
                            path,
                          )
                        : const CanonicalGroupMediaPlaintextValidationResult.invalid(
                            'missing_file',
                          );
                  },
            ).build(parent: message, currentAttachmentId: currentAttachmentId);
            final intent = draft.draft!.shareIntent;
            final caption = TextEditingController(text: intent.text);
            await navigatorKey.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => ShareTargetPickerScreen(
                  sharedText: intent.text,
                  sharedFilePaths: intent.filePaths,
                  captionController: caption,
                  contacts: const [],
                  groups: const [],
                  onToggleContact: (_) {},
                  onToggleGroup: (_) {},
                ),
              ),
            );
            caption.dispose();
            return true;
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.longPress(find.text('editable source caption'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(MessageContextOverlay.forwardActionKey));
      await pumpFrames(tester);

      expect(find.byType(ShareTargetPickerScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('share-preview-image')), findsOneWidget);
      expect(launchedCurrentAttachmentId, isNull);
      final captionField = find.byKey(const ValueKey('share-caption-field'));
      expect(
        tester.widget<TextField>(captionField).controller!.text,
        'editable source caption',
      );
      await tester.enterText(captionField, 'edited caption');
      expect(
        tester.widget<TextField>(captionField).controller!.text,
        'edited caption',
      );
      await tester.enterText(captionField, '');
      expect(tester.widget<TextField>(captionField).controller!.text, isEmpty);
      expect(message.text, 'editable source caption');
    },
  );

  testWidgets(
    'production-wired forward opens picker and delivers to a writable group',
    (tester) async {
      final identities = FakeIdentityRepository()
        ..seed(
          FakeIdentityRepository.makeIdentity(
            peerId: 'my-peer-id-12345',
            mlKemPublicKey: 'my-mlkem-public',
            mlKemSecretKey: 'my-mlkem-secret',
          ),
        );
      final contacts = InMemoryContactRepository();
      const contact = ContactModel(
        peerId: 'contact-1',
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Alice',
        signature: 'contact-signature',
        scannedAt: '2026-07-10T09:00:00.000Z',
        mlKemPublicKey: 'contact-mlkem-public-key',
      );
      await contacts.addContact(contact);
      final forwardMediaFileManager = FakeMediaFileManager();
      final canonicalSourcePath = await forwardMediaFileManager
          .localPathForAttachment(
            contactPeerId: message.contactPeerId,
            blobId: message.media.single.id,
            mime: message.media.single.mime,
          );
      const canonicalJpegBytes = <int>[
        0xff,
        0xd8,
        0xff,
        0xe0,
        0x00,
        0x10,
        0x4a,
        0x46,
        0x49,
        0x46,
        0x00,
        0x01,
        0x01,
        0x00,
      ];
      File(canonicalSourcePath).writeAsBytesSync(canonicalJpegBytes);
      final canonicalAttachment = message.media.single.copyWith(
        size: canonicalJpegBytes.length,
        localPath: canonicalSourcePath,
        contentHash: List.filled(64, 'a').join(),
        encryptionKeyBase64: 'relay-key',
        encryptionNonce: 'relay-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      final canonicalMessage = message.copyWith(media: [canonicalAttachment]);
      addTearDown(() {
        final source = File(canonicalSourcePath);
        if (source.existsSync()) source.deleteSync();
      });
      final messages = InMemoryMessageRepository();
      await messages.saveMessage(canonicalMessage);
      final attachments = InMemoryMediaAttachmentRepository();
      await attachments.saveAttachment(
        canonicalAttachment,
        owner: MediaOwnerLane.direct,
      );
      final groups = InMemoryGroupRepository();
      final groupMessages = InMemoryGroupMessageRepository();
      final group = GroupModel(
        id: 'forward-group',
        name: 'Forward Writers',
        type: GroupType.chat,
        topicName: 'topic-forward-group',
        createdAt: DateTime.parse('2026-07-10T09:00:00.000Z'),
        createdBy: 'my-peer-id-12345',
        myRole: GroupRole.admin,
      );
      await groups.saveGroup(group);
      final joinedAt = DateTime.parse('2026-07-10T09:00:00.000Z');
      await groups.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'my-peer-id-12345',
          username: 'Me',
          role: MemberRole.admin,
          publicKey: 'my-public-key',
          mlKemPublicKey: 'my-mlkem-public',
          joinedAt: joinedAt,
        ),
      );
      await groups.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-writer',
          username: 'Writer',
          role: MemberRole.writer,
          publicKey: 'writer-public-key',
          mlKemPublicKey: 'writer-mlkem-public-key',
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groups.saveKey(
        GroupKeyInfo(
          groupId: group.id,
          keyGeneration: 1,
          encryptedKey: 'forward-group-key',
          createdAt: joinedAt,
        ),
      );
      final bridge = _ProductionGroupForwardBridge();
      final p2p = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer-id-12345',
        ),
      );
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messages,
        contactRepo: contacts,
        bridge: bridge,
      );
      addTearDown(listener.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: identities,
            messageRepo: messages,
            chatMessageListener: listener,
            p2pService: p2p,
            bridge: bridge,
            contactRepo: contacts,
            mediaAttachmentRepo: attachments,
            mediaFileManager: forwardMediaFileManager,
            imageProcessor: _testImageProcessor(),
            initialMessages: [canonicalMessage],
            forwardGroupRepository: groups,
            forwardGroupMessageRepository: groupMessages,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.longPress(find.text('editable source caption'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(MessageContextOverlay.forwardActionKey));
      await pumpUntil(
        tester,
        () => find.byType(ShareTargetPickerScreen).evaluate().isNotEmpty,
        reason: 'canonical forward qualification should open the picker',
      );

      expect(find.byType(ShareTargetPickerScreen), findsOneWidget);
      expect(find.byKey(ValueKey('share-group-${group.id}')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('share-group-${group.id}')));
      await pumpFrames(tester);
      final sendGesture = tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.text('Send'),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await tester.runAsync(() async {
        sendGesture.onTap!();
        for (var i = 0; i < 80; i++) {
          if ((await groupMessages.getMessagesPage(group.id)).isNotEmpty) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      });
      await tester.pump();

      final delivered = await groupMessages.getMessagesPage(group.id);
      expect(delivered, hasLength(1));
      expect(delivered.single.text, 'editable source caption');
      expect(bridge.commandLog, contains('group:publish'));
      final groupAttachments = await attachments.getAttachmentsForMessage(
        delivered.single.id,
        owner: MediaOwnerLane.group,
      );
      expect(groupAttachments, hasLength(1));
      expect(groupAttachments.single.ownerLane, MediaOwnerLane.group);
    },
  );

  testWidgets('forward flow is localized RTL-safe and semantics-labelled', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final locale in const [Locale('de'), Locale('ar')]) {
      final localizedMessage = message.copyWith(isForwarded: true);
      await tester.pumpWidget(
        app(
          locale: locale,
          onForward: (_, {currentAttachmentId}) async => true,
          screenMessages: [localizedMessage],
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final conversationContext = tester.element(
        find.byType(ConversationScreen),
      );
      final l10n = AppLocalizations.of(conversationContext)!;
      expect(find.text(l10n.conversation_forwarded_marker), findsOneWidget);
      expect(
        Directionality.of(conversationContext),
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      await tester.longPress(find.text('editable source caption'));
      await pumpFrames(tester);
      expect(
        find.byKey(MessageContextOverlay.forwardActionKey),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(MessageContextOverlay.forwardActionKey),
          matching: find.text(l10n.media_viewer_action_forward),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.media_viewer_action_forward),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(MessageContextOverlay.backdropKey));
      await pumpFrames(tester);

      final pickerContacts = [
        const ContactModel(
          peerId: 'partial-success',
          publicKey: 'success-key',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Success',
          signature: 'success-signature',
          scannedAt: '2026-07-10T09:00:00.000Z',
        ),
        const ContactModel(
          peerId: 'partial-failure',
          publicKey: 'failure-key',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Failure',
          signature: 'failure-signature',
          scannedAt: '2026-07-10T09:00:00.000Z',
        ),
      ];
      final pickerIdentity = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity());
      final pickerContactRepo = InMemoryContactRepository();
      for (final contact in pickerContacts) {
        await pickerContactRepo.addContact(contact);
      }
      final pickerMessages = InMemoryMessageRepository();
      final pickerMedia = InMemoryMediaAttachmentRepository();
      final pickerListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: pickerMessages,
        contactRepo: pickerContactRepo,
      );
      addTearDown(pickerListener.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShareTargetPickerWired(
            shareIntent: ShareIntent(
              type: ShareIntentType.mixed,
              text: 'editable source caption',
              filePaths: [sourceFile.path],
              forwardProvenance: const ForwardProvenance(
                operationDedupKey: 'localized-operation',
              ),
            ),
            identityRepo: pickerIdentity,
            contactRepository: pickerContactRepo,
            messageRepository: pickerMessages,
            mediaAttachmentRepository: pickerMedia,
            chatMessageListener: pickerListener,
            bridge: FakeBridge(),
            p2pService: FakeP2PService(),
            mediaFileManager: FakeMediaFileManager(),
            imageProcessor: _testImageProcessor(),
            batchShareCoordinator: const _PartialForwardCoordinator(),
          ),
        ),
      );
      await pumpFrames(tester, count: 12);
      final pickerContext = tester.element(
        find.byType(ShareTargetPickerScreen),
      );
      final pickerL10n = AppLocalizations.of(pickerContext)!;
      expect(find.byKey(const ValueKey('share-caption-label')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('share-caption-label')))
            .data,
        pickerL10n.share_caption,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('share-caption-field')),
            )
            .controller!
            .text,
        'editable source caption',
      );
      await tester.tap(
        find.byKey(const ValueKey('share-contact-partial-success')),
      );
      await tester.tap(
        find.byKey(const ValueKey('share-contact-partial-failure')),
      );
      await pumpFrames(tester);
      expect(find.text(pickerL10n.share_title_count(2)), findsOneWidget);
      final localizedSendGesture = tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.text(pickerL10n.share_send),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      localizedSendGesture.onTap!();
      await pumpFrames(tester, count: 12);
      final partialSummary =
          '${pickerL10n.share_summary_sent(pickerL10n.share_target_count(1))}, '
          '${pickerL10n.share_summary_failed(pickerL10n.share_target_count(1))}.';
      final expectedSummary =
          '${partialSummary[0].toUpperCase()}${partialSummary.substring(1)}';
      expect(find.text(expectedSummary), findsOneWidget);
      expect(
        find.byKey(const ValueKey('share-inline-feedback')),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    }
    semanticsHandle.dispose();
  });
}

class _PartialForwardCoordinator implements ShareBatchDeliveryCoordinator {
  const _PartialForwardCoordinator();

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
    ShareBatchDeliveryProgressCallback? onProgress,
  }) async {
    expectSync(
      shareIntent.forwardProvenance?.operationDedupKey,
      'localized-operation',
    );
    expectSync(targets, hasLength(2));
    return ShareBatchDeliveryResult(
      results: targets
          .map(
            (target) => ShareBatchTargetResult(
              target: target,
              status: target.requireContact.peerId == 'partial-success'
                  ? ShareBatchTargetStatus.sent
                  : ShareBatchTargetStatus.failed,
              detail: target.requireContact.peerId == 'partial-success'
                  ? 'Sent.'
                  : 'Failed.',
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<ShareBatchDeliveryResult> deliverGroupMediaForward({
    required GroupMediaForwardRequest request,
    String? caption,
    required List<ShareTargetSelection> targets,
  }) {
    throw UnimplementedError(
      '1:1 received-media forwarding never dispatches a group-origin request',
    );
  }
}

ImageProcessor _testImageProcessor() => ImageProcessor(
  compressFile:
      ({
        required path,
        required quality,
        required keepExif,
        minWidth = 1920,
        minHeight = 1080,
      }) async => null,
  compressVideo: ({required path, required compress, onProgress}) async =>
      VideoProcessResult(path: path),
);

class _ProductionGroupForwardBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final command = parsed['cmd'] as String?;
    if (command != null) commandLog.add(command);
    switch (command) {
      case 'bg:begin':
        return 'forward-background-task';
      case 'bg:end':
        return '';
      case 'group.encrypt':
        final payload = parsed['payload'] as Map<String, dynamic>;
        return jsonEncode({
          'ok': true,
          'ciphertext': payload['plaintext'],
          'nonce': 'forward-group-nonce',
        });
      case 'payload.sign':
        return jsonEncode({'ok': true, 'signature': 'forward-signature'});
      case 'group:publish':
        return jsonEncode({
          'ok': true,
          'messageId': 'forward-group-message',
          'topicPeers': 1,
        });
      case 'group:inboxStore':
        return jsonEncode({'ok': true});
      default:
        return super.send(message);
    }
  }
}
