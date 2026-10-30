import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fakes/fake_media_picker.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contact_request/presentation/support/contact_request_sql_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

final _alice = TestEd25519Identity.fromSeedByte(94);
final _bob = TestEd25519Identity.fromSeedByte(95);
const _caption = 'Batch: Hafen 🌊 — مرحبا';

void main() {
  testWidgets(
    'MEDIA-008/DC-008 mixed gallery batch completes refusal and stall, then delivers ordered usable accepted images with stable IDs and caption after reopen',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Ordinary image rendering is host proof; these two event ports remain
      // empty and acknowledge subscription cleanup without native operations.
      final messenger = tester.binding.defaultBinaryMessenger;
      for (final channel in <String>[
        kPrivateMediaProtectionEventChannel,
        kPictureInPictureEventChannel,
      ]) {
        messenger.setMockMessageHandler(
          channel,
          (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
        );
        addTearDown(() => messenger.setMockMessageHandler(channel, null));
      }
      installFakeJustAudioPlatform();
      UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
      addTearDown(
        () => UploadWakeLockController.debugReset(
          driver: WakelockPlusUploadWakeLockDriver(),
        ),
      );

      // SQL, file callbacks, watchdogs and image decoding share the real zone.
      await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp('mixed-batch-');
        final previousPaths = PathProviderPlatform.instance;
        final previousCache = MediaFileManager.cachedDocumentsDir;
        PathProviderPlatform.instance = _DocumentsPath(root.path);
        MediaFileManager.cacheDocumentsDir(root.path);
        var senderDb = await MediaRepositoryRealDbFixture.create(
          databasePath: '${root.path}/alice.db',
          databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        );
        var receiverDb = await MediaRepositoryRealDbFixture.create(
          databasePath: '${root.path}/bob.db',
          databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        );
        final relay = RelayMediaStore();
        // Test XOR crypto and an in-memory relay; no native video claim.
        final senderBridge = EncryptedMediaTestBridge(relay, seedSalt: 40);
        final receiverBridge = EncryptedMediaTestBridge(relay, seedSalt: 60);
        final files = MediaFileManager();
        final senderP2p = FakeP2PService(
          initialState: NodeState(isStarted: true, peerId: _alice.peerId),
        );
        final receiverP2p = FakeP2PService();
        final stalledVideo = Completer<VideoProcessResult?>();
        final stalledEntered = Completer<void>();
        final custodyEntered = Completer<void>();
        final releaseCustody = Completer<void>();
        ChatMessageListener? senderListener;
        ChatMessageListener? receiverListener;
        try {
          final accepted =
              <({File file, List<int> bytes, int width, int height})>[];
          for (final item in [
            (name: 'first', width: 48, height: 24, red: 210),
            (name: 'last', width: 32, height: 64, red: 30),
          ]) {
            final pixels = img.Image(width: item.width, height: item.height);
            img.fill(pixels, color: img.ColorRgb8(item.red, 80, 140));
            final bytes = img.encodePng(pixels);
            final file = File('${root.path}/${item.name}.png');
            await file.writeAsBytes(bytes, flush: true);
            accepted.add((
              file: file,
              bytes: bytes,
              width: item.width,
              height: item.height,
            ));
          }
          final refused = File('${root.path}/refused.mp4');
          final stalled = File('${root.path}/stalled.mp4');
          // These are adapter inputs only and are never treated as usable media.
          await refused.writeAsBytes([1, 2, 3]);
          await stalled.writeAsBytes([4, 5, 6]);
          final picker = FakeMediaPicker()
            ..multipleMediaResult = [
              XFile(accepted.first.file.path),
              XFile(refused.path),
              XFile(stalled.path),
              XFile(accepted.last.file.path),
            ];
          final processor = ImageProcessor(
            compressFile:
                ({
                  required path,
                  required quality,
                  required keepExif,
                  minWidth = 1920,
                  minHeight = 1080,
                }) async => XFile(path),
            compressVideo:
                ({required path, required compress, onProgress}) async {
                  if (path == refused.path) return null;
                  expect(path, stalled.path);
                  stalledEntered.complete();
                  return stalledVideo.future;
                },
            cancelVideoCompression: () async {},
            videoStallTimeout: const Duration(milliseconds: 500),
          );
          final bobContact = _contact(_bob, 'Bob');
          final aliceContact = _contact(_alice, 'Alice');
          await buildWidgetContactRepository(
            senderDb.db,
          ).addContact(bobContact);
          await buildWidgetContactRepository(
            receiverDb.db,
          ).addContact(aliceContact);
          senderListener = ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: senderDb.messageRepo,
            contactRepo: buildWidgetContactRepository(senderDb.db),
          );
          String? wire;
          await tester.pumpWidget(
            _app(
              ConversationWired(
                contact: bobContact,
                identityRepo: _identity(_alice),
                messageRepo: senderDb.messageRepo,
                chatMessageListener: senderListener,
                p2pService: senderP2p,
                bridge: senderBridge,
                contactRepo: buildWidgetContactRepository(senderDb.db),
                mediaAttachmentRepo: senderDb.repo,
                mediaFileManager: files,
                imageProcessor: processor,
                mediaPicker: picker,
                micPermissionGateway: FakeMicPermissionGateway(),
                sendChatMessageFn:
                    ({
                      required p2pService,
                      required messageRepo,
                      required targetPeerId,
                      required text,
                      required senderPeerId,
                      required senderUsername,
                      messageId,
                      required preassignedMessageIdIsFresh,
                      authoredTextIntentToken,
                      timestamp,
                      bridge,
                      recipientMlKemPublicKey,
                      quotedMessageId,
                      mediaAttachments,
                      privateMediaPolicy,
                      mediaAttachmentRepo,
                      transportMetrics,
                      directEventFanout,
                    }) => sendChatMessage(
                      p2pService: p2pService,
                      messageRepo: messageRepo,
                      targetPeerId: targetPeerId,
                      text: text,
                      senderPeerId: senderPeerId,
                      senderUsername: senderUsername,
                      messageId: messageId,
                      preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
                      authoredTextIntentToken: authoredTextIntentToken,
                      timestamp: timestamp,
                      bridge: bridge,
                      recipientMlKemPublicKey: recipientMlKemPublicKey,
                      quotedMessageId: quotedMessageId,
                      mediaAttachments: mediaAttachments,
                      privateMediaPolicy: privateMediaPolicy,
                      mediaAttachmentRepo: mediaAttachmentRepo,
                      transportMetrics: transportMetrics,
                      directEventFanout: directEventFanout,
                      storeInAckCustodyInboxDetailed:
                          (
                            peer,
                            envelope, {
                            required custodyKind,
                            timeoutMs,
                          }) async {
                            wire = envelope;
                            custodyEntered.complete();
                            await releaseCustody.future;
                            return InboxStoreOutcome(
                              status: InboxStoreStatus.stored,
                              storeStatus: 'stored',
                              expiresAtMs: DateTime.now()
                                  .add(const Duration(days: 1))
                                  .millisecondsSinceEpoch,
                              custodyContract: ackOrExpiryInboxCustodyContract,
                            );
                          },
                    ),
              ),
            ),
          );
          await _until(
            tester,
            () =>
                find.byType(ConversationScreen).evaluate().isNotEmpty &&
                find.byType(TextField).evaluate().isNotEmpty,
          );
          await tester.tap(find.byIcon(Icons.add_rounded));
          await _frames(tester);
          await tester.tap(find.widgetWithText(ListTile, 'Media Library'));
          await stalledEntered.future.timeout(const Duration(seconds: 10));
          await tester.pump();
          expect(find.text('Media unavailable'), findsOneWidget);
          await _until(tester, () {
            final strips = tester.widgetList<AttachmentPreviewStrip>(
              find.byType(AttachmentPreviewStrip),
            );
            return strips.length == 1 &&
                !strips.single.isProcessing &&
                strips.single.attachments.length == 2;
          });
          final strip = tester.widget<AttachmentPreviewStrip>(
            find.byType(AttachmentPreviewStrip),
          );
          expect(
            strip.attachments.map((file) => file.path),
            accepted.map((item) => item.file.path),
          );
          expect(
            find.text('Video processing stopped. Try again.'),
            findsOneWidget,
          );
          expect(
            await senderDb.messageRepo.getMessagesForContact(_bob.peerId),
            isEmpty,
          );
          expect(await refused.readAsBytes(), [1, 2, 3]);
          expect(await stalled.readAsBytes(), [4, 5, 6]);

          await tester.enterText(find.byType(TextField), _caption);
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          await custodyEntered.future.timeout(const Duration(seconds: 20));
          await tester.pump();
          final initial = tester
              .widget<ConversationScreen>(find.byType(ConversationScreen))
              .messages
              .single;
          final logicalId = initial.id;
          final attachmentIds = initial.media.map((a) => a.id).toList();
          expect(attachmentIds.toSet(), hasLength(2));
          expect(initial.text, _caption);
          releaseCustody.complete();
          await _until(
            tester,
            () =>
                tester
                    .widget<ConversationScreen>(find.byType(ConversationScreen))
                    .messages
                    .single
                    .status !=
                'sending',
          );
          final sent = (await senderDb.messageRepo.getMessagesForContact(
            _bob.peerId,
          )).single;
          expect(sent.id, logicalId);
          expect(sent.text, _caption);
          final sentMedia = await senderDb.repo.getAttachmentsForMessage(
            logicalId,
            owner: MediaOwnerLane.direct,
          );
          expect(sentMedia.map((a) => a.id), attachmentIds);
          expect(relay.blobIds.toSet(), attachmentIds.toSet());
          for (var i = 0; i < sentMedia.length; i++) {
            expect(
              relay.uploadedBytesByBlobId[sentMedia[i].id],
              isNot(equals(accepted[i].bytes)),
            );
          }

          await tester.pumpWidget(const SizedBox.shrink());
          senderListener.dispose();
          senderListener = null;
          receiverListener = _receiver(receiverDb, receiverBridge, files);
          final completed = receiverListener.incomingMessageStream.firstWhere(
            (message) =>
                message.id == logicalId &&
                message.media.length == 2 &&
                message.media.every((a) => a.downloadStatus == 'done'),
          );
          final incoming = ChatMessage(
            from: _alice.peerId,
            to: _bob.peerId,
            content: wire!,
            timestamp: sent.timestamp,
            isIncoming: true,
            transport: 'relay',
          );
          final outcome = await receiverListener.processIncomingMessage(
            incoming,
          );
          expect(outcome.state, ChatMessageProcessState.stored);
          await completed.timeout(const Duration(seconds: 20));
          receiverListener.dispose();
          receiverListener = null;
          senderDb = await senderDb.reopen();
          receiverDb = await receiverDb.reopen();
          receiverListener = _receiver(receiverDb, receiverBridge, files);
          await receiverListener.processIncomingMessage(incoming);
          final received = (await receiverDb.messageRepo.getMessagesForContact(
            _alice.peerId,
          )).single;
          expect(received.id, logicalId);
          expect(received.text, _caption);
          final receivedMedia = await receiverDb.repo.getAttachmentsForMessage(
            logicalId,
            owner: MediaOwnerLane.direct,
          );
          expect(receivedMedia.map((a) => a.id), attachmentIds);
          expect(
            (await senderDb.messageRepo.getMessagesForContact(
              _bob.peerId,
            )).map((m) => m.id),
            [logicalId],
          );
          for (var i = 0; i < receivedMedia.length; i++) {
            final attachment = receivedMedia[i];
            expect(attachment.messageId, logicalId);
            expect(attachment.downloadStatus, 'done');
            final path = await files.resolveStoredPath(attachment.localPath!);
            final bytes = await File(path).readAsBytes();
            expect(bytes, accepted[i].bytes);
            final decoded = img.decodePng(bytes)!;
            expect(
              (decoded.width, decoded.height),
              (accepted[i].width, accepted[i].height),
            );
          }
          await tester.pumpWidget(
            _app(
              ConversationWired(
                contact: aliceContact,
                identityRepo: _identity(_bob),
                messageRepo: receiverDb.messageRepo,
                chatMessageListener: receiverListener,
                p2pService: receiverP2p,
                bridge: receiverBridge,
                contactRepo: buildWidgetContactRepository(receiverDb.db),
                mediaAttachmentRepo: receiverDb.repo,
                mediaFileManager: files,
                micPermissionGateway: FakeMicPermissionGateway(),
              ),
            ),
          );
          await _until(tester, () => find.text(_caption).evaluate().isNotEmpty);
          for (var i = 0; i < receivedMedia.length; i++) {
            final tile = find.byKey(
              ValueKey('media-grid-cell-$logicalId-${attachmentIds[i]}'),
            );
            expect(tile, findsOneWidget);
            await tester.tap(tile);
            await _until(
              tester,
              () =>
                  find.byType(FullScreenTypedMediaViewer).evaluate().isNotEmpty,
            );
            final viewer = tester.widget<FullScreenTypedMediaViewer>(
              find.byType(FullScreenTypedMediaViewer),
            );
            expect(
              viewer.items[viewer.initialIndex].attachmentId,
              attachmentIds[i],
            );
            expect(viewer.items[viewer.initialIndex].caption, _caption);
            expect(
              find.byKey(const ValueKey('media_meta_caption')),
              findsOneWidget,
            );
            expect(find.text(_caption), findsOneWidget);
            expect(
              tester
                  .widget<Text>(
                    find.byKey(const ValueKey('media_viewer_page_position')),
                  )
                  .data,
              '${i + 1} / 2',
            );
            await _until(
              tester,
              () => tester
                  .widgetList<RawImage>(find.byType(RawImage))
                  .any(
                    (image) =>
                        image.image?.width == accepted[i].width &&
                        image.image?.height == accepted[i].height,
                  ),
            );
            expect(find.text("Couldn't open this file"), findsNothing);
            await tester.pageBack();
            await _frames(tester);
          }
        } finally {
          if (!releaseCustody.isCompleted) releaseCustody.complete();
          if (!stalledVideo.isCompleted) stalledVideo.complete(null);
          await tester.pumpWidget(const SizedBox.shrink());
          senderListener?.dispose();
          receiverListener?.dispose();
          senderP2p.dispose();
          receiverP2p.dispose();
          senderBridge.dispose();
          receiverBridge.dispose();
          await senderDb.dispose();
          await receiverDb.dispose();
          PathProviderPlatform.instance = previousPaths;
          MediaFileManager.debugResetDocumentsDirCache();
          if (previousCache != null) {
            MediaFileManager.cacheDocumentsDir(previousCache);
          }
          await root.delete(recursive: true);
        }
      });
    },
  );
}

ChatMessageListener _receiver(
  MediaRepositoryRealDbFixture db,
  EncryptedMediaTestBridge bridge,
  MediaFileManager files,
) => ChatMessageListener(
  chatMessageStream: const Stream.empty(),
  messageRepo: db.messageRepo,
  contactRepo: buildWidgetContactRepository(db.db),
  bridge: bridge,
  getOwnMlKemSecretKey: () async => 'test-only-bob-secret',
  mediaAttachmentRepo: db.repo,
  mediaFileManager: files,
);

ContactModel _contact(TestEd25519Identity identity, String name) =>
    ContactModel(
      peerId: identity.peerId,
      publicKey: identity.publicKey,
      username: name,
      rendezvous: 'test-only-rendezvous',
      signature: 'test-only-signature',
      scannedAt: '2026-10-20T10:00:00.000Z',
      mlKemPublicKey: 'test-only-${identity.peerId}',
    );

FakeIdentityRepository _identity(TestEd25519Identity identity) =>
    FakeIdentityRepository()..seed(
      FakeIdentityRepository.makeIdentity(
        peerId: identity.peerId,
        publicKey: identity.publicKey,
        privateKey: identity.privateKey,
      ),
    );

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(
    ready(),
    isTrue,
    reason: 'the batch must reach its observable completed state',
  );
  await _frames(tester);
}

class _DocumentsPath extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _DocumentsPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
