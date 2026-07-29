import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

const _contactPeerId = 'contact-1';
const _contentHash = 'canonical-ciphertext-hash';
const _encryptionKey = 'cHJpdmF0ZS1rZXk=';
const _encryptionNonce = 'bm9uY2U=';

class _OwnedConversationMediaFileManager extends MediaFileManager {
  _OwnedConversationMediaFileManager(
    this.root, {
    this.beforePlaintextCopy,
    this.failOwnedPendingDelete = false,
  });

  final Directory root;
  final Future<void> Function(String messageId, String attachmentId)?
  beforePlaintextCopy;
  final bool failOwnedPendingDelete;

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    await beforePlaintextCopy?.call(messageId, attachmentId);
    final extension = sourceFilePath.substring(sourceFilePath.lastIndexOf('.'));
    final relative = 'pending_uploads/$messageId/$attachmentId$extension';
    final target = File('${root.path}/$relative');
    target.parent.createSync(recursive: true);
    File(sourceFilePath).copySync(target.path);
    return relative;
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('media/')) {
      return '${root.path}/$storedPath';
    }
    return storedPath;
  }

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final relative = relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
    final target = File('${root.path}/$relative');
    target.parent.createSync(recursive: true);
    return target.path;
  }

  @override
  Future<String> trustedMediaRootPath() async => '${root.path}/media';

  @override
  Future<String> trustedPendingUploadRootPath() async =>
      '${root.path}/pending_uploads';

  @override
  Future<void> deletePendingUploadDir(String messageId) async {
    final pending = Directory('${root.path}/pending_uploads/$messageId');
    if (pending.existsSync()) pending.deleteSync(recursive: true);
  }

  @override
  Future<void> deleteMediaForContact(String contactPeerId) async {
    final media = Directory('${root.path}/media/$contactPeerId');
    if (media.existsSync()) media.deleteSync(recursive: true);
  }

  @override
  Future<void> deleteOwnedPendingUploadFilesForMessage({
    required String messageId,
    required Iterable<String?> storedPaths,
  }) async {
    if (failOwnedPendingDelete) {
      throw const FileSystemException('injected pending-file delete failure');
    }
    await super.deleteOwnedPendingUploadFilesForMessage(
      messageId: messageId,
      storedPaths: storedPaths,
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition() && stopwatch.elapsed < timeout) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(condition(), isTrue);
}

void main() {
  setUp(() {
    flowEventLoggingEnabled = false;
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  tearDown(() {
    flowEventLoggingEnabled = true;
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
    MediaFileManager.debugResetDocumentsDirCache();
  });

  for (final testCase
      in <
        ({
          String name,
          PrivateMediaPolicy policy,
          bool expectsPrivateCustody,
          bool requestCancellation,
          bool terminalBeforeHandoff,
        })
      >[
        (
          name: 'protected',
          policy: const PrivateMediaPolicy.protected(),
          expectsPrivateCustody: true,
          requestCancellation: false,
          terminalBeforeHandoff: false,
        ),
        (
          name: 'view-once',
          policy: const PrivateMediaPolicy.viewOnce(),
          expectsPrivateCustody: true,
          requestCancellation: false,
          terminalBeforeHandoff: false,
        ),
        // Cancellation is a non-completion mutation. Keep this refusal race on
        // the mode whose active viewer still owns an opening lease; a
        // lease-free protected viewer intentionally no longer blocks it.
        (
          name: 'view-once active-viewer cancellation race',
          policy: const PrivateMediaPolicy.viewOnce(),
          expectsPrivateCustody: true,
          requestCancellation: true,
          terminalBeforeHandoff: false,
        ),
        (
          name: 'protected FIRST-FRAME before envelope handoff',
          policy: const PrivateMediaPolicy.protected(),
          expectsPrivateCustody: true,
          requestCancellation: false,
          terminalBeforeHandoff: true,
        ),
        // 302: protected no longer terminalizes on close, so the
        // terminalize-before-handoff custody choreography needs a home on the
        // mode that still leases.
        (
          name: 'view-once FIRST-FRAME before envelope handoff',
          policy: const PrivateMediaPolicy.viewOnce(),
          expectsPrivateCustody: true,
          requestCancellation: false,
          terminalBeforeHandoff: true,
        ),
        (
          name: 'ordinary control',
          policy: const PrivateMediaPolicy.ordinary(),
          expectsPrivateCustody: false,
          requestCancellation: false,
          terminalBeforeHandoff: false,
        ),
      ]) {
    testWidgets(
      '${testCase.name} foreground upload owns transfer through durable envelope and exact pending cleanup',
      (tester) async {
        // 302: only outgoing view-once still claims the one-shot lease. A
        // protected sender open is lease-free, so it never latches the parent
        // to 'opening' and its close never terminalizes.
        final leases = testCase.policy.mode == PrivateMediaMode.viewOnce;
        final fixture = (await tester.runAsync(
          MediaRepositoryRealDbFixture.create,
        ))!;
        addTearDown(fixture.dispose);
        final root = Directory.systemTemp.createTempSync(
          'sender_finalize_canonical_',
        );
        addTearDown(() {
          if (root.existsSync()) root.deleteSync(recursive: true);
        });
        MediaFileManager.cacheDocumentsDir(root.path);
        var registryOwnedBeforePlaintextCopy = false;
        var lifecycleLockReleasedBeforePlaintextCopy = false;
        var registryOwnedDuringUpload = false;
        var staleEnvelopeClearedBeforeUpload = false;
        var registryOwnedDuringSend = false;
        var completeResultCarriedToSend = false;
        String? preparedMessageId;
        String? uploadedAttachmentId;
        final manager = _OwnedConversationMediaFileManager(
          root,
          beforePlaintextCopy: (messageId, attachmentId) async {
            preparedMessageId = messageId;
            registryOwnedBeforePlaintextCopy =
                directPrivateMediaTransferRegistry.isActive(attachmentId);
            await Zone.root.run(
              () => fixture.repo.lifecycleLock.synchronized(
                attachmentId,
                () async {
                  lifecycleLockReleasedBeforePlaintextCopy = true;
                },
              ),
            );
            await fixture.messageRepo.updateWireEnvelope(
              messageId,
              '{"stale":true}',
            );
          },
        );
        final source = File('${root.path}/picker-source.jpg')
          ..writeAsBytesSync(const <int>[0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]);
        final contact = ContactModel(
          peerId: _contactPeerId,
          publicKey: 'contact-public-key',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Alice',
          signature: 'signature',
          scannedAt: '2026-07-20T09:00:00.000Z',
        );
        final identityRepo = FakeIdentityRepository()
          ..seed(FakeIdentityRepository.makeIdentity(peerId: 'self-peer'));
        final contactRepo = FakeContactRepository()..seed([contact]);
        final listener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: fixture.messageRepo,
          contactRepo: contactRepo,
        );
        final sendCompleted = Completer<void>();
        final uploadReadReached = Completer<void>();
        final allowUploadRead = Completer<void>();
        final envelopeHandoffReached = Completer<void>();
        final sendReadyForEnvelope = Completer<void>();
        final allowEnvelopeHandoff = Completer<void>();
        final allowSendReturn = Completer<void>();
        PrivateMediaLifecycleState? envelopeHandoffParentState;
        String? envelopeHandoffAttachmentStatus;
        String? envelopeHandoffAttachmentPath;
        String? sentMessageId;
        String? pendingUploadPath;
        String? canonicalRelativePath;
        String? canonicalAbsolutePath;
        bool? deleteSourceWhenDoneValue;
        MediaFileManager? uploadMediaFileManager;
        PrivateMediaPolicy? sentPrivateMediaPolicy;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMessageHandler(
          kPrivateMediaProtectionEventChannel,
          (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
        );
        addTearDown(() {
          messenger.setMockMessageHandler(
            kPrivateMediaProtectionEventChannel,
            null,
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationWired(
              contact: contact,
              identityRepo: identityRepo,
              messageRepo: fixture.messageRepo,
              chatMessageListener: listener,
              p2pService: FakeP2PService(),
              bridge: FakeBridge(),
              contactRepo: contactRepo,
              mediaAttachmentRepo: fixture.repo,
              mediaFileManager: manager,
              micPermissionGateway: FakeMicPermissionGateway(),
              initialAttachments: [source],
              uploadMediaFn:
                  ({
                    required Bridge bridge,
                    required String localFilePath,
                    required String mime,
                    required String recipientPeerId,
                    MediaFileManager? mediaFileManager,
                    int? width,
                    int? height,
                    int? durationMs,
                    List<double>? waveform,
                    List<String>? allowedPeers,
                    String? blobId,
                    bool deleteSourceWhenDone = false,
                    EncryptedMediaArtifact? preparedArtifact,
                  }) async {
                    deleteSourceWhenDoneValue = deleteSourceWhenDone;
                    uploadMediaFileManager = mediaFileManager;
                    registryOwnedDuringUpload =
                        directPrivateMediaTransferRegistry.isActive(blobId!);
                    uploadedAttachmentId = blobId;
                    final beforeUpload = await fixture.messageRepo.getMessage(
                      preparedMessageId!,
                    );
                    staleEnvelopeClearedBeforeUpload =
                        beforeUpload?.wireEnvelope == null;
                    pendingUploadPath = localFilePath;
                    if (testCase.expectsPrivateCustody) {
                      uploadReadReached.complete();
                      await allowUploadRead.future.timeout(
                        const Duration(seconds: 10),
                      );
                    }
                    final sourceBytes = File(localFilePath).readAsBytesSync();
                    canonicalRelativePath = manager.relativePathForAttachment(
                      contactPeerId: recipientPeerId,
                      blobId: blobId,
                      mime: mime,
                    );
                    canonicalAbsolutePath = await manager
                        .localPathForAttachment(
                          contactPeerId: recipientPeerId,
                          blobId: blobId,
                          mime: mime,
                        );
                    File(canonicalAbsolutePath!).writeAsBytesSync(sourceBytes);
                    // Production uploadMedia retains the already-owned
                    // durable source for ConversationWired's canonical-copy
                    // finalizer even when ordinary cleanup is requested.
                    return UploadMediaSucceeded(
                      MediaAttachment(
                        id: blobId,
                        messageId: '',
                        mime: mime,
                        size: sourceBytes.length,
                        mediaType: MediaAttachment.mediaTypeFromMime(mime),
                        width: width,
                        height: height,
                        durationMs: durationMs,
                        waveform: waveform,
                        localPath: canonicalRelativePath,
                        downloadStatus: 'done',
                        createdAt: '2026-07-20T10:00:00.000Z',
                        contentHash: _contentHash,
                        encryptionKeyBase64: _encryptionKey,
                        encryptionNonce: _encryptionNonce,
                        encryptionScheme:
                            kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                      ),
                    );
                  },
              sendChatMessageFn:
                  ({
                    required P2PService p2pService,
                    required MessageRepository messageRepo,
                    required String targetPeerId,
                    required String text,
                    required String senderPeerId,
                    required String senderUsername,
                    String? messageId,
                    String? timestamp,
                    Bridge? bridge,
                    String? recipientMlKemPublicKey,
                    String? quotedMessageId,
                    List<MediaAttachment>? mediaAttachments,
                    PrivateMediaPolicy? privateMediaPolicy,
                    MediaAttachmentRepository? mediaAttachmentRepo,
                    TransportMetrics? transportMetrics,
                  }) async {
                    sentPrivateMediaPolicy = privateMediaPolicy;
                    sentMessageId = messageId;
                    final attachment = mediaAttachments!.single;
                    registryOwnedDuringSend = directPrivateMediaTransferRegistry
                        .isActive(attachment.id);
                    completeResultCarriedToSend =
                        attachment.localPath?.startsWith('media/') == true &&
                        attachment.downloadStatus == 'done' &&
                        attachment.contentHash == _contentHash &&
                        attachment.encryptionKeyBase64 == _encryptionKey;
                    if (testCase.terminalBeforeHandoff) {
                      sendReadyForEnvelope.complete();
                      await allowEnvelopeHandoff.future.timeout(
                        const Duration(seconds: 10),
                      );
                    }
                    if (testCase.expectsPrivateCustody) {
                      final envelopeRepository =
                          messageRepo
                              as OutgoingDirectPrivateEnvelopeCustodyRepository;
                      final envelopeResult = await envelopeRepository
                          .commitOutgoingDirectPrivateWireEnvelope(
                            messageId: messageId!,
                            completedAttachment: attachment,
                            expectedPendingLocalPath: pendingUploadPath!
                                .substring(root.path.length + 1),
                            envelope: '{"fresh":true}',
                            hasOwnedPendingCompletion: true,
                          );
                      if (!envelopeResult.authorizesTransport) {
                        throw StateError(
                          'test private wire-envelope handoff was refused',
                        );
                      }
                    } else {
                      await messageRepo.updateWireEnvelope(
                        messageId!,
                        '{"fresh":true}',
                      );
                    }
                    final durable = await messageRepo.getMessage(messageId);
                    final delivered = durable!.copyWith(
                      status: 'delivered',
                      media: mediaAttachments,
                    );
                    await messageRepo.saveMessage(delivered);
                    if (testCase.expectsPrivateCustody) {
                      final durableParent = await fixture.messageRepo
                          .loadPrivateMediaLifecycleMessage(messageId);
                      final durableAttachments = await fixture.repo
                          .getAttachmentsForMessage(
                            messageId,
                            owner: MediaOwnerLane.direct,
                          );
                      envelopeHandoffParentState =
                          durableParent?.privateMediaState;
                      envelopeHandoffAttachmentStatus =
                          durableAttachments.singleOrNull?.downloadStatus;
                      envelopeHandoffAttachmentPath =
                          durableAttachments.singleOrNull?.localPath;
                      envelopeHandoffReached.complete();
                      await allowSendReturn.future.timeout(
                        const Duration(seconds: 10),
                      );
                    }
                    sendCompleted.complete();
                    return (SendChatMessageResult.success, delivered);
                  },
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await _pumpUntil(
          tester,
          () =>
              find.byType(ConversationScreen).evaluate().isNotEmpty &&
              tester
                      .widget<ConversationScreen>(
                        find.byType(ConversationScreen),
                      )
                      .composerStateListenable
                      ?.value
                      .pendingAttachments
                      .length ==
                  1,
        );

        var screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onPrivateMediaPolicyChanged!(testCase.policy);
        await tester.pump();
        screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onSend('');

        if (testCase.expectsPrivateCustody) {
          await _pumpUntil(tester, () => uploadReadReached.isCompleted);
          expect(
            directPrivateMediaTransferRegistry.isActive(uploadedAttachmentId!),
            isTrue,
          );
          final lifecycle = DirectPrivateMediaLifecycle(
            messageRepository: fixture.messageRepo,
            mediaAttachmentRepository: fixture.repo,
            mediaFileManager: manager,
          );
          final engine = PrivateMediaLifecycleEngine(
            adapter: lifecycle,
            lifecycleLock: fixture.repo.lifecycleLock,
            nowMs: () => 5000,
          );
          final nativeEvents = StreamController<Object?>.broadcast();
          final coordinator = PrivateMediaProtectionCoordinator(
            invokeMethod: (method, arguments) async => <String, Object?>{
              'ok': true,
              'protectionActive': method == 'enter',
            },
            nativeEvents: nativeEvents.stream,
          );
          final controller = DirectPrivateMediaViewerController(
            loadCurrentRows: (identity) async {
              final parent = await fixture.messageRepo
                  .loadPrivateMediaLifecycleMessage(identity.messageId);
              final current = await fixture.repo.getAttachmentsForMessage(
                identity.messageId,
                owner: MediaOwnerLane.direct,
              );
              return DirectPrivateMediaCurrentRows(
                parent: parent,
                attachment: current
                    .where((row) => row.id == identity.attachmentId)
                    .single,
              );
            },
            lifecycleEngine: engine,
            protectionCoordinator: coordinator,
          );
          addTearDown(() async {
            await controller.dispose();
            await nativeEvents.close();
          });
          final pendingPrepared = await tester.runAsync(
            () => controller
                .prepareResult(
                  DirectPrivateMediaViewerIdentity(
                    messageId: preparedMessageId!,
                    attachmentId: uploadedAttachmentId!,
                  ),
                  const DirectPrivateMediaAlwaysValidContinuityGuard(),
                )
                .timeout(const Duration(seconds: 5)),
          );
          expect(pendingPrepared!.isGranted, isTrue);
          expect(pendingPrepared.grant!.localPath, pendingUploadPath);
          if (testCase.requestCancellation) {
            await _pumpUntil(
              tester,
              () => find
                  .byKey(const ValueKey('upload-progress-cancel-button'))
                  .evaluate()
                  .isNotEmpty,
            );
            await tester.tap(
              find.byKey(const ValueKey('upload-progress-cancel-button')),
            );
            await tester.pump();
          }

          allowUploadRead.complete();
          if (testCase.terminalBeforeHandoff) {
            await _pumpUntil(tester, () => sendReadyForEnvelope.isCompleted);
            expect(
              await tester.runAsync(
                () => controller.markFirstFrame(pendingPrepared.grant!),
              ),
              isTrue,
            );
            final terminalSettlement = await tester.runAsync(
              () => controller
                  .settle(
                    pendingPrepared.grant!,
                    DirectPrivateMediaExitReason.close,
                  )
                  .timeout(const Duration(seconds: 5)),
            );
            expect(
              terminalSettlement?.disposition,
              leases
                  ? DirectPrivateMediaSettleDisposition.terminalized
                  : DirectPrivateMediaSettleDisposition.noLease,
            );
            expect(
              (await tester.runAsync(
                () => fixture.messageRepo.loadPrivateMediaLifecycleMessage(
                  preparedMessageId!,
                ),
              ))?.privateMediaState,
              leases
                  ? PrivateMediaLifecycleState.consumed
                  : PrivateMediaLifecycleState.available,
            );
            final preHandoffRows = (await tester.runAsync(
              () => fixture.repo.getAttachmentsForMessage(
                preparedMessageId!,
                owner: MediaOwnerLane.direct,
              ),
            ))!;
            expect(
              (
                preHandoffRows.single.downloadStatus,
                preHandoffRows.single.localPath,
              ),
              (
                leases ? 'upload_pending' : 'done',
                leases
                    ? pendingUploadPath!.substring(root.path.length + 1)
                    : canonicalRelativePath,
              ),
            );
            expect(File(pendingUploadPath!).existsSync(), isTrue);
            allowEnvelopeHandoff.complete();
          }
          await _pumpUntil(tester, () => envelopeHandoffReached.isCompleted);
          expect(
            directPrivateMediaTransferRegistry.isActive(uploadedAttachmentId!),
            isTrue,
          );
          if (!testCase.terminalBeforeHandoff) {
            await tester.runAsync(
              () => controller
                  .settle(
                    pendingPrepared.grant!,
                    DirectPrivateMediaExitReason.preFrameDecodeFailure,
                  )
                  .timeout(const Duration(seconds: 5)),
            );
          }
          allowSendReturn.complete();
        }
        await _pumpUntil(tester, () => sendCompleted.isCompleted);
        await _pumpUntil(
          tester,
          () =>
              uploadedAttachmentId != null &&
              pendingUploadPath != null &&
              !directPrivateMediaTransferRegistry.isActive(
                uploadedAttachmentId!,
              ) &&
              !File(pendingUploadPath!).existsSync(),
        );
        final postReleaseLockBarrier = Completer<void>();
        await tester.runAsync(() async {
          unawaited(
            Zone.root
                .run(
                  () => fixture.repo.lifecycleLock.synchronized(
                    uploadedAttachmentId!,
                    () async {},
                  ),
                )
                .then((_) => postReleaseLockBarrier.complete()),
          );
        });
        await _pumpUntil(
          tester,
          () => postReleaseLockBarrier.isCompleted,
          timeout: const Duration(seconds: 30),
        );

        final rows = (await tester.runAsync(
          () => fixture.repo.getAttachmentsForMessage(
            sentMessageId!,
            owner: MediaOwnerLane.direct,
          ),
        ))!;
        final terminalized = testCase.terminalBeforeHandoff && leases;
        expect(rows, terminalized ? isEmpty : hasLength(1));
        expect(sentPrivateMediaPolicy, testCase.policy);
        expect(
          registryOwnedBeforePlaintextCopy,
          testCase.expectsPrivateCustody,
        );
        expect(lifecycleLockReleasedBeforePlaintextCopy, isTrue);
        expect(registryOwnedDuringUpload, testCase.expectsPrivateCustody);
        expect(
          staleEnvelopeClearedBeforeUpload,
          testCase.expectsPrivateCustody,
        );
        expect(registryOwnedDuringSend, testCase.expectsPrivateCustody);
        if (testCase.expectsPrivateCustody) {
          expect(
            (
              envelopeHandoffParentState,
              envelopeHandoffAttachmentStatus,
              envelopeHandoffAttachmentPath,
            ),
            (
              leases
                  ? (testCase.terminalBeforeHandoff
                        ? PrivateMediaLifecycleState.consumed
                        : PrivateMediaLifecycleState.opening)
                  : PrivateMediaLifecycleState.available,
              leases ? 'upload_pending' : 'done',
              leases
                  ? pendingUploadPath!.substring(root.path.length + 1)
                  : canonicalRelativePath,
            ),
          );
        }
        expect(completeResultCarriedToSend, isTrue);
        if (testCase.requestCancellation) {
          expect(find.text('Upload cancelled.'), findsNothing);
        }
        expect(deleteSourceWhenDoneValue, !testCase.expectsPrivateCustody);
        expect(uploadMediaFileManager, same(manager));
        expect(File(pendingUploadPath!).existsSync(), isFalse);
        if (terminalized) {
          expect(File(canonicalAbsolutePath!).existsSync(), isFalse);
        } else {
          final persisted = rows.single;
          expect(persisted.localPath, canonicalRelativePath);
          expect(persisted.localPath, startsWith('media/$_contactPeerId/'));
          expect(persisted.downloadStatus, 'done');
          expect(File(canonicalAbsolutePath!).existsSync(), isTrue);
          expect(persisted.contentHash, _contentHash);
          expect(persisted.encryptionKeyBase64, _encryptionKey);
          expect(persisted.encryptionNonce, _encryptionNonce);
          expect(
            persisted.encryptionScheme,
            kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          );
        }
        expect(
          (await tester.runAsync(
            () => fixture.messageRepo.getMessage(sentMessageId!),
          ))?.wireEnvelope,
          '{"fresh":true}',
        );
      },
    );
  }

  testWidgets(
    'protected batch-preparation refusal exact-cleans copied plaintext and never uploads',
    (tester) async {
      final fixture = (await tester.runAsync(
        MediaRepositoryRealDbFixture.create,
      ))!;
      addTearDown(fixture.dispose);
      final root = Directory.systemTemp.createTempSync(
        'sender_prepare_refusal_',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      MediaFileManager.cacheDocumentsDir(root.path);
      String? copiedMessageId;
      String? copiedAttachmentId;
      final manager = _OwnedConversationMediaFileManager(
        root,
        beforePlaintextCopy: (messageId, attachmentId) async {
          copiedMessageId = messageId;
          copiedAttachmentId = attachmentId;
          final updated = await fixture.db.update(
            'messages',
            <String, Object?>{
              'private_media_state':
                  PrivateMediaLifecycleState.consumed.wireValue,
              'private_media_terminal_at_ms': 9000,
            },
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          );
          if (updated != 1) {
            throw StateError('test could not terminalize optimistic parent');
          }
        },
      );
      final source = File('${root.path}/picker-source.jpg')
        ..writeAsBytesSync(const <int>[0xff, 0xd8, 0xff, 0xe0, 5, 4, 3, 2]);
      final contact = ContactModel(
        peerId: _contactPeerId,
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Alice',
        signature: 'signature',
        scannedAt: '2026-07-20T09:00:00.000Z',
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity(peerId: 'self-peer'));
      final contactRepo = FakeContactRepository()..seed([contact]);
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: fixture.messageRepo,
        contactRepo: contactRepo,
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler(
        kPrivateMediaProtectionEventChannel,
        (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
      );
      addTearDown(() {
        messenger.setMockMessageHandler(
          kPrivateMediaProtectionEventChannel,
          null,
        );
      });
      var uploadInvoked = false;
      var sendInvoked = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: identityRepo,
            messageRepo: fixture.messageRepo,
            chatMessageListener: listener,
            p2pService: FakeP2PService(),
            bridge: FakeBridge(),
            contactRepo: contactRepo,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: manager,
            micPermissionGateway: FakeMicPermissionGateway(),
            initialAttachments: [source],
            uploadMediaFn:
                ({
                  required Bridge bridge,
                  required String localFilePath,
                  required String mime,
                  required String recipientPeerId,
                  MediaFileManager? mediaFileManager,
                  int? width,
                  int? height,
                  int? durationMs,
                  List<double>? waveform,
                  List<String>? allowedPeers,
                  String? blobId,
                  bool deleteSourceWhenDone = false,
                  EncryptedMediaArtifact? preparedArtifact,
                }) async {
                  uploadInvoked = true;
                  throw StateError('upload must not run after prep refusal');
                },
            sendChatMessageFn:
                ({
                  required P2PService p2pService,
                  required MessageRepository messageRepo,
                  required String targetPeerId,
                  required String text,
                  required String senderPeerId,
                  required String senderUsername,
                  String? messageId,
                  String? timestamp,
                  Bridge? bridge,
                  String? recipientMlKemPublicKey,
                  String? quotedMessageId,
                  List<MediaAttachment>? mediaAttachments,
                  PrivateMediaPolicy? privateMediaPolicy,
                  MediaAttachmentRepository? mediaAttachmentRepo,
                  TransportMetrics? transportMetrics,
                }) async {
                  sendInvoked = true;
                  return (SendChatMessageResult.success, null);
                },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpUntil(
        tester,
        () =>
            find.byType(ConversationScreen).evaluate().isNotEmpty &&
            tester
                    .widget<ConversationScreen>(find.byType(ConversationScreen))
                    .composerStateListenable
                    ?.value
                    .pendingAttachments
                    .length ==
                1,
      );

      var screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onPrivateMediaPolicyChanged!(const PrivateMediaPolicy.protected());
      await tester.pump();
      screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onSend('');

      await _pumpUntil(tester, () {
        final messageId = copiedMessageId;
        final attachmentId = copiedAttachmentId;
        if (messageId == null || attachmentId == null) return false;
        final relativePath =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: 'image/jpeg',
            );
        return !directPrivateMediaTransferRegistry.isActive(attachmentId) &&
            !File('${root.path}/$relativePath').existsSync();
      }, timeout: const Duration(seconds: 30));
      await tester.runAsync(
        () => fixture.repo.lifecycleLock.synchronizedAll(() async {}),
      );

      final messageId = copiedMessageId!;
      final attachmentId = copiedAttachmentId!;
      final pendingRelativePath =
          MediaFilePathConvention.relativePathForPendingUpload(
            messageId: messageId,
            attachmentId: attachmentId,
            mime: 'image/jpeg',
          );
      final durableRows = (await tester.runAsync(
        () => fixture.repo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        ),
      ))!;
      expect(uploadInvoked, isFalse);
      expect(sendInvoked, isFalse);
      expect(durableRows, isEmpty);
      expect(File('${root.path}/$pendingRelativePath').existsSync(), isFalse);
      expect(
        directPrivateMediaTransferRegistry.isActive(attachmentId),
        isFalse,
      );
      screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      expect(
        screen.composerStateListenable?.value.pendingAttachments,
        hasLength(1),
      );
    },
  );

  testWidgets(
    'protected optimistic parent-save failure aborts before transfer claim or plaintext copy',
    (tester) async {
      final fixture = (await tester.runAsync(
        MediaRepositoryRealDbFixture.create,
      ))!;
      addTearDown(fixture.dispose);
      await tester.runAsync(
        () => fixture.db.execute('''
          CREATE TRIGGER reject_private_optimistic_parent
          BEFORE INSERT ON messages
          WHEN NEW.private_media_policy_version = 1
            AND NEW.private_media_mode IN ('protected', 'view_once')
          BEGIN
            SELECT RAISE(ABORT, 'injected private parent save failure');
          END
        '''),
      );
      final root = Directory.systemTemp.createTempSync(
        'sender_parent_save_refusal_',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      MediaFileManager.cacheDocumentsDir(root.path);
      var plaintextCopyInvoked = false;
      final manager = _OwnedConversationMediaFileManager(
        root,
        beforePlaintextCopy: (_, _) async {
          plaintextCopyInvoked = true;
        },
      );
      final source = File('${root.path}/picker-source.jpg')
        ..writeAsBytesSync(const <int>[0xff, 0xd8, 0xff, 0xe0, 6, 5, 4, 3]);
      final contact = ContactModel(
        peerId: _contactPeerId,
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Alice',
        signature: 'signature',
        scannedAt: '2026-07-20T09:00:00.000Z',
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity(peerId: 'self-peer'));
      final contactRepo = FakeContactRepository()..seed([contact]);
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: fixture.messageRepo,
        contactRepo: contactRepo,
      );
      final protectionMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      protectionMessenger.setMockMessageHandler(
        kPrivateMediaProtectionEventChannel,
        (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
      );
      addTearDown(() {
        protectionMessenger.setMockMessageHandler(
          kPrivateMediaProtectionEventChannel,
          null,
        );
      });
      var uploadInvoked = false;
      var sendInvoked = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: identityRepo,
            messageRepo: fixture.messageRepo,
            chatMessageListener: listener,
            p2pService: FakeP2PService(),
            bridge: FakeBridge(),
            contactRepo: contactRepo,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: manager,
            micPermissionGateway: FakeMicPermissionGateway(),
            initialAttachments: [source],
            uploadMediaFn:
                ({
                  required Bridge bridge,
                  required String localFilePath,
                  required String mime,
                  required String recipientPeerId,
                  MediaFileManager? mediaFileManager,
                  int? width,
                  int? height,
                  int? durationMs,
                  List<double>? waveform,
                  List<String>? allowedPeers,
                  String? blobId,
                  bool deleteSourceWhenDone = false,
                  EncryptedMediaArtifact? preparedArtifact,
                }) async {
                  uploadInvoked = true;
                  throw StateError('upload must not run after parent failure');
                },
            sendChatMessageFn:
                ({
                  required P2PService p2pService,
                  required MessageRepository messageRepo,
                  required String targetPeerId,
                  required String text,
                  required String senderPeerId,
                  required String senderUsername,
                  String? messageId,
                  String? timestamp,
                  Bridge? bridge,
                  String? recipientMlKemPublicKey,
                  String? quotedMessageId,
                  List<MediaAttachment>? mediaAttachments,
                  PrivateMediaPolicy? privateMediaPolicy,
                  MediaAttachmentRepository? mediaAttachmentRepo,
                  TransportMetrics? transportMetrics,
                }) async {
                  sendInvoked = true;
                  return (SendChatMessageResult.success, null);
                },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpUntil(
        tester,
        () =>
            find.byType(ConversationScreen).evaluate().isNotEmpty &&
            tester
                    .widget<ConversationScreen>(find.byType(ConversationScreen))
                    .composerStateListenable
                    ?.value
                    .pendingAttachments
                    .length ==
                1,
      );

      var screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onPrivateMediaPolicyChanged!(const PrivateMediaPolicy.protected());
      await tester.pump();
      screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onSend('');
      await _pumpUntil(
        tester,
        () =>
            find
                .text('Failed to prepare private media. Try again.')
                .evaluate()
                .isNotEmpty &&
            tester
                    .widget<ConversationScreen>(find.byType(ConversationScreen))
                    .composerStateListenable
                    ?.value
                    .pendingAttachments
                    .length ==
                1,
      );

      screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      final optimisticMessageId = screen.messages.single.id;
      final durableRows = (await tester.runAsync(
        () => fixture.repo.getAttachmentsForMessage(
          optimisticMessageId,
          owner: MediaOwnerLane.direct,
        ),
      ))!;
      expect(plaintextCopyInvoked, isFalse);
      expect(uploadInvoked, isFalse);
      expect(sendInvoked, isFalse);
      expect(durableRows, isEmpty);
      expect(
        directPrivateMediaTransferRegistry.isActiveForMessage(
          optimisticMessageId,
        ),
        isFalse,
      );
      expect(Directory('${root.path}/pending_uploads').existsSync(), isFalse);
      expect(
        await tester.runAsync(
          () => fixture.messageRepo.getMessage(optimisticMessageId),
        ),
        isNull,
      );
    },
  );

  testWidgets(
    'contact deletion wins before first private parent publication without resurrection',
    (tester) async {
      final lifecycleLock = MediaAttachmentLifecycleLock();
      final fixture = (await tester.runAsync(
        () => MediaRepositoryRealDbFixture.create(lifecycleLock: lifecycleLock),
      ))!;
      addTearDown(fixture.dispose);
      final root = Directory.systemTemp.createTempSync(
        'sender_contact_delete_parent_race_',
      );
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      MediaFileManager.cacheDocumentsDir(root.path);
      var plaintextCopyInvoked = false;
      final manager = _OwnedConversationMediaFileManager(
        root,
        beforePlaintextCopy: (_, _) async {
          plaintextCopyInvoked = true;
        },
      );
      final source = File('${root.path}/picker-source.jpg')
        ..writeAsBytesSync(const <int>[0xff, 0xd8, 0xff, 0xe0, 7, 6, 5, 4]);
      final contact = ContactModel(
        peerId: _contactPeerId,
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Alice',
        signature: 'signature',
        scannedAt: '2026-07-20T09:00:00.000Z',
      );
      final identityRepo = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity(peerId: 'self-peer'));
      final contactRepo = FakeContactRepository()..seed([contact]);
      final deletionLockEntered = Completer<void>();
      final allowContactRemoval = Completer<void>();
      final contactRemoved = Completer<void>();
      final releaseDeletionAuthority = Completer<void>();
      Future<void>? deletionAuthority;
      addTearDown(() {
        if (!allowContactRemoval.isCompleted) {
          allowContactRemoval.complete();
        }
        if (!releaseDeletionAuthority.isCompleted) {
          releaseDeletionAuthority.complete();
        }
      });
      await tester.runAsync(() async {
        deletionAuthority = Zone.root.run(
          () => fixture.repo.lifecycleLock.synchronizedAll(() async {
            deletionLockEntered.complete();
            await allowContactRemoval.future;
            await contactRepo.deleteContact(_contactPeerId);
            contactRemoved.complete();
            await releaseDeletionAuthority.future;
          }),
        );
      });
      await _pumpUntil(tester, () => deletionLockEntered.isCompleted);
      final protectionMessenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      protectionMessenger.setMockMessageHandler(
        kPrivateMediaProtectionEventChannel,
        (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
      );
      addTearDown(() {
        protectionMessenger.setMockMessageHandler(
          kPrivateMediaProtectionEventChannel,
          null,
        );
      });
      final listener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: fixture.messageRepo,
        contactRepo: contactRepo,
      );
      var uploadInvoked = false;
      var sendInvoked = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: identityRepo,
            messageRepo: fixture.messageRepo,
            chatMessageListener: listener,
            p2pService: FakeP2PService(),
            bridge: FakeBridge(),
            contactRepo: contactRepo,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: manager,
            micPermissionGateway: FakeMicPermissionGateway(),
            initialAttachments: [source],
            uploadMediaFn:
                ({
                  required Bridge bridge,
                  required String localFilePath,
                  required String mime,
                  required String recipientPeerId,
                  MediaFileManager? mediaFileManager,
                  int? width,
                  int? height,
                  int? durationMs,
                  List<double>? waveform,
                  List<String>? allowedPeers,
                  String? blobId,
                  bool deleteSourceWhenDone = false,
                  EncryptedMediaArtifact? preparedArtifact,
                }) async {
                  uploadInvoked = true;
                  throw StateError(
                    'upload must not run after contact deletion wins',
                  );
                },
            sendChatMessageFn:
                ({
                  required P2PService p2pService,
                  required MessageRepository messageRepo,
                  required String targetPeerId,
                  required String text,
                  required String senderPeerId,
                  required String senderUsername,
                  String? messageId,
                  String? timestamp,
                  Bridge? bridge,
                  String? recipientMlKemPublicKey,
                  String? quotedMessageId,
                  List<MediaAttachment>? mediaAttachments,
                  PrivateMediaPolicy? privateMediaPolicy,
                  MediaAttachmentRepository? mediaAttachmentRepo,
                  TransportMetrics? transportMetrics,
                }) async {
                  sendInvoked = true;
                  return (SendChatMessageResult.success, null);
                },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await _pumpUntil(
        tester,
        () =>
            find.byType(ConversationScreen).evaluate().isNotEmpty &&
            tester
                    .widget<ConversationScreen>(find.byType(ConversationScreen))
                    .composerStateListenable
                    ?.value
                    .pendingAttachments
                    .length ==
                1,
      );
      var screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onPrivateMediaPolicyChanged!(const PrivateMediaPolicy.protected());
      await tester.pump();
      allowContactRemoval.complete();
      await _pumpUntil(tester, () => contactRemoved.isCompleted);
      screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onSend('');
      await _pumpUntil(
        tester,
        () =>
            tester
                .widget<ConversationScreen>(find.byType(ConversationScreen))
                .messages
                .length ==
            1,
      );
      screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      final optimisticMessage = screen.messages.single;
      final optimisticAttachment = optimisticMessage.media.single;

      expect(plaintextCopyInvoked, isFalse);
      expect(uploadInvoked, isFalse);
      expect(sendInvoked, isFalse);
      expect(
        await tester.runAsync(
          () => fixture.messageRepo.getMessage(optimisticMessage.id),
        ),
        isNull,
      );
      expect(
        directPrivateMediaTransferRegistry.isActive(optimisticAttachment.id),
        isFalse,
      );

      final deletionAuthoritySettled = Completer<void>();
      await tester.runAsync(() async {
        releaseDeletionAuthority.complete();
        unawaited(
          deletionAuthority!.then((_) => deletionAuthoritySettled.complete()),
        );
      });
      await _pumpUntil(tester, () => deletionAuthoritySettled.isCompleted);
      await _pumpUntil(
        tester,
        () =>
            find
                .text('Failed to prepare private media. Try again.')
                .evaluate()
                .isNotEmpty &&
            tester
                    .widget<ConversationScreen>(find.byType(ConversationScreen))
                    .composerStateListenable
                    ?.value
                    .pendingAttachments
                    .length ==
                1 &&
            !mediaUploadInFlightTracker.isInFlight(optimisticAttachment.id),
      );

      expect(await contactRepo.contactExists(_contactPeerId), isFalse);
      expect(
        await tester.runAsync(
          () => fixture.messageRepo.getMessage(optimisticMessage.id),
        ),
        isNull,
      );
      expect(
        await tester.runAsync(
          () => fixture.repo.getAttachmentsForMessage(
            optimisticMessage.id,
            owner: MediaOwnerLane.direct,
          ),
        ),
        isEmpty,
      );
      expect(source.existsSync(), isTrue);
      expect(Directory('${root.path}/pending_uploads').existsSync(), isFalse);
      expect(plaintextCopyInvoked, isFalse);
      expect(uploadInvoked, isFalse);
      expect(sendInvoked, isFalse);
      expect(
        directPrivateMediaTransferRegistry.isActive(optimisticAttachment.id),
        isFalse,
      );
    },
  );

  for (final deleteCase
      in <
        ({
          String name,
          PrivateMediaPolicy policy,
          bool activeViewer,
          bool activeTransfer,
          bool fileDeleteFails,
          bool reinsertRace,
          bool expectsDeletion,
        })
      >[
        // 302 (AD-4): the delete refusal is keyed on the 'opening'/'viewing'
        // lease states. A protected sender open no longer produces either, so
        // deleting one's own failed protected message now PROCEEDS. View-once
        // still leases, so its refusal is retained below — that case is what
        // keeps the whole refusal behavior class under test.
        (
          name: 'active protected viewer',
          policy: const PrivateMediaPolicy.protected(),
          activeViewer: true,
          activeTransfer: false,
          fileDeleteFails: false,
          reinsertRace: false,
          expectsDeletion: true,
        ),
        (
          name: 'active view-once viewer',
          policy: const PrivateMediaPolicy.viewOnce(),
          activeViewer: true,
          activeTransfer: false,
          fileDeleteFails: false,
          reinsertRace: false,
          expectsDeletion: false,
        ),
        (
          name: 'active protected upload custody',
          policy: const PrivateMediaPolicy.protected(),
          activeViewer: false,
          activeTransfer: true,
          fileDeleteFails: false,
          reinsertRace: false,
          expectsDeletion: false,
        ),
        (
          name: 'available protected file-delete failure',
          policy: const PrivateMediaPolicy.protected(),
          activeViewer: false,
          activeTransfer: false,
          fileDeleteFails: true,
          reinsertRace: false,
          expectsDeletion: false,
        ),
        (
          name: 'available protected failed-media intent',
          policy: const PrivateMediaPolicy.protected(),
          activeViewer: false,
          activeTransfer: false,
          fileDeleteFails: false,
          reinsertRace: true,
          expectsDeletion: true,
        ),
      ]) {
    testWidgets(
      'failed-media delete ${deleteCase.name} has truthful row/file/parent/key effects',
      (tester) async {
        final fixture = (await tester.runAsync(
          MediaRepositoryRealDbFixture.create,
        ))!;
        addTearDown(fixture.dispose);
        final root = Directory.systemTemp.createTempSync(
          'sender_failed_delete_guard_',
        );
        addTearDown(() {
          if (root.existsSync()) root.deleteSync(recursive: true);
        });
        MediaFileManager.cacheDocumentsDir(root.path);
        final manager = _OwnedConversationMediaFileManager(
          root,
          failOwnedPendingDelete: deleteCase.fileDeleteFails,
        );
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMessageHandler(
          kPrivateMediaProtectionEventChannel,
          (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
        );
        addTearDown(() {
          messenger.setMockMessageHandler(
            kPrivateMediaProtectionEventChannel,
            null,
          );
        });
        const messageId = 'protected-failed-delete-message';
        const attachmentId = 'protected-failed-delete-attachment';
        const mime = 'image/jpeg';
        final pendingRelativePath =
            MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: mime,
            );
        final pendingFile = File('${root.path}/$pendingRelativePath')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(const <int>[0xff, 0xd8, 0xff, 0xe0, 9, 8, 7, 6]);
        final contact = ContactModel(
          peerId: _contactPeerId,
          publicKey: 'contact-public-key',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Alice',
          signature: 'signature',
          scannedAt: '2026-07-20T09:00:00.000Z',
        );
        final failedMessage = ConversationMessage(
          id: messageId,
          contactPeerId: _contactPeerId,
          senderPeerId: 'self-peer',
          text: '',
          timestamp: '2026-07-20T10:00:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-07-20T10:00:00.000Z',
          wireEnvelope: '{"stale":true}',
          privateMediaPolicy: deleteCase.policy,
          privateMediaState: PrivateMediaLifecycleState.available,
        );
        final pendingAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: mime,
          size: pendingFile.lengthSync(),
          mediaType: 'image',
          localPath: pendingRelativePath,
          downloadStatus: 'upload_pending',
          createdAt: '2026-07-20T10:00:00.000Z',
        );
        final secureKeyName = mediaAttachmentEncryptionKeyStoreName(
          attachmentId,
        );
        await tester.runAsync(() async {
          await fixture.messageRepo.saveMessage(failedMessage);
          await fixture.repo.saveAttachment(
            pendingAttachment,
            owner: MediaOwnerLane.direct,
          );
          // Model an interrupted legacy writer that left key custody beside an
          // otherwise exact pending row. The delete path must preserve or
          // remove both halves together.
          await fixture.secureKeyStore.write(secureKeyName, _encryptionKey);
          await fixture.db.update(
            'media_attachments',
            <String, Object?>{
              'encryption_key_base64': secureStoreReferenceForKey(
                secureKeyName,
              ),
            },
            where: 'id = ?',
            whereArgs: <Object?>[attachmentId],
          );
        });
        expect(
          await tester.runAsync(
            () => fixture.secureKeyStore.containsKey(secureKeyName),
          ),
          isTrue,
        );

        final identityRepo = FakeIdentityRepository()
          ..seed(FakeIdentityRepository.makeIdentity(peerId: 'self-peer'));
        final contactRepo = FakeContactRepository()..seed([contact]);
        final listener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: fixture.messageRepo,
          contactRepo: contactRepo,
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ConversationWired(
              contact: contact,
              identityRepo: identityRepo,
              messageRepo: fixture.messageRepo,
              chatMessageListener: listener,
              p2pService: FakeP2PService(),
              contactRepo: contactRepo,
              mediaAttachmentRepo: fixture.repo,
              mediaFileManager: manager,
              micPermissionGateway: FakeMicPermissionGateway(),
            ),
          ),
        );
        await _pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('failed-media-delete-$messageId'))
              .evaluate()
              .isNotEmpty,
        );

        DirectPrivateMediaViewerController? viewerController;
        StreamController<Object?>? nativeEvents;
        DirectPrivateMediaViewerGrant? viewerGrant;
        Object? transferToken;
        Future<OutgoingDirectPrivatePendingPreparationOutcome>? reinsertAttempt;
        StreamSubscription<MediaAttachmentAuthorizationChange>?
        authorizationSubscription;
        if (deleteCase.activeViewer) {
          final lifecycle = DirectPrivateMediaLifecycle(
            messageRepository: fixture.messageRepo,
            mediaAttachmentRepository: fixture.repo,
            mediaFileManager: manager,
          );
          final engine = PrivateMediaLifecycleEngine(
            adapter: lifecycle,
            lifecycleLock: fixture.repo.lifecycleLock,
            nowMs: () => 5000,
          );
          nativeEvents = StreamController<Object?>.broadcast();
          final protectionCoordinator = PrivateMediaProtectionCoordinator(
            invokeMethod: (method, arguments) async => <String, Object?>{
              'ok': true,
              'protectionActive': method == 'enter',
            },
            nativeEvents: nativeEvents.stream,
          );
          viewerController = DirectPrivateMediaViewerController(
            loadCurrentRows: (identity) async {
              final parent = await fixture.messageRepo
                  .loadPrivateMediaLifecycleMessage(identity.messageId);
              final attachments = await fixture.repo.getAttachmentsForMessage(
                identity.messageId,
                owner: MediaOwnerLane.direct,
              );
              return DirectPrivateMediaCurrentRows(
                parent: parent,
                attachment: attachments
                    .where((row) => row.id == identity.attachmentId)
                    .single,
              );
            },
            lifecycleEngine: engine,
            protectionCoordinator: protectionCoordinator,
          );
          final prepared = await tester.runAsync(
            () => viewerController!
                .prepareResult(
                  const DirectPrivateMediaViewerIdentity(
                    messageId: messageId,
                    attachmentId: attachmentId,
                  ),
                  const DirectPrivateMediaAlwaysValidContinuityGuard(),
                )
                .timeout(const Duration(seconds: 5)),
          );
          expect(prepared!.isGranted, isTrue);
          viewerGrant = prepared.grant;
          expect(
            (await tester.runAsync(
              () => fixture.messageRepo.loadPrivateMediaLifecycleMessage(
                messageId,
              ),
            ))?.privateMediaState,
            deleteCase.policy.mode == PrivateMediaMode.viewOnce
                ? PrivateMediaLifecycleState.opening
                : PrivateMediaLifecycleState.available,
            reason:
                'the active-viewer delete gate must distinguish a retained '
                'view-once lease from a lease-free protected grant',
          );
        }
        if (deleteCase.activeTransfer) {
          transferToken = await tester.runAsync(
            () => fixture.repo.lifecycleLock.synchronized<Object>(
              attachmentId,
              () async {
                final token = directPrivateMediaTransferRegistry.tryBegin(
                  attachmentId,
                  messageId: messageId,
                );
                if (token == null) {
                  throw StateError('test transfer registry claim refused');
                }
                return token;
              },
            ),
          );
          expect(transferToken, isNotNull);
        }
        if (deleteCase.reinsertRace) {
          authorizationSubscription = fixture.repo.authorizationChanges.listen((
            change,
          ) {
            if (change.kind != MediaAttachmentAuthorizationMutation.removed ||
                change.messageId != messageId ||
                change.attachmentId != attachmentId ||
                reinsertAttempt != null) {
              return;
            }
            // The event is emitted synchronously after the row delete while
            // the repository lock is still held. Queue a first-preparation
            // contender at that exact boundary. ConversationWired must keep
            // the outer global lock through parent deletion, so this attempt
            // can run only after the parent is already gone and must refuse.
            reinsertAttempt = Zone.root.run(
              () => fixture.repo.prepareOutgoingDirectPrivatePendingAttachments(
                <MediaAttachment>[pendingAttachment],
              ),
            );
          });
        }
        addTearDown(() async {
          await authorizationSubscription?.cancel();
          await viewerController?.dispose();
          await nativeEvents?.close();
          final token = transferToken;
          if (token != null &&
              directPrivateMediaTransferRegistry.owns(attachmentId, token)) {
            await fixture.repo.lifecycleLock.synchronized(
              attachmentId,
              () async =>
                  directPrivateMediaTransferRegistry.end(attachmentId, token),
            );
          }
        });

        await tester.tap(
          find.byKey(const ValueKey('failed-media-delete-$messageId')),
        );
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump();
        final deleteBarrier = Completer<void>();
        await tester.runAsync(() async {
          unawaited(
            Zone.root
                .run(
                  () => fixture.repo.lifecycleLock.synchronizedAll(() async {}),
                )
                .then((_) => deleteBarrier.complete()),
          );
        });
        await _pumpUntil(
          tester,
          () => deleteBarrier.isCompleted,
          timeout: const Duration(seconds: 30),
        );
        if (deleteCase.reinsertRace) {
          await _pumpUntil(tester, () => reinsertAttempt != null);
          final reinsertResult = await tester.runAsync(
            () => reinsertAttempt!.timeout(const Duration(seconds: 5)),
          );
          expect(
            reinsertResult,
            OutgoingDirectPrivatePendingPreparationOutcome.refused,
          );
        }
        if (deleteCase.expectsDeletion) {
          await _pumpUntil(
            tester,
            () => find
                .byKey(const ValueKey('failed-media-delete-$messageId'))
                .evaluate()
                .isEmpty,
          );
        }

        final durableMessage = await tester.runAsync(
          () => fixture.messageRepo.getMessage(messageId),
        );
        final durableRows = (await tester.runAsync(
          () => fixture.repo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          ),
        ))!;
        final secureKeyPresent = await tester.runAsync(
          () => fixture.secureKeyStore.containsKey(secureKeyName),
        );
        if (deleteCase.expectsDeletion) {
          expect(durableMessage, isNull);
          expect(durableRows, isEmpty);
          expect(pendingFile.existsSync(), isFalse);
          // Key custody must go with the row; an implementation that deletes
          // the attachment but orphans the secure key fails here.
          expect(secureKeyPresent, isFalse);
          expect(
            find.byKey(const ValueKey('failed-media-delete-$messageId')),
            findsNothing,
          );
        } else {
          expect(durableMessage, isNotNull);
          // Only a real lease can hold the parent at 'opening' — that is the
          // exact state the delete refusal keys on.
          expect(
            durableMessage!.privateMediaState,
            deleteCase.activeViewer
                ? PrivateMediaLifecycleState.opening
                : PrivateMediaLifecycleState.available,
          );
          expect(durableRows, hasLength(1));
          expect(durableRows.single.downloadStatus, 'upload_pending');
          expect(durableRows.single.localPath, pendingRelativePath);
          expect(pendingFile.existsSync(), isTrue);
          expect(secureKeyPresent, isTrue);
          expect(
            find.byKey(const ValueKey('failed-media-delete-$messageId')),
            findsOneWidget,
          );
        }

        if (viewerGrant != null) {
          final settlement = await tester.runAsync(
            () => viewerController!
                .settle(
                  viewerGrant!,
                  DirectPrivateMediaExitReason.preFrameDecodeFailure,
                )
                .timeout(const Duration(seconds: 5)),
          );
          // Settling a lease-free grant whose row was deleted underneath it is
          // a no-op, not a fail-closed error.
          expect(
            settlement?.disposition,
            deleteCase.expectsDeletion
                ? DirectPrivateMediaSettleDisposition.noLease
                : DirectPrivateMediaSettleDisposition.rolledBackAvailable,
          );
        }
        final token = transferToken;
        if (token != null) {
          await tester.runAsync(
            () => fixture.repo.lifecycleLock.synchronized(
              attachmentId,
              () async =>
                  directPrivateMediaTransferRegistry.end(attachmentId, token),
            ),
          );
          transferToken = null;
        }
      },
    );
  }
}
