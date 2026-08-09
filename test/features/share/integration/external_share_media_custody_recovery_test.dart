import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  test(
    'TC-348-03 committed external share survives unusable preview and restart',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'tc348_external_share_recovery_',
      );
      final documents = Directory(p.join(root.path, 'documents'))
        ..createSync(recursive: true);
      final source = File(p.join(root.path, 'external-source.jpg'))
        ..writeAsBytesSync(List<int>.generate(128, (index) => index));
      final databasePath = p.join(root.path, 'identity.sqlite');
      final previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _RecoveryPathProvider(documents.path);
      mediaUploadInFlightTracker.clearAll();

      late MediaRepositoryRealDbFixture fixture;
      var fixtureOpen = false;
      addTearDown(() async {
        mediaUploadInFlightTracker.clearAll();
        PathProviderPlatform.instance = previousPathProvider;
        if (fixtureOpen) await fixture.dispose();
        if (await root.exists()) await root.delete(recursive: true);
      });

      fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: databasePath,
      );
      fixtureOpen = true;
      final identity = IdentityModel(
        peerId: 'tc348-recovery-local',
        publicKey: 'tc348-recovery-public',
        privateKey: 'tc348-recovery-private',
        mnemonic12:
            'one two three four five six seven eight nine ten eleven twelve',
        username: 'Recovery Sender',
        createdAt: '2026-08-08T16:00:00.000Z',
        updatedAt: '2026-08-08T16:00:00.000Z',
      );
      const contact = ContactModel(
        peerId: 'tc348-recovery-recipient',
        publicKey: 'tc348-recovery-contact-key',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Recovery Recipient',
        signature: 'tc348-recovery-signature',
        scannedAt: '2026-08-08T16:00:00.000Z',
        mlKemPublicKey: 'tc348-recovery-mlkem',
      );
      final identityRepository = FakeIdentityRepository()..seed(identity);
      final contacts = InMemoryContactRepository();
      await contacts.addContact(contact);
      final bridge = _RecoveryStrictBridge();
      final p2pService = _RecoveryP2PService(
        initialState: NodeState(isStarted: true, peerId: identity.peerId),
      );
      final fileManager = _BlockingRefusingPreviewFileManager(documents.path);
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: contacts,
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        groupRepository: null,
        groupMessageRepository: null,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: fileManager,
        imageProcessor: _recoveryImageProcessor(),
        directMediaBlobCustodyClientEnabled: true,
        forwardNow: () => DateTime.utc(2026, 8, 8, 16),
        processSharedMediaFn: (_) async => ProcessedShareMediaBatch(
          processedMedia: <PendingComposerMedia>[
            PendingComposerMedia(
              file: source,
              budgetBytes: source.lengthSync(),
            ),
          ],
        ),
      );

      final deliveryFuture = coordinator.deliver(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: <String>[source.path],
        ),
        targets: <ShareTargetSelection>[ShareTargetSelection.contact(contact)],
      );
      await fileManager.copyEntered.future.timeout(const Duration(seconds: 5));

      final parentRowsWhileClaimed = await fixture.db.query(
        'messages',
        where: 'contact_peer_id = ? AND is_incoming = 0',
        whereArgs: <Object?>[contact.peerId],
      );
      expect(parentRowsWhileClaimed, hasLength(1));
      final parentWhileClaimed = ConversationMessage.fromMap(
        parentRowsWhileClaimed.single,
      );
      final claimedAttachments = await fixture.repo.getAttachmentsForMessage(
        parentWhileClaimed.id,
        owner: MediaOwnerLane.direct,
      );
      expect(claimedAttachments, hasLength(1));
      expect(
        mediaUploadInFlightTracker.isInFlight(claimedAttachments.single.id),
        isTrue,
      );

      final deferredWhileForegroundOwnsLease = await retryIncompleteUploads(
        mediaAttachmentRepo: fixture.repo,
        messageRepo: fixture.messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepository,
        contactRepo: contacts,
        mediaFileManager: fileManager,
        tryClaimUploadLease: (ids) => mediaUploadInFlightTracker.tryClaimAll(
          ids,
          source: MediaUploadTriggerSource.manual,
        ),
        releaseUploadLease: mediaUploadInFlightTracker.release,
      );
      expect(deferredWhileForegroundOwnsLease, 0);
      expect(bridge.mediaUploadPaths, isEmpty);

      fileManager.refuseCopy.complete();
      final delivery = await deliveryFuture;
      expect(delivery.queuedCount, 1);
      expect(delivery.failureCount, 0);
      expect(bridge.mediaUploadPaths, isEmpty);
      expect(
        mediaUploadInFlightTracker.isInFlight(claimedAttachments.single.id),
        isFalse,
      );

      final custodyRepository =
          fixture.repo as DirectMediaBlobCustodyRepository;
      final custodyBeforeRestart = await custodyRepository
          .loadDirectMediaBlobCustodyForMessage(parentWhileClaimed.id);
      expect(custodyBeforeRestart, hasLength(1));
      final custodyIdentity = custodyBeforeRestart.single;
      final canonicalPreviewPath = await fileManager.resolveStoredPath(
        claimedAttachments.single.localPath!,
      );
      final unusablePreview = File(canonicalPreviewPath);
      unusablePreview.parent.createSync(recursive: true);
      unusablePreview.writeAsBytesSync(const <int>[0xde, 0xad]);
      expect(unusablePreview.lengthSync(), isNot(source.lengthSync()));
      source.deleteSync();

      fixture = await fixture.reopen();
      final reopenedParent = await fixture.messageRepo.getMessage(
        parentWhileClaimed.id,
      );
      final reopenedAttachments = await fixture.repo.getAttachmentsForMessage(
        parentWhileClaimed.id,
        owner: MediaOwnerLane.direct,
      );
      expect(reopenedParent, isNotNull);
      expect(reopenedAttachments.map((attachment) => attachment.id), <String>[
        claimedAttachments.single.id,
      ]);
      expect(
        await fixture.repo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        ),
        hasLength(1),
      );
      expect(
        isExactDirectMediaCustodyRetryProjection(
          message: reopenedParent!,
          expectedSenderPeerId: identity.peerId,
          attachments: reopenedAttachments,
          allowPublishedPending: true,
        ),
        isTrue,
      );
      expect(mediaUploadInFlightTracker.inFlightCount, 0);

      final artifactStore = DirectMediaBlobArtifactStore(
        documentsDirectoryProvider: () async => documents,
      );
      var matchingV108ObservedBeforeInboxStore = false;
      p2pService.onMediaExpiryStore = () async {
        final rows = await fixture.db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[parentWhileClaimed.id],
        );
        matchingV108ObservedBeforeInboxStore =
            rows.length == 1 &&
            rows.single['incarnation_id'] ==
                parentWhileClaimed.directMediaCustodyIntentId;
      };
      if (kDirectMediaBlobCustodyClientEnabled) {
        final recovered = await retryIncompleteUploads(
          mediaAttachmentRepo: fixture.repo,
          messageRepo: fixture.messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepository,
          contactRepo: contacts,
          mediaFileManager: fileManager,
          directMediaBlobArtifactStore: artifactStore,
          tryClaimUploadLease: (ids) => mediaUploadInFlightTracker.tryClaimAll(
            ids,
            source: MediaUploadTriggerSource.manual,
          ),
          releaseUploadLease: mediaUploadInFlightTracker.release,
        );
        expect(recovered, 1);
      } else {
        // Default-off family compilation still exercises the strict restart
        // owner directly; the explicit-define focused gate covers its exact
        // production retry caller.
        final strictCoordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: fixture.repo as DirectMediaBlobCustodyRepository,
          artifactStore: artifactStore,
        );
        final reopened = await strictCoordinator.reopenAndUpload(
          bridge: bridge,
          identityPeerId: identity.peerId,
          recipientPeerId: contact.peerId,
          expectedParent: reopenedParent,
          expectedAttachments: reopenedAttachments,
        );
        expect(reopened.isComplete, isTrue);
        final (sendResult, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: fixture.messageRepo,
          targetPeerId: contact.peerId,
          text: reopenedParent.text,
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          messageId: reopenedParent.id,
          timestamp: reopenedParent.timestamp,
          createdAt: reopenedParent.createdAt,
          dedupKey: reopenedParent.id,
          isForwarded: false,
          bridge: bridge,
          recipientMlKemPublicKey: contact.mlKemPublicKey,
          mediaAttachments: reopened.attachments,
          mediaAttachmentRepo: fixture.repo,
        );
        expect(sendResult, SendChatMessageResult.success);
      }

      expect(bridge.mediaUploadPaths, hasLength(1));
      expect(
        bridge.mediaUploadPaths.single.replaceAll('\\', '/'),
        contains('direct_media_blob_custody_v1/'),
        reason: 'restart uploads v111 ciphertext, never the unusable preview',
      );
      expect(bridge.mediaUploadIds, <String>[claimedAttachments.single.id]);
      expect(unusablePreview.readAsBytesSync(), const <int>[0xde, 0xad]);
      expect(
        await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[parentWhileClaimed.id],
        ),
        hasLength(1),
      );
      expect(matchingV108ObservedBeforeInboxStore, isTrue);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(custodyIdentity.messageId, parentWhileClaimed.id);
      expect(custodyIdentity.attachmentId, claimedAttachments.single.id);
    },
  );

  test(
    'TC-350-03c committed internal forward survives source loss and restart with exact provenance',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'tc350_internal_forward_recovery_',
      );
      final documents = Directory(p.join(root.path, 'documents'))
        ..createSync(recursive: true);
      // A dispatch-owned snapshot the entry disposes normally after delivery.
      final snapshotDir = Directory(p.join(root.path, 'forward-snapshot'))
        ..createSync(recursive: true);
      final snapshotSource = File(p.join(snapshotDir.path, 'source_0.jpg'))
        ..writeAsBytesSync(List<int>.generate(160, (index) => index));
      final databasePath = p.join(root.path, 'identity.sqlite');
      final previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _RecoveryPathProvider(documents.path);
      mediaUploadInFlightTracker.clearAll();

      late MediaRepositoryRealDbFixture fixture;
      var fixtureOpen = false;
      addTearDown(() async {
        mediaUploadInFlightTracker.clearAll();
        PathProviderPlatform.instance = previousPathProvider;
        if (fixtureOpen) await fixture.dispose();
        if (await root.exists()) await root.delete(recursive: true);
      });

      fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: databasePath,
      );
      fixtureOpen = true;
      final identity = IdentityModel(
        peerId: 'tc350-recovery-local',
        publicKey: 'tc350-recovery-public',
        privateKey: 'tc350-recovery-private',
        mnemonic12:
            'one two three four five six seven eight nine ten eleven twelve',
        username: 'Forward Sender',
        createdAt: '2026-08-09T16:00:00.000Z',
        updatedAt: '2026-08-09T16:00:00.000Z',
      );
      const contact = ContactModel(
        peerId: 'tc350-recovery-recipient',
        publicKey: 'tc350-recovery-contact-key',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Forward Recipient',
        signature: 'tc350-recovery-signature',
        scannedAt: '2026-08-09T16:00:00.000Z',
        mlKemPublicKey: 'tc350-recovery-mlkem',
      );
      const forwardToken = 'tc350-recovery-forward-token';
      final identityRepository = FakeIdentityRepository()..seed(identity);
      final contacts = InMemoryContactRepository();
      await contacts.addContact(contact);
      final bridge = _RecoveryStrictBridge();
      final p2pService = _RecoveryP2PService(
        initialState: NodeState(isStarted: true, peerId: identity.peerId),
      );
      final fileManager = _BlockingRefusingPreviewFileManager(documents.path);
      final coordinator = DefaultShareBatchDeliveryCoordinator(
        identityRepository: identityRepository,
        contactRepository: contacts,
        messageRepository: fixture.messageRepo,
        mediaAttachmentRepository: fixture.repo,
        groupRepository: null,
        groupMessageRepository: null,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: fileManager,
        imageProcessor: _recoveryImageProcessor(),
        directMediaBlobCustodyClientEnabled: true,
        forwardNow: () => DateTime.utc(2026, 8, 9, 16),
        processSharedMediaFn: (intent) async => ProcessedShareMediaBatch(
          processedMedia: <PendingComposerMedia>[
            PendingComposerMedia(
              file: File(intent.filePaths.single),
              budgetBytes: File(intent.filePaths.single).lengthSync(),
            ),
          ],
        ),
      );

      // The revalidated direct-library port is the reviewed entry here.
      final deliveryFuture = coordinator.deliverDirectMediaBatchForwardStrict(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: <String>[snapshotSource.path],
          forwardProvenance: const ForwardProvenance(
            operationDedupKey: forwardToken,
          ),
        ),
        contacts: const <ContactModel>[contact],
      );
      await fileManager.copyEntered.future.timeout(const Duration(seconds: 5));
      fileManager.refuseCopy.complete();
      final delivery = await deliveryFuture;
      expect(delivery.queuedCount, 1);
      expect(delivery.failureCount, 0);
      expect(bridge.mediaUploadPaths, isEmpty);

      final parentRows = await fixture.db.query(
        'messages',
        where: 'contact_peer_id = ? AND is_incoming = 0',
        whereArgs: <Object?>[contact.peerId],
      );
      expect(parentRows, hasLength(1));
      final committedParent = ConversationMessage.fromMap(parentRows.single);
      expect(committedParent.isForwarded, isTrue);
      expect(committedParent.dedupKey, forwardToken);
      final committedAttachments = await fixture.repo.getAttachmentsForMessage(
        committedParent.id,
        owner: MediaOwnerLane.direct,
      );
      expect(committedAttachments, hasLength(1));
      final custodyRepository =
          fixture.repo as DirectMediaBlobCustodyRepository;
      expect(
        await custodyRepository.loadDirectMediaBlobCustodyForMessage(
          committedParent.id,
        ),
        hasLength(1),
      );

      // Normal snapshot disposal plus source loss: recovery is source-free.
      snapshotDir.deleteSync(recursive: true);
      expect(snapshotSource.existsSync(), isFalse);

      fixture = await fixture.reopen();
      final reopenedParent = await fixture.messageRepo.getMessage(
        committedParent.id,
      );
      final reopenedAttachments = await fixture.repo.getAttachmentsForMessage(
        committedParent.id,
        owner: MediaOwnerLane.direct,
      );
      expect(reopenedParent, isNotNull);
      expect(
        reopenedParent!.isForwarded,
        isTrue,
        reason: 'restart rebuilds nothing — the exact forwarded row survives',
      );
      expect(reopenedParent.dedupKey, forwardToken);
      expect(reopenedParent.contactPeerId, contact.peerId);
      expect(reopenedAttachments.map((attachment) => attachment.id), <String>[
        committedAttachments.single.id,
      ]);
      expect(
        reopenedAttachments.single.encryptionNonce,
        committedAttachments.single.encryptionNonce,
        reason: 'the exact encrypted inner projection is preserved',
      );

      final artifactStore = DirectMediaBlobArtifactStore(
        documentsDirectoryProvider: () async => documents,
      );
      var matchingV108ObservedBeforeInboxStore = false;
      p2pService.onMediaExpiryStore = () async {
        final rows = await fixture.db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[committedParent.id],
        );
        matchingV108ObservedBeforeInboxStore =
            rows.length == 1 &&
            rows.single['incarnation_id'] ==
                committedParent.directMediaCustodyIntentId;
      };
      if (kDirectMediaBlobCustodyClientEnabled) {
        expect(
          await retryIncompleteUploads(
            mediaAttachmentRepo: fixture.repo,
            messageRepo: fixture.messageRepo,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: identityRepository,
            contactRepo: contacts,
            mediaFileManager: fileManager,
            directMediaBlobArtifactStore: artifactStore,
            tryClaimUploadLease: (ids) => mediaUploadInFlightTracker
                .tryClaimAll(ids, source: MediaUploadTriggerSource.manual),
            releaseUploadLease: mediaUploadInFlightTracker.release,
          ),
          1,
        );
      } else {
        final strictCoordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: fixture.repo as DirectMediaBlobCustodyRepository,
          artifactStore: artifactStore,
        );
        final reopened = await strictCoordinator.reopenAndUpload(
          bridge: bridge,
          identityPeerId: identity.peerId,
          recipientPeerId: contact.peerId,
          expectedParent: reopenedParent,
          expectedAttachments: reopenedAttachments,
        );
        expect(reopened.isComplete, isTrue);
        final (sendResult, _) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: fixture.messageRepo,
          targetPeerId: contact.peerId,
          text: reopenedParent.text,
          senderPeerId: identity.peerId,
          senderUsername: identity.username,
          messageId: reopenedParent.id,
          timestamp: reopenedParent.timestamp,
          createdAt: reopenedParent.createdAt,
          dedupKey: forwardToken,
          isForwarded: true,
          bridge: bridge,
          recipientMlKemPublicKey: contact.mlKemPublicKey,
          mediaAttachments: reopened.attachments,
          mediaAttachmentRepo: fixture.repo,
        );
        expect(sendResult, SendChatMessageResult.success);
      }

      expect(bridge.mediaUploadPaths, hasLength(1));
      expect(
        bridge.mediaUploadPaths.single.replaceAll('\\', '/'),
        contains('direct_media_blob_custody_v1/'),
        reason:
            'restart uploads the v111 ciphertext without the lost source or '
            'any plaintext preview',
      );
      expect(bridge.mediaUploadIds, <String>[committedAttachments.single.id]);
      expect(matchingV108ObservedBeforeInboxStore, isTrue);
      expect(p2pService.storeInInboxCallCount, 1);

      final settledParent = await fixture.messageRepo.getMessage(
        committedParent.id,
      );
      expect(settledParent!.isForwarded, isTrue);
      expect(settledParent.dedupKey, forwardToken);
    },
  );
}

ImageProcessor _recoveryImageProcessor() => ImageProcessor(
  compressFile:
      ({
        required path,
        required quality,
        required keepExif,
        minWidth = 1920,
        minHeight = 1080,
      }) async => null,
  compressVideo: ({required path, required compress, onProgress}) async => null,
);

class _BlockingRefusingPreviewFileManager extends MediaFileManager {
  _BlockingRefusingPreviewFileManager(this.documentsPath);

  final String documentsPath;
  final Completer<void> copyEntered = Completer<void>();
  final Completer<void> refuseCopy = Completer<void>();

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    if (!copyEntered.isCompleted) copyEntered.complete();
    await refuseCopy.future;
    throw const FileSystemException('injected pre-write preview refusal');
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async =>
      p.isAbsolute(storedPath) ? storedPath : p.join(documentsPath, storedPath);
}

class _RecoveryStrictBridge extends PassthroughCryptoBridge {
  final List<String> mediaUploadIds = <String>[];
  final List<String> mediaUploadPaths = <String>[];

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'] as String?;
    if (command != 'media:upload') return super.send(message);
    final payload = request['payload']! as Map<String, dynamic>;
    final id = payload['id']! as String;
    final filePath = payload['filePath']! as String;
    mediaUploadIds.add(id);
    mediaUploadPaths.add(filePath);
    return jsonEncode(<String, dynamic>{
      'ok': true,
      'id': id,
      'storeStatus': 'stored',
      'custodyKind': payload['custodyKind'],
      'custodyContract': payload['custodyContract'],
      'contentHash': payload['contentHash'],
      'size': File(filePath).lengthSync(),
      'mime': payload['mime'],
      'expiresAtMs': DateTime.now()
          .toUtc()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
      'custodyRelayPeerId': 'tc348-recovery-relay',
    });
  }
}

class _RecoveryP2PService extends FakeP2PService
    implements AckOrExpiryInboxStore, MediaExpiryBoundedInboxStore {
  _RecoveryP2PService({required super.initialState});

  Future<void> Function()? onMediaExpiryStore;

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    final stored = await storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
    return InboxStoreOutcome(
      status: stored ? InboxStoreStatus.stored : InboxStoreStatus.failed,
      errorCode: stored ? null : 'STORE_RETURNED_FALSE',
      storeStatus: stored ? 'stored' : null,
      custodyContract: stored ? ackOrExpiryInboxCustodyContract : null,
    );
  }

  @override
  Future<InboxStoreOutcome> storeInMediaExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) async {
    await onMediaExpiryStore?.call();
    final stored = await storeInInbox(toPeerId, message, timeoutMs: timeoutMs);
    return InboxStoreOutcome(
      status: stored ? InboxStoreStatus.stored : InboxStoreStatus.failed,
      errorCode: stored ? null : 'STORE_RETURNED_FALSE',
      storeStatus: stored ? 'stored' : null,
      custodyContract: stored ? ackOrExpiryInboxCustodyContract : null,
      expiresAtMs: stored ? custodyExpiresAtOrBeforeMs : null,
    );
  }
}

class _RecoveryPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _RecoveryPathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
