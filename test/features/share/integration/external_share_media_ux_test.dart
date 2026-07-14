import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p_connection;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

class _AttachmentSaveGate {
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> allowSave = Completer<void>();

  Future<void> around(
    Map<String, Object?> _,
    Future<void> Function() persist,
  ) async {
    if (!saveStarted.isCompleted) {
      saveStarted.complete();
    }
    await allowSave.future;
    await persist();
  }
}

void main() {
  setUp(() {
    final previousFlowEventLogging = flowEventLoggingEnabled;
    flowEventLoggingEnabled = false;
    addTearDown(() => flowEventLoggingEnabled = previousFlowEventLogging);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      kPrivateMediaProtectionEventChannel,
      (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
    );
    addTearDown(
      () => messenger.setMockMessageHandler(
        kPrivateMediaProtectionEventChannel,
        null,
      ),
    );
  });

  final cases =
      <({String extension, String label, String mediaType, String mime})>[
        (
          extension: 'png',
          label: 'image',
          mediaType: 'image',
          mime: 'image/png',
        ),
        (
          extension: 'mp4',
          label: 'video',
          mediaType: 'video',
          mime: 'video/mp4',
        ),
      ];

  for (final mediaCase in cases) {
    testWidgets(
      '1:1 external ${mediaCase.label} share into an open conversation renders the media card on the first outgoing frame',
      (tester) => _runExternalShareCardCase(tester, mediaCase),
    );
  }
}

Future<void> _runExternalShareCardCase(
  WidgetTester tester,
  ({String extension, String label, String mediaType, String mime}) mediaCase,
) async {
  final tempDir = Directory.systemTemp.createTempSync(
    'external-share-${mediaCase.label}-first-frame-',
  );
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final mediaFile = File('${tempDir.path}/shared.${mediaCase.extension}')
    ..writeAsBytesSync(
      mediaCase.mediaType == 'image'
          ? _tinyPngBytes
          : const <int>[
              0x00,
              0x00,
              0x00,
              0x18,
              0x66,
              0x74,
              0x79,
              0x70,
              0x69,
              0x73,
              0x6f,
              0x6d,
            ],
    );
  if (mediaCase.mediaType == 'video') {
    final thumbnail = File('${tempDir.path}/video-thumb.png')
      ..writeAsBytesSync(_tinyPngBytes);
    debugSetVideoThumbnailGenerator((_) async => thumbnail);
    addTearDown(() => debugSetVideoThumbnailGenerator(null));
  }

  const ownPeerId = 'own-peer';
  const contactPeerId = 'contact-peer';
  final messageId = 'external-${mediaCase.label}-share-message';
  final attachmentId = 'external-${mediaCase.label}-share-attachment';
  const timestamp = '2026-07-10T12:00:00.000Z';
  final identity = IdentityModel(
    peerId: ownPeerId,
    publicKey: 'own-public-key',
    privateKey: 'own-private-key',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    username: 'Me',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  final contact = ContactModel(
    peerId: contactPeerId,
    publicKey: 'contact-public-key',
    mlKemPublicKey: 'contact-mlkem-key',
    rendezvous: '/ip4/127.0.0.1/tcp/4001',
    username: 'Friend',
    signature: 'contact-signature',
    scannedAt: timestamp,
  );
  final identityRepository = FakeIdentityRepository()..seed(identity);
  final contactRepository = InMemoryContactRepository()
    ..addTestContact(contact);
  final saveGate = _AttachmentSaveGate();
  final repositoryFixture = (await tester.runAsync(
    () => MediaRepositoryRealDbFixture.create(
      dbSaveMediaAttachmentAround: saveGate.around,
    ),
  ))!;
  addTearDown(() => tester.runAsync(repositoryFixture.dispose));
  final messageRepository = repositoryFixture.messageRepo;
  final mediaAttachmentRepository = repositoryFixture.repo;
  final p2pService = FakeP2PService(
    initialState: const NodeState(
      peerId: ownPeerId,
      isStarted: true,
      connections: [
        p2p_connection.ConnectionState(
          peerId: contactPeerId,
          multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
          direction: 'outbound',
          status: 'connected',
        ),
      ],
    ),
    storeInInboxResult: true,
  );
  final bridge = PassthroughCryptoBridge();
  final chatMessageListener = ChatMessageListener(
    chatMessageStream: const Stream.empty(),
    messageRepo: messageRepository,
    contactRepo: contactRepository,
  );

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ConversationWired(
        contact: contact,
        initialMessages: const [],
        identityRepo: identityRepository,
        messageRepo: messageRepository,
        chatMessageListener: chatMessageListener,
        p2pService: p2pService,
        bridge: bridge,
        mediaAttachmentRepo: mediaAttachmentRepository,
        mediaFileManager: FakeMediaFileManager(),
        audioRecorderService: FakeAudioRecorderService(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  final coordinator = DefaultShareBatchDeliveryCoordinator(
    identityRepository: identityRepository,
    contactRepository: contactRepository,
    messageRepository: messageRepository,
    mediaAttachmentRepository: mediaAttachmentRepository,
    groupRepository: null,
    groupMessageRepository: null,
    bridge: bridge,
    p2pService: p2pService,
    mediaFileManager: FakeMediaFileManager(),
    imageProcessor: ImageProcessor(
      compressFile:
          ({
            required path,
            required quality,
            required keepExif,
            minWidth = 1920,
            minHeight = 1080,
          }) async => null,
      compressVideo: ({required path, required compress, onProgress}) async =>
          null,
    ),
    processSharedMediaFn: (shareIntent) async => ProcessedShareMediaBatch(
      processedMedia: [
        PendingComposerMedia(
          file: mediaFile,
          budgetBytes: mediaFile.lengthSync(),
          durationMs: mediaCase.mediaType == 'video' ? 1000 : null,
        ),
      ],
    ),
    sendToContactFn:
        ({
          required identity,
          required shareIntent,
          required contact,
          required processedMedia,
          required uploadHooks,
        }) async {
          final attachment = MediaAttachment(
            id: attachmentId,
            messageId: '',
            mime: mediaCase.mime,
            size: processedMedia.single.budgetBytes,
            mediaType: mediaCase.mediaType,
            durationMs: processedMedia.single.durationMs,
            localPath: processedMedia.single.file.path,
            downloadStatus: 'done',
            createdAt: timestamp,
            contentHash:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            encryptionKeyBase64: 'external-share-key',
            encryptionNonce: 'external-share-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          );
          final (result, message) = await sendChatMessage(
            p2pService: p2pService,
            messageRepo: messageRepository,
            targetPeerId: contact.peerId,
            text: shareIntent.text ?? '',
            senderPeerId: identity.peerId,
            senderUsername: identity.username,
            messageId: messageId,
            timestamp: timestamp,
            createdAt: timestamp,
            bridge: bridge,
            recipientMlKemPublicKey: contact.mlKemPublicKey,
            mediaAttachments: [attachment],
            mediaAttachmentRepo: mediaAttachmentRepository,
          );
          return ShareBatchTargetResult(
            target: ShareTargetSelection.contact(contact),
            status: result == SendChatMessageResult.success
                ? ShareBatchTargetStatus.sent
                : ShareBatchTargetStatus.failed,
            detail: message == null ? 'Share failed.' : 'Sent.',
          );
        },
  );

  final delivery = coordinator.deliver(
    shareIntent: ShareIntent(
      type: ShareIntentType.files,
      filePaths: [mediaFile.path],
    ),
    targets: [ShareTargetSelection.contact(contact)],
  );
  ShareBatchDeliveryResult? deliveryResult;
  Object? deliveryError;
  StackTrace? deliveryStackTrace;
  var deliveryCompleted = false;
  unawaited(
    delivery.then<void>(
      (result) {
        deliveryResult = result;
        deliveryCompleted = true;
      },
      onError: (Object error, StackTrace stackTrace) {
        deliveryError = error;
        deliveryStackTrace = stackTrace;
        deliveryCompleted = true;
      },
    ),
  );
  for (var i = 0; i < 100 && !saveGate.saveStarted.isCompleted; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }

  final attachmentSaveStarted = saveGate.saveStarted.isCompleted;
  var renderedCardCountBeforeAttachmentSave = 0;
  String? renderedMediaTypeBeforeAttachmentSave;
  String? renderedMediaPathBeforeAttachmentSave;
  if (attachmentSaveStarted) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final renderedCards = find.byType(MediaThumbnailImage);
    renderedCardCountBeforeAttachmentSave = renderedCards.evaluate().length;
    if (renderedCardCountBeforeAttachmentSave == 1) {
      final renderedCard = tester.widget<MediaThumbnailImage>(renderedCards);
      renderedMediaTypeBeforeAttachmentSave = renderedCard.mediaType;
      renderedMediaPathBeforeAttachmentSave = renderedCard.mediaPath;
    }
  }

  // Always release the production DB boundary before asserting so a RED run
  // cannot strand the coordinator future or leak work into the next case.
  if (!saveGate.allowSave.isCompleted) {
    saveGate.allowSave.complete();
  }
  for (var i = 0; i < 100 && !deliveryCompleted; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 500));

  if (deliveryError != null) {
    Error.throwWithStackTrace(deliveryError!, deliveryStackTrace!);
  }
  expect(deliveryCompleted, isTrue);
  expect(deliveryResult?.sentCount, 1);

  expect(
    attachmentSaveStarted,
    isTrue,
    reason: 'the test must observe the attachment row before it is committed',
  );
  expect(
    renderedCardCountBeforeAttachmentSave,
    1,
    reason:
        'the production repository change must retain inline ${mediaCase.label} media before the separately persisted attachment row is committed',
  );
  expect(renderedMediaTypeBeforeAttachmentSave, mediaCase.mediaType);
  expect(renderedMediaPathBeforeAttachmentSave, mediaFile.path);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

final List<int> _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
