import 'dart:io';

import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() => fixture.dispose());

  Future<MediaAttachment> seedPrivatePending({
    String messageId = 'writer-private',
    String attachmentId = 'writer-private-att',
    String state = 'available',
    String parentStatus = 'sending',
    String attachmentStatus = 'upload_pending',
    int retryCount = 0,
    String contactPeerId = 'writer-contact',
  }) async {
    await fixture.seedDirectParent(messageId, contactPeerId: contactPeerId);
    await fixture.db.update(
      'messages',
      <String, Object?>{
        'status': parentStatus,
        'is_incoming': 0,
        'private_media_policy_version': 1,
        'private_media_mode': 'protected',
        'private_media_state': state,
        'private_media_received_at_ms': 1000,
        'private_media_clock_high_water_ms': 1000,
        'private_media_revealed_at_ms': state == 'opening' || state == 'viewing'
            ? 1100
            : null,
        'private_media_terminal_at_ms': state == 'consumed' ? 1200 : null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[messageId],
    );
    final pendingPath = MediaFilePathConvention.relativePathForPendingUpload(
      messageId: messageId,
      attachmentId: attachmentId,
      mime: 'image/jpeg',
    );
    final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
    await fixture.secureKeyStore.write(keyName, 'writer-key');
    final attachment = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 4,
      mediaType: 'image',
      localPath: pendingPath,
      downloadStatus: attachmentStatus,
      createdAt: '2026-07-20T00:00:00.000Z',
      uploadRetryCount: retryCount,
      contentHash: 'pending-hash',
      encryptionKeyBase64: secureStoreReferenceForKey(keyName),
      encryptionNonce: 'pending-nonce',
      encryptionScheme: 'blob_aes_gcm_v1',
      ownerLane: MediaOwnerLane.direct,
    );
    await dbInsertMediaAttachment(fixture.db, attachment.toMap());
    return attachment;
  }

  Future<Map<String, Object?>> row(String attachmentId) async =>
      (await fixture.db.query(
        'media_attachments',
        where: 'id = ?',
        whereArgs: <Object?>[attachmentId],
      )).single;

  test('failure projection returns an explicit active-lease no-op', () async {
    final attachment = await seedPrivatePending(state: 'opening');
    final before = Map<String, Object?>.from(await row(attachment.id));

    final result = await dbProjectDirectUploadFailure(
      fixture.db,
      messageId: attachment.messageId,
      attachmentId: attachment.id,
      disposition: UploadMediaDisposition.terminal,
    );

    expect(result.blockedByActiveLease, isTrue);
    expect(await row(attachment.id), before);
    expect(
      (await fixture.db.query(
        'messages',
        columns: const <String>['status', 'private_media_state'],
        where: 'id = ?',
        whereArgs: <Object?>[attachment.messageId],
      )).single,
      <String, Object?>{'status': 'sending', 'private_media_state': 'opening'},
    );
  });

  test(
    'envelope invalidation rejects incoherent private lifecycle shapes',
    () async {
      final seeded = await seedPrivatePending(state: 'available');
      const staleEnvelope = 'stale-envelope';
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'wire_envelope': staleEnvelope,
          'private_media_revealed_at_ms': 1100,
        },
        where: 'id = ?',
        whereArgs: <Object?>[seeded.messageId],
      );

      expect(
        await dbInvalidateWireEnvelopeBeforePrivateUpload(
          fixture.db,
          messageId: seeded.messageId,
          attachmentId: seeded.id,
          expectedPendingLocalPath: seeded.localPath!,
        ),
        isFalse,
      );
      expect(
        (await fixture.db.query(
          'messages',
          columns: const <String>['wire_envelope'],
          where: 'id = ?',
          whereArgs: <Object?>[seeded.messageId],
        )).single['wire_envelope'],
        staleEnvelope,
      );

      await fixture.db.update(
        'messages',
        <String, Object?>{
          'private_media_state': 'consumed',
          'private_media_revealed_at_ms': 1100,
          'private_media_terminal_at_ms': null,
        },
        where: 'id = ?',
        whereArgs: <Object?>[seeded.messageId],
      );
      expect(
        await dbInvalidateWireEnvelopeBeforePrivateUpload(
          fixture.db,
          messageId: seeded.messageId,
          attachmentId: seeded.id,
          expectedPendingLocalPath: seeded.localPath!,
        ),
        isFalse,
      );

      await fixture.db.update(
        'messages',
        <String, Object?>{
          'private_media_state': 'viewing',
          'private_media_terminal_at_ms': null,
        },
        where: 'id = ?',
        whereArgs: <Object?>[seeded.messageId],
      );
      expect(
        await dbInvalidateWireEnvelopeBeforePrivateUpload(
          fixture.db,
          messageId: seeded.messageId,
          attachmentId: seeded.id,
          expectedPendingLocalPath: seeded.localPath!,
        ),
        isTrue,
      );
      expect(
        (await fixture.db.query(
          'messages',
          columns: const <String>['wire_envelope'],
          where: 'id = ?',
          whereArgs: <Object?>[seeded.messageId],
        )).single['wire_envelope'],
        isNull,
      );
    },
  );

  test(
    'private envelope handoff accepts only canonical or coordinator-owned custody',
    () async {
      MediaAttachment completedFor(
        MediaAttachment pending, {
        required String contactPeerId,
      }) => pending.copyWith(
        localPath: MediaFilePathConvention.relativePathForAttachment(
          contactPeerId: contactPeerId,
          blobId: pending.id,
          mime: pending.mime,
        ),
        downloadStatus: 'done',
        contentHash:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        thumbnailHash: 'completion-thumbnail',
        encryptionKeyBase64: 'rotated-${pending.id}',
        encryptionNonce: 'completion-nonce-${pending.id}',
        encryptionScheme: 'blob_aes_gcm_v1',
        ownerLane: MediaOwnerLane.direct,
      );

      for (final state in const <String>[
        'available',
        'opening',
        'viewing',
        'consumed',
      ]) {
        final messageId = 'writer-handoff-$state';
        final attachmentId = '$messageId-att';
        final contactPeerId = '$messageId-contact';
        final pending = await seedPrivatePending(
          messageId: messageId,
          attachmentId: attachmentId,
          state: state,
          contactPeerId: contactPeerId,
        );
        final completed = completedFor(pending, contactPeerId: contactPeerId);
        final mutation = await fixture
            .repo
            .outgoingDirectPrivateMutationCoordinator
            .commitCompletion(
              attachment: completed,
              expectedPendingLocalPath: pending.localPath!,
            );
        expect(mutation.authorizesTransportHandoff, isTrue, reason: state);
        final owned = await fixture
            .repo
            .outgoingDirectPrivateMutationCoordinator
            .loadOwnedCompletionFingerprint(
              messageId: messageId,
              attachmentId: attachmentId,
              expectedPendingLocalPath: pending.localPath!,
            );
        final envelope = 'envelope-$state';
        expect(
          await fixture.messageRepo.commitOutgoingDirectPrivateWireEnvelope(
            messageId: messageId,
            completedAttachment: completed,
            expectedPendingLocalPath: pending.localPath!,
            envelope: envelope,
            hasOwnedPendingCompletion: owned == mutation.fingerprint,
          ),
          OutgoingDirectPrivateEnvelopeHandoffOutcome.committed,
          reason: state,
        );
        final parent = (await fixture.db.query(
          'messages',
          columns: const <String>[
            'wire_envelope',
            'private_media_state',
            'hidden_at',
            'deleted_at',
          ],
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single;
        expect(parent['wire_envelope'], envelope, reason: state);
        expect(parent['private_media_state'], state, reason: state);
        expect(parent['hidden_at'], isNull, reason: state);
        expect(parent['deleted_at'], isNull, reason: state);
        expect(
          await fixture.messageRepo.commitOutgoingDirectPrivateWireEnvelope(
            messageId: messageId,
            completedAttachment: completed,
            expectedPendingLocalPath: pending.localPath!,
            envelope: envelope,
            hasOwnedPendingCompletion: owned == mutation.fingerprint,
          ),
          OutgoingDirectPrivateEnvelopeHandoffOutcome.idempotent,
          reason: state,
        );
      }

      const restartMessageId = 'writer-handoff-consumed-canonical';
      const restartAttachmentId = '$restartMessageId-att';
      const restartContactPeerId = '$restartMessageId-contact';
      final restartPending = await seedPrivatePending(
        messageId: restartMessageId,
        attachmentId: restartAttachmentId,
        state: 'available',
        contactPeerId: restartContactPeerId,
      );
      final restartCompleted = completedFor(
        restartPending,
        contactPeerId: restartContactPeerId,
      );
      expect(
        (await fixture.repo.outgoingDirectPrivateMutationCoordinator
                .commitCompletion(
                  attachment: restartCompleted,
                  expectedPendingLocalPath: restartPending.localPath!,
                ))
            .outcome,
        OutgoingDirectPrivateMutationOutcome.committed,
      );
      await fixture.db.update(
        'messages',
        const <String, Object?>{
          'private_media_state': 'consumed',
          'private_media_terminal_at_ms': 1200,
        },
        where: 'id = ?',
        whereArgs: const <Object?>[restartMessageId],
      );
      expect(
        await fixture.messageRepo.commitOutgoingDirectPrivateWireEnvelope(
          messageId: restartMessageId,
          completedAttachment: restartCompleted,
          expectedPendingLocalPath: restartPending.localPath!,
          envelope: 'restart-envelope',
          hasOwnedPendingCompletion: false,
        ),
        OutgoingDirectPrivateEnvelopeHandoffOutcome.committed,
      );

      final unowned = await seedPrivatePending(
        messageId: 'writer-handoff-unowned',
        attachmentId: 'writer-handoff-unowned-att',
        state: 'opening',
        contactPeerId: 'writer-handoff-unowned-contact',
      );
      expect(
        await fixture.messageRepo.commitOutgoingDirectPrivateWireEnvelope(
          messageId: unowned.messageId,
          completedAttachment: completedFor(
            unowned,
            contactPeerId: 'writer-handoff-unowned-contact',
          ),
          expectedPendingLocalPath: unowned.localPath!,
          envelope: 'must-not-persist',
          hasOwnedPendingCompletion: false,
        ),
        OutgoingDirectPrivateEnvelopeHandoffOutcome.refused,
      );
      expect(
        (await fixture.db.query(
          'messages',
          columns: const <String>['wire_envelope'],
          where: 'id = ?',
          whereArgs: <Object?>[unowned.messageId],
        )).single['wire_envelope'],
        isNull,
      );
    },
  );

  test(
    'private transport settlement is column-only and concurrent intent wins',
    () async {
      Future<({MediaAttachment pending, MediaAttachment completed})> prepare(
        String suffix,
      ) async {
        final messageId = 'writer-settle-$suffix';
        final attachmentId = '$messageId-att';
        final contactPeerId = '$messageId-contact';
        final pending = await seedPrivatePending(
          messageId: messageId,
          attachmentId: attachmentId,
          state: 'viewing',
          contactPeerId: contactPeerId,
        );
        final completed = pending.copyWith(
          localPath: MediaFilePathConvention.relativePathForAttachment(
            contactPeerId: contactPeerId,
            blobId: attachmentId,
            mime: pending.mime,
          ),
          downloadStatus: 'done',
          contentHash:
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          encryptionKeyBase64: 'settle-key-$suffix',
          encryptionNonce: 'settle-nonce-$suffix',
          encryptionScheme: 'blob_aes_gcm_v1',
          ownerLane: MediaOwnerLane.direct,
        );
        final mutation = await fixture
            .repo
            .outgoingDirectPrivateMutationCoordinator
            .commitCompletion(
              attachment: completed,
              expectedPendingLocalPath: pending.localPath!,
            );
        expect(
          mutation.outcome,
          OutgoingDirectPrivateMutationOutcome.deferredActiveLease,
        );
        expect(
          await fixture.messageRepo.commitOutgoingDirectPrivateWireEnvelope(
            messageId: messageId,
            completedAttachment: completed,
            expectedPendingLocalPath: pending.localPath!,
            envelope: 'settle-envelope-$suffix',
            hasOwnedPendingCompletion: true,
          ),
          OutgoingDirectPrivateEnvelopeHandoffOutcome.committed,
        );
        return (pending: pending, completed: completed);
      }

      final visible = await prepare('visible');
      final attachmentBefore = Map<String, Object?>.from(
        await row(visible.pending.id),
      );
      expect(
        await fixture.messageRepo.settleOutgoingDirectPrivateTransport(
          messageId: visible.pending.messageId,
          attachmentId: visible.pending.id,
          expectedEnvelope: 'settle-envelope-visible',
          status: 'inboxed',
          transport: 'inbox',
          relayExpiresAt: 9000,
        ),
        OutgoingDirectPrivateTransportSettlementOutcome.committed,
      );
      var parent = (await fixture.db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[visible.pending.messageId],
      )).single;
      expect(parent['status'], 'inboxed');
      expect(parent['transport'], 'inbox');
      expect(parent['relay_expires_at'], 9000);
      expect(parent['wire_envelope'], 'settle-envelope-visible');
      expect(parent['private_media_state'], 'viewing');
      expect(await row(visible.pending.id), attachmentBefore);

      expect(
        await fixture.messageRepo.settleOutgoingDirectPrivateTransport(
          messageId: visible.pending.messageId,
          attachmentId: visible.pending.id,
          expectedEnvelope: 'settle-envelope-visible',
          status: 'delivered',
          transport: 'direct',
          relayExpiresAt: null,
        ),
        OutgoingDirectPrivateTransportSettlementOutcome.committed,
      );
      parent = (await fixture.db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[visible.pending.messageId],
      )).single;
      expect(parent['status'], 'delivered');
      expect(parent['transport'], 'direct');
      expect(parent['wire_envelope'], isNull);
      expect(parent['private_media_state'], 'viewing');
      expect(await row(visible.pending.id), attachmentBefore);

      for (final intentColumn in const <String>['hidden_at', 'deleted_at']) {
        final suffix = intentColumn == 'hidden_at' ? 'hidden' : 'deleted';
        final raced = await prepare(suffix);
        await fixture.db.update(
          'messages',
          <String, Object?>{intentColumn: '2026-07-20T02:00:00.000Z'},
          where: 'id = ?',
          whereArgs: <Object?>[raced.pending.messageId],
        );
        expect(
          await fixture.messageRepo.settleOutgoingDirectPrivateTransport(
            messageId: raced.pending.messageId,
            attachmentId: raced.pending.id,
            expectedEnvelope: 'settle-envelope-$suffix',
            status: 'delivered',
            transport: 'direct',
            relayExpiresAt: null,
          ),
          OutgoingDirectPrivateTransportSettlementOutcome.preservedUserIntent,
          reason: intentColumn,
        );
        final racedParent = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[raced.pending.messageId],
        )).single;
        expect(racedParent[intentColumn], isNotNull);
        expect(racedParent['status'], 'sending');
        expect(racedParent['private_media_state'], 'viewing');
        expect(racedParent['wire_envelope'], 'settle-envelope-$suffix');
      }
    },
  );

  test('generic envelope writer excludes private and future parents', () async {
    final private = await seedPrivatePending(
      messageId: 'writer-generic-envelope-private',
      attachmentId: 'writer-generic-envelope-private-att',
    );
    await dbUpdateWireEnvelope(
      fixture.db,
      private.messageId,
      'generic-must-not-persist',
    );
    expect(
      (await fixture.db.query(
        'messages',
        columns: const <String>['wire_envelope'],
        where: 'id = ?',
        whereArgs: <Object?>[private.messageId],
      )).single['wire_envelope'],
      isNull,
    );

    for (final shape in const <({String id, int version, String mode})>[
      (id: 'writer-generic-envelope-ordinary', version: 0, mode: 'ordinary'),
      (
        id: 'writer-generic-envelope-disappearing',
        version: 1,
        mode: 'disappearing',
      ),
      (id: 'writer-generic-envelope-future', version: 2, mode: 'protected'),
    ]) {
      await fixture.seedDirectParent(shape.id);
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'is_incoming': 0,
          'private_media_policy_version': shape.version,
          'private_media_mode': shape.mode,
        },
        where: 'id = ?',
        whereArgs: <Object?>[shape.id],
      );
      await dbUpdateWireEnvelope(fixture.db, shape.id, 'generic-${shape.id}');
      expect(
        (await fixture.db.query(
          'messages',
          columns: const <String>['wire_envelope'],
          where: 'id = ?',
          whereArgs: <Object?>[shape.id],
        )).single['wire_envelope'],
        shape.version > 1 ? isNull : 'generic-${shape.id}',
        reason: shape.id,
      );
    }
  });

  test(
    'first private pending preparation exact-inserts and invalid policy refuses',
    () async {
      const messageId = 'writer-first-private';
      const attachmentId = 'writer-first-private-att';
      await fixture.seedDirectParent(messageId);
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'status': 'sending',
          'is_incoming': 0,
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: const <Object?>[messageId],
      );
      final exactPath = MediaFilePathConvention.relativePathForPendingUpload(
        messageId: messageId,
        attachmentId: attachmentId,
        mime: 'image/jpeg',
      );
      final pending = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 4,
        mediaType: 'image',
        localPath: exactPath,
        downloadStatus: 'upload_pending',
        createdAt: '2026-07-20T00:00:00.000Z',
        ownerLane: MediaOwnerLane.direct,
      );

      expect(
        await fixture.repo.prepareOutgoingDirectPrivatePendingAttachments(
          <MediaAttachment>[pending],
        ),
        OutgoingDirectPrivatePendingPreparationOutcome.inserted,
      );
      expect((await row(attachmentId))['local_path'], exactPath);

      const futureMessageId = 'writer-future-policy';
      const futureAttachmentId = 'writer-future-policy-att';
      await fixture.seedDirectParent(futureMessageId);
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'status': 'sending',
          'is_incoming': 0,
          'private_media_policy_version': 2,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
        },
        where: 'id = ?',
        whereArgs: const <Object?>[futureMessageId],
      );
      final futureAttachment = MediaAttachment(
        id: futureAttachmentId,
        messageId: futureMessageId,
        mime: 'image/jpeg',
        size: 4,
        mediaType: 'image',
        localPath: MediaFilePathConvention.relativePathForPendingUpload(
          messageId: futureMessageId,
          attachmentId: futureAttachmentId,
          mime: 'image/jpeg',
        ),
        downloadStatus: 'upload_pending',
        createdAt: '2026-07-20T00:00:00.000Z',
        ownerLane: MediaOwnerLane.direct,
      );
      expect(
        await fixture.repo.prepareOutgoingDirectPrivatePendingAttachments(
          <MediaAttachment>[futureAttachment],
        ),
        OutgoingDirectPrivatePendingPreparationOutcome.refused,
      );
      await expectLater(
        fixture.repo.saveAttachment(
          futureAttachment,
          owner: MediaOwnerLane.direct,
        ),
        throwsA(
          isA<OutgoingDirectPrivatePendingPreparationRefused>().having(
            (error) => error.outcome,
            'outcome',
            OutgoingDirectPrivatePendingPreparationOutcome.refused,
          ),
        ),
      );
      expect(
        await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: const <Object?>[futureAttachmentId],
        ),
        isEmpty,
      );

      const keyedMessageId = 'writer-keyed-preparation';
      const keyedAttachmentId = 'writer-keyed-preparation-att';
      await fixture.seedDirectParent(keyedMessageId);
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'status': 'sending',
          'is_incoming': 0,
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: const <Object?>[keyedMessageId],
      );
      expect(
        await fixture.repo
            .prepareOutgoingDirectPrivatePendingAttachments(<MediaAttachment>[
              MediaAttachment(
                id: keyedAttachmentId,
                messageId: keyedMessageId,
                mime: 'image/jpeg',
                size: 4,
                mediaType: 'image',
                localPath: MediaFilePathConvention.relativePathForPendingUpload(
                  messageId: keyedMessageId,
                  attachmentId: keyedAttachmentId,
                  mime: 'image/jpeg',
                ),
                downloadStatus: 'upload_pending',
                createdAt: '2026-07-20T00:00:00.000Z',
                encryptionKeyBase64: 'must-not-become-a-dangling-reference',
                ownerLane: MediaOwnerLane.direct,
              ),
            ]),
        OutgoingDirectPrivatePendingPreparationOutcome.refused,
      );
      expect(
        await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: const <Object?>[keyedAttachmentId],
        ),
        isEmpty,
      );
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(keyedAttachmentId),
        ),
        isFalse,
      );

      for (final invalid
          in <({String messageId, String attachmentId, String mime})>[
            (
              messageId: 'writer-unknown-mime',
              attachmentId: 'writer-unknown-mime-att',
              mime: 'application/x-unknown-private',
            ),
            (
              messageId: '../writer-unsafe-message',
              attachmentId: 'writer-unsafe-att',
              mime: 'image/jpeg',
            ),
          ]) {
        await fixture.seedDirectParent(invalid.messageId);
        await fixture.db.update(
          'messages',
          <String, Object?>{
            'status': 'sending',
            'is_incoming': 0,
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
            'private_media_received_at_ms': 1000,
            'private_media_clock_high_water_ms': 1000,
          },
          where: 'id = ?',
          whereArgs: <Object?>[invalid.messageId],
        );
        expect(
          await fixture.repo.prepareOutgoingDirectPrivatePendingAttachments(
            <MediaAttachment>[
              MediaAttachment(
                id: invalid.attachmentId,
                messageId: invalid.messageId,
                mime: invalid.mime,
                size: 4,
                mediaType: 'document',
                localPath: MediaFilePathConvention.relativePathForPendingUpload(
                  messageId: invalid.messageId,
                  attachmentId: invalid.attachmentId,
                  mime: invalid.mime,
                ),
                downloadStatus: 'upload_pending',
                createdAt: '2026-07-20T00:00:00.000Z',
                ownerLane: MediaOwnerLane.direct,
              ),
            ],
          ),
          OutgoingDirectPrivatePendingPreparationOutcome.refused,
        );
        expect(
          await fixture.db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: <Object?>[invalid.attachmentId],
          ),
          isEmpty,
        );
      }

      const batchMessageId = 'writer-atomic-batch';
      await fixture.seedDirectParent(batchMessageId);
      await fixture.db.update(
        'messages',
        <String, Object?>{
          'status': 'sending',
          'is_incoming': 0,
          'private_media_policy_version': 1,
          'private_media_mode': 'protected',
          'private_media_state': 'available',
          'private_media_received_at_ms': 1000,
          'private_media_clock_high_water_ms': 1000,
        },
        where: 'id = ?',
        whereArgs: const <Object?>[batchMessageId],
      );
      MediaAttachment batchAttachment(String id, String mime) =>
          MediaAttachment(
            id: id,
            messageId: batchMessageId,
            mime: mime,
            size: 4,
            mediaType: 'image',
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: batchMessageId,
              attachmentId: id,
              mime: mime,
            ),
            downloadStatus: 'upload_pending',
            createdAt: '2026-07-20T00:00:00.000Z',
            ownerLane: MediaOwnerLane.direct,
          );
      expect(
        await fixture.repo
            .prepareOutgoingDirectPrivatePendingAttachments(<MediaAttachment>[
              batchAttachment('writer-atomic-batch-good', 'image/jpeg'),
              batchAttachment(
                'writer-atomic-batch-refused',
                'application/x-unknown-private',
              ),
            ]),
        OutgoingDirectPrivatePendingPreparationOutcome.refused,
      );
      expect(
        await fixture.db.query(
          'media_attachments',
          where: 'message_id = ?',
          whereArgs: const <Object?>[batchMessageId],
        ),
        isEmpty,
      );
    },
  );

  test('outgoing disappearing retains generic save and deletion', () async {
    const messageId = 'writer-disappearing';
    const attachmentId = 'writer-disappearing-att';
    await fixture.seedDirectParent(
      messageId,
      contactPeerId: 'writer-disappearing-contact',
    );
    await fixture.db.update(
      'messages',
      <String, Object?>{
        'status': 'sending',
        'is_incoming': 0,
        'private_media_policy_version': 1,
        'private_media_mode': 'disappearing',
        'private_media_state': 'available',
        'private_media_received_at_ms': 1000,
        'private_media_clock_high_water_ms': 1000,
      },
      where: 'id = ?',
      whereArgs: const <Object?>[messageId],
    );
    final attachment = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 4,
      mediaType: 'image',
      localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
      downloadStatus: 'upload_pending',
      createdAt: '2026-07-20T00:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );

    await fixture.repo.saveAttachment(attachment, owner: MediaOwnerLane.direct);
    await fixture.repo.saveAttachment(
      attachment.copyWith(downloadStatus: 'upload_failed'),
      owner: MediaOwnerLane.direct,
    );
    expect((await row(attachmentId))['download_status'], 'upload_failed');
    final canonicalPath = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: 'writer-disappearing-contact',
      blobId: attachmentId,
      mime: attachment.mime,
    );
    await fixture.repo.saveAttachment(
      attachment.copyWith(
        localPath: canonicalPath,
        downloadStatus: 'done',
        contentHash:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        encryptionKeyBase64: 'disappearing-key',
        encryptionNonce: 'disappearing-nonce',
        encryptionScheme: 'blob_aes_gcm_v1',
      ),
      owner: MediaOwnerLane.direct,
    );
    final completed = await row(attachmentId);
    expect(completed['download_status'], 'done');
    expect(completed['local_path'], canonicalPath);
    expect(completed['content_hash'], isNotNull);
    expect(
      await fixture.repo.deleteAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      ),
      1,
    );
    expect(
      await fixture.db.query(
        'media_attachments',
        where: 'id = ?',
        whereArgs: const <Object?>[attachmentId],
      ),
      isEmpty,
    );
  });

  test('legacy ordinary completed upload retains generic persistence', () async {
    const messageId = 'writer-legacy-ordinary';
    const attachmentId = 'writer-legacy-ordinary-att';
    await fixture.seedDirectParent(
      messageId,
      contactPeerId: 'writer-legacy-contact',
    );
    await fixture.db.update(
      'messages',
      const <String, Object?>{'is_incoming': 0, 'status': 'sending'},
      where: 'id = ?',
      whereArgs: const <Object?>[messageId],
    );
    final pending = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 4,
      mediaType: 'image',
      localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
      downloadStatus: 'upload_pending',
      createdAt: '2026-07-20T00:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );
    await fixture.repo.saveAttachment(pending, owner: MediaOwnerLane.direct);
    final canonicalPath = MediaFilePathConvention.relativePathForAttachment(
      contactPeerId: 'writer-legacy-contact',
      blobId: attachmentId,
      mime: pending.mime,
    );
    await fixture.repo.saveAttachment(
      pending.copyWith(
        localPath: canonicalPath,
        downloadStatus: 'done',
        contentHash:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        encryptionKeyBase64: 'legacy-key',
        encryptionNonce: 'legacy-nonce',
        encryptionScheme: 'blob_aes_gcm_v1',
      ),
      owner: MediaOwnerLane.direct,
    );

    final completed = await row(attachmentId);
    expect(completed['download_status'], 'done');
    expect(completed['local_path'], canonicalPath);
    expect(completed['content_hash'], isNotNull);
  });

  test(
    'typed cancel and delete expose active, terminal, and applied outcomes',
    () async {
      final mediaFileManager = FakeMediaFileManager();
      final seeded = await seedPrivatePending(state: 'opening');
      final hydrated = (await fixture.repo.getAttachmentsForMessage(
        seeded.messageId,
        owner: MediaOwnerLane.direct,
      )).single;

      expect(
        await fixture.repo.applyOutgoingDirectPrivateNonCompletionMutation(
          hydrated.copyWith(downloadStatus: 'upload_cancelled'),
        ),
        OutgoingDirectPrivateNonCompletionMutationOutcome.notAppliedActiveLease,
      );
      expect(
        await fixture.repo
            .deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
              seeded.messageId,
              mediaFileManager: mediaFileManager,
            ),
        OutgoingDirectPrivateNonCompletionMutationOutcome.notAppliedActiveLease,
      );
      expect((await row(seeded.id))['download_status'], 'upload_pending');

      await fixture.db.update(
        'messages',
        <String, Object?>{
          'private_media_state': 'consumed',
          'private_media_terminal_at_ms': 1200,
        },
        where: 'id = ?',
        whereArgs: <Object?>[seeded.messageId],
      );
      final transferToken = directPrivateMediaTransferRegistry.tryBegin(
        seeded.id,
      );
      expect(transferToken, isNotNull);
      expect(
        await fixture.repo
            .deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
              seeded.messageId,
              mediaFileManager: mediaFileManager,
            ),
        OutgoingDirectPrivateNonCompletionMutationOutcome.notAppliedActiveLease,
      );
      expect((await row(seeded.id))['download_status'], 'upload_pending');
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(seeded.id),
        ),
        isTrue,
      );
      directPrivateMediaTransferRegistry.end(seeded.id, transferToken!);
      expect(
        await fixture.repo.applyOutgoingDirectPrivateNonCompletionMutation(
          hydrated.copyWith(downloadStatus: 'upload_cancelled'),
        ),
        OutgoingDirectPrivateNonCompletionMutationOutcome.terminalNoOp,
      );

      await fixture.db.update(
        'messages',
        <String, Object?>{
          'private_media_state': 'available',
          'private_media_revealed_at_ms': null,
          'private_media_terminal_at_ms': null,
        },
        where: 'id = ?',
        whereArgs: <Object?>[seeded.messageId],
      );
      expect(
        await fixture.repo.applyOutgoingDirectPrivateNonCompletionMutation(
          hydrated.copyWith(downloadStatus: 'upload_cancelled'),
        ),
        OutgoingDirectPrivateNonCompletionMutationOutcome.applied,
      );
      expect(
        await fixture.repo
            .deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
              seeded.messageId,
              mediaFileManager: _ThrowingPendingDeleteMediaFileManager(),
            ),
        OutgoingDirectPrivateNonCompletionMutationOutcome.refused,
      );
      expect((await row(seeded.id))['download_status'], 'upload_cancelled');
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(seeded.id),
        ),
        isTrue,
      );
      expect(
        await fixture.repo
            .deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
              seeded.messageId,
              mediaFileManager: mediaFileManager,
            ),
        OutgoingDirectPrivateNonCompletionMutationOutcome.applied,
      );
      expect(
        await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: <Object?>[seeded.id],
        ),
        isEmpty,
      );
      expect(
        await fixture.secureKeyStore.containsKey(
          mediaAttachmentEncryptionKeyStoreName(seeded.id),
        ),
        isFalse,
      );
    },
  );

  test('generic failure save mutates only exact available authority', () async {
    final seeded = await seedPrivatePending(state: 'opening');
    final hydrated = (await fixture.repo.getAttachmentsForMessage(
      seeded.messageId,
      owner: MediaOwnerLane.direct,
    )).single;
    final before = Map<String, Object?>.from(await row(seeded.id));
    final writesBefore = fixture.secureKeyStore.writtenKeys.length;

    await fixture.repo.saveAttachment(
      hydrated.copyWith(downloadStatus: 'upload_failed'),
      owner: MediaOwnerLane.direct,
    );

    expect(await row(seeded.id), before);
    expect(fixture.secureKeyStore.writtenKeys.length, writesBefore);

    await fixture.db.update(
      'messages',
      <String, Object?>{
        'private_media_state': 'available',
        'private_media_revealed_at_ms': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[seeded.messageId],
    );
    await fixture.repo.saveAttachment(
      hydrated.copyWith(downloadStatus: 'upload_failed'),
      owner: MediaOwnerLane.direct,
    );

    final applied = await row(seeded.id);
    expect(applied['download_status'], 'upload_failed');
    expect(applied['local_path'], seeded.localPath);
    expect(applied['encryption_key_base64'], before['encryption_key_base64']);
    expect(fixture.secureKeyStore.writtenKeys.length, writesBefore);
  });

  test(
    'generic save cannot mutate a completed private row or key during an active lease',
    () async {
      const contactPeerId = 'writer-completed-active-contact';
      final seeded = await seedPrivatePending(
        messageId: 'writer-completed-active',
        attachmentId: 'writer-completed-active-att',
        state: 'opening',
        contactPeerId: contactPeerId,
      );
      final canonicalPath = MediaFilePathConvention.relativePathForAttachment(
        contactPeerId: contactPeerId,
        blobId: seeded.id,
        mime: seeded.mime,
      );
      await fixture.db.update(
        'media_attachments',
        <String, Object?>{
          'local_path': canonicalPath,
          'download_status': 'done',
        },
        where: 'id = ?',
        whereArgs: <Object?>[seeded.id],
      );
      final completed = await fixture.repo.getAttachmentById(seeded.id);
      final before = Map<String, Object?>.from(await row(seeded.id));
      final writesBefore = fixture.secureKeyStore.writtenKeys.length;

      await fixture.repo.saveAttachment(
        completed!.copyWith(
          downloadStatus: 'upload_failed',
          encryptionKeyBase64: 'must-not-rotate',
        ),
        owner: MediaOwnerLane.direct,
      );

      expect(await row(seeded.id), before);
      expect(fixture.secureKeyStore.writtenKeys.length, writesBefore);
      expect(
        await fixture.secureKeyStore.read(
          mediaAttachmentEncryptionKeyStoreName(seeded.id),
        ),
        'writer-key',
      );
    },
  );

  test('manual rearm and bulk failure refuse active private leases', () async {
    final seeded = await seedPrivatePending(
      state: 'viewing',
      parentStatus: 'failed',
      attachmentStatus: 'upload_failed',
      retryCount: kMaxUploadRetries,
    );

    final rearmed = await dbRearmDirectUploadRetryForManualRetry(
      fixture.db,
      messageId: seeded.messageId,
      attachments: <ManualUploadRetryAttachmentExpectation>[
        ManualUploadRetryAttachmentExpectation(
          attachmentId: seeded.id,
          storedLocalPath: seeded.localPath!,
          downloadStatus: 'upload_failed',
          uploadRetryCount: kMaxUploadRetries,
        ),
      ],
    );
    expect(rearmed, isFalse);
    expect((await row(seeded.id))['download_status'], 'upload_failed');

    await fixture.db.update(
      'media_attachments',
      <String, Object?>{'download_status': 'upload_pending'},
      where: 'id = ?',
      whereArgs: <Object?>[seeded.id],
    );
    final marked = await dbMarkUploadPendingAttachmentsFailedForMessage(
      fixture.db,
      seeded.messageId,
      ownerLane: MediaOwnerLane.direct.dbValue,
    );
    expect(marked, 0);
    expect((await row(seeded.id))['download_status'], 'upload_pending');
  });

  test(
    'generic message/contact bulk deletion never removes private rows',
    () async {
      final private = await seedPrivatePending(state: 'available');
      await fixture.seedDirectParent(
        'writer-ordinary',
        contactPeerId: 'writer-contact',
      );
      await dbInsertMediaAttachment(
        fixture.db,
        MediaAttachment(
          id: 'writer-ordinary-att',
          messageId: 'writer-ordinary',
          mime: 'image/jpeg',
          size: 4,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: '2026-07-20T00:00:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        ).toMap(),
      );

      expect(
        await dbDeleteMediaForMessage(
          fixture.db,
          private.messageId,
          ownerLane: MediaOwnerLane.direct.dbValue,
        ),
        0,
      );
      expect(await row(private.id), isNotEmpty);

      expect(await dbDeleteMediaForContact(fixture.db, 'writer-contact'), 1);
      expect(await row(private.id), isNotEmpty);
      expect(
        await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: const <Object?>['writer-ordinary-att'],
        ),
        isEmpty,
      );
    },
  );

  test(
    'message column/full saves preserve lifecycle and deletion intent',
    () async {
      final seeded = await seedPrivatePending(state: 'opening');
      await fixture.db.update(
        'messages',
        <String, Object?>{'deleted_at': '2026-07-20T01:00:00.000Z'},
        where: 'id = ?',
        whereArgs: <Object?>[seeded.messageId],
      );
      final stale =
          Map<String, Object?>.from(
              (await fixture.db.query(
                'messages',
                where: 'id = ?',
                whereArgs: <Object?>[seeded.messageId],
              )).single,
            )
            ..['private_media_state'] = 'available'
            ..['private_media_revealed_at_ms'] = null
            ..['private_media_terminal_at_ms'] = null
            ..['deleted_at'] = null
            ..['status'] = 'failed';

      await dbInsertMessage(fixture.db, stale);
      await dbUpdateWireEnvelope(
        fixture.db,
        seeded.messageId,
        'fresh-envelope',
      );
      await dbUpdateMessageStatus(fixture.db, seeded.messageId, 'inboxed');

      final persisted = (await fixture.db.query(
        'messages',
        where: 'id = ?',
        whereArgs: <Object?>[seeded.messageId],
      )).single;
      expect(persisted['private_media_state'], 'opening');
      expect(persisted['private_media_revealed_at_ms'], 1100);
      expect(persisted['deleted_at'], '2026-07-20T01:00:00.000Z');
      expect(persisted['wire_envelope'], isNull);
      expect(persisted['status'], 'failed');
    },
  );
}

class _ThrowingPendingDeleteMediaFileManager extends FakeMediaFileManager {
  @override
  Future<void> deleteOwnedPendingUploadFilesForMessage({
    required String messageId,
    required Iterable<String?> storedPaths,
  }) async {
    throw FileSystemException('injected pending-file deletion failure');
  }
}
