import 'package:flutter_app/core/database/helpers/group_media_key_snapshot.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../core/bridge/fake_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/database/direct_inbox_custody_outbox_contract.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_media_deletion_journal_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show
        DirectMediaFanoutStageAuthority,
        DirectMediaFanoutTargetBinding,
        IncomingDirectMediaCaptionEditOutcome,
        OutgoingDirectMediaCaptionEditLane;
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_terminalization.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/incoming_direct_media_blob_custody_result.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/features/conversation/application/drain_direct_media_blob_custody_use_case.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../../shared/fakes/recording_fake_bridge.dart';

class _FailFirstDeleteSecureKeyStore extends RecordingSecureKeyStore {
  String? failOnceFor;

  @override
  Future<void> delete(String key) async {
    if (failOnceFor == key) {
      failOnceFor = null;
      throw StateError('injected first secure-key delete failure');
    }
    await super.delete(key);
  }
}

class _FailingSnapshotSecureKeyStore extends RecordingSecureKeyStore {
  bool failContains = false;
  bool failRead = false;

  @override
  Future<bool> containsKey(String key) {
    if (failContains) {
      throw StateError('injected containsKey failure');
    }
    return super.containsKey(key);
  }

  @override
  Future<String?> read(String key) {
    if (failRead) {
      throw StateError('injected read failure');
    }
    return super.read(key);
  }
}

class _IncomingKeyReadGateSecureKeyStore extends RecordingSecureKeyStore {
  bool pauseNextRead = false;
  final readEntered = Completer<void>();
  final releaseRead = Completer<void>();

  @override
  Future<String?> read(String key) async {
    final value = await super.read(key);
    if (pauseNextRead) {
      pauseNextRead = false;
      readEntered.complete();
      await releaseRead.future;
    }
    return value;
  }
}

const _retryCounterColumns = <String>{
  'upload_retry_count',
  'download_retry_count',
};

/// Scoped test double for the only SQLite-default behavior that the Plan 269
/// widget fixtures need to model. A missing counter key gets the production
/// schema default; an explicit SQL NULL remains invalid.
Map<String, Object?> _applyProductionRetryCounterDefaults(
  Map<String, Object?> row,
) {
  final normalized = Map<String, Object?>.of(row);
  for (final column in _retryCounterColumns) {
    if (!normalized.containsKey(column)) {
      normalized[column] = 0;
    } else if (normalized[column] == null) {
      throw ArgumentError.value(
        normalized[column],
        column,
        'production schema rejects an explicit null retry counter',
      );
    }
  }
  return normalized;
}

void main() {
  // 228: the repository fixture is a REAL in-memory database built through
  // the shared production registry (current schema), not a hand-rolled map
  // store — so owner filtering, the CHECK constraint and the atomic
  // local-state-preserving merge are exercised for real.
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async {
    fixture = await MediaRepositoryRealDbFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  _registerStrictGroupMediaKeyBoundaryTests(() => fixture);

  group('incoming group key boundary', () {
    const groupId = 'incoming-key-group';
    const messageId = 'incoming-key-message';
    const attachmentId = 'incoming-key-attachment';
    const createdAt = '2026-09-10T00:00:00.000Z';
    const key = 'incoming-exact-key';
    const expiresAtMs = 1930000000000;
    final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);

    Future<({MediaAttachment attachment, DirectMediaBlobCustodyRow custody})>
    seed(String storage) async {
      final hash = 'cd' * 32;
      final fingerprint = computeGroupMediaBlobCustodyFingerprint(
        groupId: groupId,
        messageId: messageId,
        attachmentId: attachmentId,
        custodyBlobId: 'incoming-key-custody',
        contentHash: hash,
        ciphertextSize: 80,
        recipientPeerIds: const <String>['incoming-key-recipient'],
      );
      final attachment = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 64,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: createdAt,
        contentHash: hash,
        encryptionKeyBase64: key,
        encryptionNonce: 'incoming-exact-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        groupMediaBlobCustodyFingerprint: fingerprint,
        ownerLane: MediaOwnerLane.group,
      );
      final custody = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        ownerLane: MediaBlobCustodyOwnerLane.group,
        groupId: groupId,
        custodyBlobId: 'incoming-key-custody',
        direction: DirectMediaBlobCustodyDirection.incoming,
        state: DirectMediaBlobCustodyState.incomingCommitted,
        inboxCustodyIncarnationId: null,
        recipientPeerId: null,
        ciphertextRelativePath: null,
        custodyKind: kGroupMediaBlobCustodyKind,
        contentHash: hash,
        ciphertextSize: 80,
        expiresAtMs: expiresAtMs,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      await fixture.seedGroupParent(messageId, groupId: groupId);
      if (storage == 'legacy') {
        await fixture.db.insert('media_attachments', attachment.toMap());
      } else {
        await fixture.repo.saveAttachment(
          attachment,
          owner: MediaOwnerLane.group,
        );
      }
      await fixture.db.insert(kDirectMediaBlobCustodyTable, custody.toMap());
      return (attachment: attachment, custody: custody);
    }

    Future<bool> commit(
      MediaAttachment attachment,
      DirectMediaBlobCustodyRow custody,
    ) => fixture.repo.commitIncomingGroupMediaBlobLocalPath(
      expectedAttachment: attachment,
      expectedCustody: custody,
      localPath: 'media/$groupId/$attachmentId.jpg',
      sourceRelayPeerId: 'incoming-key-relay',
      updatedAt: '2026-09-10T00:00:01.000Z',
      nowMs: 1800000000000,
    );

    Future<void> expectPending() async {
      expect(
        (await fixture.rawAttachmentRow(attachmentId))!['download_status'],
        'pending',
      );
      final rows = await fixture.repo.loadGroupMediaBlobCustodyForMessage(
        groupId: groupId,
        messageId: messageId,
      );
      expect(rows.single.state, DirectMediaBlobCustodyState.incomingCommitted);
      expect(rows.single.custodyRelayPeerId, isNull);
    }

    for (final storage in <String>['legacy', 'secure']) {
      test(
        '$storage exact key preserves its stored representation after commit',
        () async {
          final input = await seed(storage);
          final stored = (await fixture.rawAttachmentRow(
            attachmentId,
          ))!['encryption_key_base64'];
          final writes = fixture.secureKeyStore.writtenKeys.length;
          expect(await commit(input.attachment, input.custody), isTrue);
          expect(
            (await fixture.rawAttachmentRow(
              attachmentId,
            ))!['encryption_key_base64'],
            stored,
          );
          expect(fixture.secureKeyStore.writtenKeys, hasLength(writes));
          final rows = await fixture.repo.loadGroupMediaBlobCustodyForMessage(
            groupId: groupId,
            messageId: messageId,
          );
          expect(
            rows.single.state,
            DirectMediaBlobCustodyState.incomingAckPending,
          );
          expect(rows.single.custodyRelayPeerId, 'incoming-key-relay');
        },
      );

      for (final mismatch in <String>[
        'key',
        'nonce',
        'hash',
        'size',
        'waveform',
        'fingerprint',
        'owner',
        'message',
        'custody',
      ]) {
        test(
          '$storage stale $mismatch refuses without promotion or ACK',
          () async {
            final input = await seed(storage);
            var expected = input.attachment;
            var custody = input.custody;
            switch (mismatch) {
              case 'key':
                expected = expected.copyWith(encryptionKeyBase64: 'wrong-key');
              case 'nonce':
                expected = expected.copyWith(encryptionNonce: 'wrong-nonce');
              case 'hash':
                expected = expected.copyWith(contentHash: 'ef' * 32);
              case 'size':
                expected = expected.copyWith(size: 65);
              case 'waveform':
                expected = expected.copyWith(waveform: const <double>[0.5]);
              case 'fingerprint':
                expected = expected.copyWith(
                  groupMediaBlobCustodyFingerprint: 'ef' * 32,
                );
              case 'owner':
                expected = expected.copyWith(ownerLane: MediaOwnerLane.direct);
              case 'message':
                expected = expected.copyWith(messageId: 'other-message');
              case 'custody':
                custody = custody.copyWith(updatedAt: '2026-09-10T00:00:02.000Z');
            }
            expect(await commit(expected, custody), isFalse);
            await expectPending();
          },
        );
      }
    }

    test('secure missing key refuses without promotion', () async {
      final input = await seed('secure');
      await fixture.secureKeyStore.delete(keyName);
      expect(await commit(input.attachment, input.custody), isFalse);
      await expectPending();
    });

    test('secure rotated key refuses without promotion', () async {
      final input = await seed('secure');
      await fixture.secureKeyStore.write(keyName, 'rotated-key');
      expect(await commit(input.attachment, input.custody), isFalse);
      await expectPending();
    });

    test('noncanonical reference with matching value still refuses', () async {
      final input = await seed('secure');
      const otherName = 'another-attachment-key';
      await fixture.secureKeyStore.write(otherName, key);
      await fixture.db.update(
        'media_attachments',
        <String, Object?>{
          'encryption_key_base64': secureStoreReferenceForKey(otherName),
        },
        where: 'id = ?',
        whereArgs: <Object?>[attachmentId],
      );
      expect(await commit(input.attachment, input.custody), isFalse);
      await expectPending();
    });

    test('secure read error propagates and retains pending custody', () async {
      await fixture.dispose();
      final store = _FailingSnapshotSecureKeyStore();
      fixture = await MediaRepositoryRealDbFixture.create(
        secureKeyStore: store,
      );
      final input = await seed('secure');
      store.failRead = true;
      await expectLater(
        commit(input.attachment, input.custody),
        throwsStateError,
      );
      await expectPending();
      store.failRead = false;
      expect(await commit(input.attachment, input.custody), isTrue);
    });

    test(
      'existing plaintext row commits after database reopen without rewriting its key',
      () async {
        await fixture.dispose();
        final dir = Directory.systemTemp.createTempSync(
          'incoming-group-key-reopen-',
        );
        addTearDown(() => dir.delete(recursive: true));
        fixture = await MediaRepositoryRealDbFixture.create(
          databasePath: '${dir.path}/identity.db',
        );
        final input = await seed('legacy');
        fixture = await fixture.reopen();
        expect(await commit(input.attachment, input.custody), isTrue);
        expect(
          (await fixture.rawAttachmentRow(
            attachmentId,
          ))!['encryption_key_base64'],
          key,
        );
        expect(fixture.secureKeyStore.writtenKeys, isEmpty);
      },
    );

    test(
      'media ownership holds from secure read through the SQL commit',
      () async {
        await fixture.dispose();
        final lock = MediaAttachmentLifecycleLock();
        final store = _IncomingKeyReadGateSecureKeyStore();
        fixture = await MediaRepositoryRealDbFixture.create(
          secureKeyStore: store,
          lifecycleLock: lock,
        );
        final input = await seed('secure');
        store.pauseNextRead = true;
        final committing = commit(input.attachment, input.custody);
        await store.readEntered.future;
        var mutationEntered = false;
        Object? statusAtMutation;
        final mutation = Zone.root.run(
          () => lock.synchronized(attachmentId, () async {
            mutationEntered = true;
            statusAtMutation = (await fixture.rawAttachmentRow(
              attachmentId,
            ))!['download_status'];
            await store.write(keyName, 'post-commit-rotation');
          }),
        );
        await Future<void>(() {});
        expect(mutationEntered, isFalse);
        store.releaseRead.complete();
        expect(await committing, isTrue);
        await mutation;
        expect(mutationEntered, isTrue);
        expect(statusAtMutation, 'done');
      },
    );
  });

  Future<Map<String, Object?>?> rawRow(String id) =>
      fixture.rawAttachmentRow(id);

  MediaAttachment makeAttachment({
    String id = 'blob-001',
    String messageId = 'msg-001',
    String mime = 'image/jpeg',
    int size = 245000,
    String mediaType = 'image',
    int? width = 1920,
    int? height = 1080,
    int? durationMs,
    String downloadStatus = 'pending',
    String createdAt = '2026-02-20T10:00:00.000Z',
    String? localPath,
    String? encryptionKeyBase64,
    String? encryptionNonce,
    String? encryptionScheme,
    int? downloadRetryCount,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: size,
      mediaType: mediaType,
      width: width,
      height: height,
      durationMs: durationMs,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: createdAt,
      encryptionKeyBase64: encryptionKeyBase64,
      encryptionNonce: encryptionNonce,
      encryptionScheme: encryptionScheme,
      downloadRetryCount: downloadRetryCount,
    );
  }

  Future<void> saveDirect(MediaAttachment attachment) =>
      fixture.repo.saveAttachment(attachment, owner: MediaOwnerLane.direct);

  test(
    'TC-365-01a direct drains cannot observe or retire group custody',
    () async {
      const messageId = 'tc365-direct-isolation-message';
      const attachmentId = 'tc365-direct-isolation-attachment';
      final groupRow = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        ownerLane: MediaBlobCustodyOwnerLane.group,
        groupId: 'tc365-direct-isolation-group',
        direction: DirectMediaBlobCustodyDirection.outgoing,
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        inboxCustodyIncarnationId: null,
        recipientPeerId: 'tc365-physical-target',
        ciphertextRelativePath:
            'group_media_blob_custody_v1/identity-scope/group-scope/blob.blob',
        custodyKind: kGroupMediaBlobCustodyKind,
        contentHash: 'ef' * 32,
        ciphertextSize: 4096,
        expiresAtMs: null,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: '2026-08-14T12:00:00.000Z',
        updatedAt: '2026-08-14T12:00:00.000Z',
      );
      await fixture.db.insert('direct_media_blob_custody', groupRow.toMap());

      final direct = fixture.repo as DirectMediaBlobCustodyRepository;
      expect(
        await direct.loadDirectMediaBlobCustodyForMessage(messageId),
        isEmpty,
      );
      expect(
        await direct.loadDirectMediaBlobCustodyByStates(
          const <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingCleanupPending,
          },
        ),
        everyElement(
          isA<DirectMediaBlobCustodyRow>().having(
            (row) => row.ownerLane,
            'owner lane',
            MediaBlobCustodyOwnerLane.direct,
          ),
        ),
      );
      expect(
        await direct.deleteDirectMediaBlobCleanupPendingIfExact(groupRow),
        isFalse,
      );
      expect(
        await fixture.db.query(
          'direct_media_blob_custody',
          where: 'owner_lane = ? AND group_id = ? AND message_id = ?',
          whereArgs: const <Object?>[
            'group',
            'tc365-direct-isolation-group',
            messageId,
          ],
        ),
        hasLength(1),
      );
    },
  );

  test('TC-365-01a sole-group fresh custody stores secure references and '
      'compensates a refused SQL stage', () async {
    const groupId = 'tc365-sole-group';
    const messageId = 'tc365-sole-message';
    const attachmentId = 'tc365-sole-attachment';
    const custodyBlobId = 'gmb1-tc365-sole-blob';
    const rawKey = 'tc365-sole-raw-key';
    const hash =
        'abababababababababababababababababababababababababababababababab';
    const createdAt = '2026-08-14T12:00:00.000Z';
    await fixture.db.insert('groups', <String, Object?>{
      'id': groupId,
      'name': 'Sole group',
      'type': 'chat',
      'topic_name': 'topic-$groupId',
      'created_at': createdAt,
      'created_by': 'peer-self',
      'my_role': 'member',
    });
    final parent = GroupMessage(
      id: messageId,
      groupId: groupId,
      senderPeerId: 'peer-self',
      senderUsername: 'Self',
      text: '',
      timestamp: DateTime.parse(createdAt),
      status: 'sending',
      isIncoming: false,
      createdAt: DateTime.parse(createdAt),
    );
    final fingerprint = computeGroupMediaBlobCustodyFingerprint(
      groupId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      custodyBlobId: custodyBlobId,
      contentHash: hash,
      ciphertextSize: 48,
      recipientPeerIds: const <String>[],
    );
    final attachment = MediaAttachment(
      id: attachmentId,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 32,
      mediaType: 'image',
      localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
      downloadStatus: 'upload_pending',
      createdAt: createdAt,
      contentHash: hash,
      encryptionKeyBase64: rawKey,
      encryptionNonce: 'bm9uY2U=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      groupMediaBlobCustodyFingerprint: fingerprint,
      ownerLane: MediaOwnerLane.group,
    );
    final repository = fixture.repo as GroupMediaBlobCustodyRepository;
    expect(repository.supportsGroupMediaBlobCustody, isTrue);
    expect(
      await repository.stageFreshOutgoingGroupMediaBlobGeneration(
        parent: parent,
        attachments: <MediaAttachment>[attachment],
        custodyRows: const <DirectMediaBlobCustodyRow>[],
        custodyBlobIdsByAttachmentId: const <String, String>{
          attachmentId: custodyBlobId,
        },
      ),
      GroupMediaBlobCustodyStageOutcome.applied,
    );
    final raw = (await fixture.rawAttachmentRow(attachmentId))!;
    final secureKeyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
    expect(
      raw['encryption_key_base64'],
      secureStoreReferenceForKey(secureKeyName),
    );
    expect(raw['encryption_key_base64'], isNot(rawKey));
    expect(await fixture.secureKeyStore.read(secureKeyName), rawKey);
    final writesAfterFirstStage = fixture.secureKeyStore.writtenKeys.length;
    expect(
      await repository.stageFreshOutgoingGroupMediaBlobGeneration(
        parent: parent,
        attachments: <MediaAttachment>[attachment],
        custodyRows: const <DirectMediaBlobCustodyRow>[],
        custodyBlobIdsByAttachmentId: const <String, String>{
          attachmentId: custodyBlobId,
        },
      ),
      GroupMediaBlobCustodyStageOutcome.idempotent,
    );
    expect(
      fixture.secureKeyStore.writtenKeys,
      hasLength(writesAfterFirstStage),
    );

    const crossedMessageId = 'tc365-crossed-parent';
    const crossedAttachmentId = 'tc365-crossed-attachment';
    const previousKey = 'tc365-previous-stable-key';
    await fixture.seedGroupParent(crossedMessageId, groupId: groupId);
    final crossedKeyName = mediaAttachmentEncryptionKeyStoreName(
      crossedAttachmentId,
    );
    await fixture.secureKeyStore.write(crossedKeyName, previousKey);
    final crossedParent = GroupMessage(
      id: crossedMessageId,
      groupId: groupId,
      senderPeerId: 'peer-self',
      senderUsername: 'Self',
      text: 'crossed candidate',
      timestamp: DateTime.parse(createdAt),
      status: 'sending',
      isIncoming: false,
      createdAt: DateTime.parse(createdAt),
    );
    final crossedFingerprint = computeGroupMediaBlobCustodyFingerprint(
      groupId: groupId,
      messageId: crossedMessageId,
      attachmentId: crossedAttachmentId,
      custodyBlobId: 'gmb1-crossed',
      contentHash: hash,
      ciphertextSize: 48,
      recipientPeerIds: const <String>[],
    );
    final crossedAttachment = attachment.copyWith(
      id: crossedAttachmentId,
      messageId: crossedMessageId,
      encryptionKeyBase64: 'tc365-losing-raw-key',
      groupMediaBlobCustodyFingerprint: crossedFingerprint,
    );
    expect(
      await repository.stageFreshOutgoingGroupMediaBlobGeneration(
        parent: crossedParent,
        attachments: <MediaAttachment>[crossedAttachment],
        custodyRows: const <DirectMediaBlobCustodyRow>[],
        custodyBlobIdsByAttachmentId: const <String, String>{
          crossedAttachmentId: 'gmb1-crossed',
        },
      ),
      GroupMediaBlobCustodyStageOutcome.refused,
    );
    expect(await fixture.secureKeyStore.read(crossedKeyName), previousKey);
    expect(await fixture.rawAttachmentRow(crossedAttachmentId), isNull);
  });

  test('TC-365-01a group strict fingerprint refuses legacy fallback after '
      'custody retirement', () async {
    const groupId = 'tc365-no-demotion-group';
    const messageId = 'tc365-no-demotion-message';
    const attachmentId = 'tc365-no-demotion-attachment';
    await fixture.seedGroupParent(messageId, groupId: groupId);
    await fixture.repo.saveAttachment(
      makeAttachment(
        id: attachmentId,
        messageId: messageId,
        downloadStatus: kMediaDownloadStatusPending,
      ),
      owner: MediaOwnerLane.group,
    );
    await fixture.db.update(
      'media_attachments',
      <String, Object?>{'group_media_blob_custody_fingerprint': 'cd' * 32},
      where: 'id = ? AND message_id = ? AND owner_lane = ?',
      whereArgs: const <Object?>[attachmentId, messageId, 'group'],
    );

    final legacyRecovery =
        fixture.repo as RecoverableGroupMediaDownloadRepository;
    expect(
      await legacyRecovery.loadRecoverableGroupDownloadPage(limit: 25),
      isEmpty,
      reason:
          'the durable fingerprint stays a no-demotion boundary after the '
          'strict custody row has retired',
    );
    expect(
      (await fixture.rawAttachmentRow(
        attachmentId,
      ))!['group_media_blob_custody_fingerprint'],
      'cd' * 32,
    );
  });

  Future<
    ({
      ConversationMessage parent,
      List<MediaAttachment> attachments,
      List<DirectMediaBlobCustodyRow> rows,
      List<DirectMediaBlobArtifact> artifacts,
    })
  >
  stageOutgoingBlobGeneration({
    required DirectMediaBlobArtifactStore store,
    required Directory sourceDirectory,
    required String identityPeerId,
    required String messageId,
    required List<String> attachmentIds,
    String createdAt = '2026-08-08T11:00:00.000Z',
  }) async {
    final parent = ConversationMessage(
      id: messageId,
      contactPeerId: 'tc347-terminal-recipient',
      senderPeerId: identityPeerId,
      text: 'terminalization fixture',
      timestamp: createdAt,
      status: 'sending',
      isIncoming: false,
      createdAt: createdAt,
      directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
        messageId: messageId,
        attachmentIds: attachmentIds,
      ),
    );
    final pending = <MediaAttachment>[];
    final prepared = <MediaAttachment>[];
    final rows = <DirectMediaBlobCustodyRow>[];
    final artifacts = <DirectMediaBlobArtifact>[];
    for (var index = 0; index < attachmentIds.length; index++) {
      final attachmentId = attachmentIds[index];
      final attachment = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 40 + index,
        mediaType: 'image',
        localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
        downloadStatus: 'upload_pending',
        createdAt: createdAt,
        ownerLane: MediaOwnerLane.direct,
      );
      final source = File(
        '${sourceDirectory.path}/$messageId-$attachmentId.enc',
      );
      final bytes = <int>[11 + index, 21 + index, 31 + index, 41 + index];
      await source.writeAsBytes(bytes, flush: true);
      addTearDown(() async {
        if (await source.exists()) await source.delete();
      });
      final hash = sha256.convert(bytes).toString();
      final artifact = await store.persistCandidate(
        identityPeerId: identityPeerId,
        attachmentId: attachmentId,
        encryptedSourcePath: source.path,
        expectedContentHash: hash,
      );
      pending.add(attachment);
      prepared.add(
        attachment.copyWith(
          contentHash: hash,
          encryptionKeyBase64: 'tc347-terminal-key-$attachmentId',
          encryptionNonce: 'tc347-terminal-nonce-$attachmentId',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ),
      );
      rows.add(
        DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingPrepared,
          inboxCustodyIncarnationId: null,
          recipientPeerId: parent.contactPeerId,
          ciphertextRelativePath: artifact.relativePath,
          contentHash: artifact.contentHash,
          ciphertextSize: artifact.ciphertextSize,
          expiresAtMs: null,
          custodyRelayPeerId: null,
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      artifacts.add(artifact);
    }
    await fixture.messageRepo.saveMessage(parent);
    for (final attachment in pending) {
      await fixture.repo.saveAttachment(
        attachment,
        owner: MediaOwnerLane.direct,
      );
    }
    final staged = await (fixture.repo as DirectMediaBlobCustodyRepository)
        .stageOutgoingDirectMediaBlobGeneration(
          expectedParent: parent,
          expectedAttachments: pending,
          preparedAttachments: prepared,
          custodyRows: rows,
        );
    expect(staged.outcome.name, 'applied');
    return (
      parent: parent,
      attachments: staged.attachments,
      rows: staged.custodyRows,
      artifacts: artifacts,
    );
  }

  group('MediaAttachmentRepositoryImpl', () {
    test(
      'TC-348-02b fresh blob owner resolves commit ambiguity before key compensation',
      () async {
        ({
          ConversationMessage parent,
          MediaAttachment pending,
          MediaAttachment prepared,
          DirectMediaBlobCustodyRow custody,
        })
        freshCandidate({
          required String suffix,
          String hashDigit = 'a',
          String? key,
          ConversationMessage? parentOverride,
          MediaAttachment? pendingOverride,
        }) {
          final messageId = parentOverride?.id ?? 'tc348-repo-$suffix';
          final attachmentId =
              pendingOverride?.id ?? 'tc348-repo-$suffix-attachment';
          const createdAt = '2026-08-08T15:30:00.000Z';
          final parent =
              parentOverride ??
              ConversationMessage(
                id: messageId,
                contactPeerId: 'tc348-repo-recipient-$suffix',
                senderPeerId: 'tc348-repo-local',
                text: 'fresh repository ambiguity',
                timestamp: createdAt,
                status: 'sending',
                isIncoming: false,
                createdAt: createdAt,
                directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
                  messageId: messageId,
                  attachmentIds: <String>[attachmentId],
                ),
                dedupKey: messageId,
              );
          final pending =
              pendingOverride ??
              MediaAttachment(
                id: attachmentId,
                messageId: messageId,
                mime: 'image/jpeg',
                size: 31,
                mediaType: 'image',
                localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
                downloadStatus: 'upload_pending',
                createdAt: createdAt,
                ownerLane: MediaOwnerLane.direct,
              );
          final hash = hashDigit * 64;
          final prepared = pending.copyWith(
            contentHash: hash,
            encryptionKeyBase64: key ?? 'tc348-key-$suffix-$hashDigit',
            encryptionNonce: 'tc348-nonce-$suffix-$hashDigit',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          );
          return (
            parent: parent,
            pending: pending,
            prepared: prepared,
            custody: DirectMediaBlobCustodyRow(
              attachmentId: attachmentId,
              messageId: messageId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: parent.contactPeerId,
              ciphertextRelativePath:
                  'direct_media_blob_custody_v1/${'2' * 64}/$attachmentId.blob',
              contentHash: hash,
              ciphertextSize: 47,
              expiresAtMs: null,
              custodyRelayPeerId: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          );
        }

        Future<FreshOutgoingDirectMediaBlobGenerationStageResult> stageFresh(
          ({
            ConversationMessage parent,
            MediaAttachment pending,
            MediaAttachment prepared,
            DirectMediaBlobCustodyRow custody,
          })
          candidate,
        ) => (fixture.repo as FreshOutgoingDirectMediaBlobGenerationRepository)
            .stageFreshOutgoingDirectMediaBlobGeneration(
              parent: candidate.parent,
              expectedAttachments: <MediaAttachment>[candidate.pending],
              preparedAttachments: <MediaAttachment>[candidate.prepared],
              custodyRows: <DirectMediaBlobCustodyRow>[candidate.custody],
            );

        await fixture.dispose();
        var throwAfterFirstCommit = true;
        fixture = await MediaRepositoryRealDbFixture.create(
          dbStageFreshOutgoingDirectMediaBlobGenerationAround: (stage) async {
            final result = await stage();
            if (throwAfterFirstCommit) {
              throwAfterFirstCommit = false;
              throw StateError('injected wrapper failure after SQLite commit');
            }
            return result;
          },
        );
        final winner = freshCandidate(suffix: 'commit-winner');
        final committed = await stageFresh(winner);
        expect(committed.hasDurableAuthority, isTrue);
        expect(committed.outcome.name, 'applied');
        expect(committed.attachments, hasLength(1));
        expect(committed.attachments.single.contentHash, 'a' * 64);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(winner.pending.id),
          ),
          winner.prepared.encryptionKeyBase64,
          reason:
              'a real committed candidate keeps its stable key after the '
              'wrapper throws',
        );

        final writesAfterWinner = fixture.secureKeyStore.writtenKeys.length;
        final loser = freshCandidate(
          suffix: 'losing-candidate',
          hashDigit: 'b',
          parentOverride: winner.parent,
          pendingOverride: winner.pending,
        );
        final adopted = await stageFresh(loser);
        expect(adopted.outcome.name, 'idempotent');
        expect(adopted.attachments.single.contentHash, 'a' * 64);
        expect(
          adopted.attachments.single.encryptionKeyBase64,
          winner.prepared.encryptionKeyBase64,
        );
        expect(
          fixture.secureKeyStore.writtenKeys,
          hasLength(writesAfterWinner),
          reason: 'a losing candidate must not publish its key',
        );

        final rejected = freshCandidate(suffix: 'precommit-rejection');
        await fixture.messageRepo.saveMessage(rejected.parent);
        final keyName = mediaAttachmentEncryptionKeyStoreName(
          rejected.pending.id,
        );
        await fixture.secureKeyStore.write(keyName, 'previous-stable-key');
        final refused = await stageFresh(rejected);
        expect(refused.hasDurableAuthority, isFalse);
        expect(refused.outcome.name, 'refused');
        expect(
          await fixture.secureKeyStore.read(keyName),
          'previous-stable-key',
          reason: 'a proven pre-commit refusal compensates the candidate key',
        );
        expect(
          await fixture.repo.loadDirectMediaBlobCustodyForMessage(
            rejected.parent.id,
          ),
          isEmpty,
        );

        await fixture.dispose();
        final hydrationStore = _FailingSnapshotSecureKeyStore()
          ..failRead = true;
        fixture = await MediaRepositoryRealDbFixture.create(
          secureKeyStore: hydrationStore,
        );
        final hydrationCandidate = freshCandidate(suffix: 'hydration-failure');
        final authorityOnly = await stageFresh(hydrationCandidate);
        expect(authorityOnly.hasDurableAuthority, isTrue);
        expect(authorityOnly.attachments, isEmpty);
        expect(
          await fixture.repo.loadDirectMediaBlobCustodyForMessage(
            hydrationCandidate.parent.id,
          ),
          hasLength(1),
        );
        hydrationStore.failRead = false;
        expect(
          (await fixture.repo.getAttachmentById(
            hydrationCandidate.pending.id,
          ))?.encryptionKeyBase64,
          hydrationCandidate.prepared.encryptionKeyBase64,
          reason: 'post-commit hydration failure retains the exact winner key',
        );
      },
    );

    test(
      'TC-350-02b fresh forwarded repository requires exact authorization token',
      () async {
        const forwardToken = 'tc350-repo-forward-token';
        ({
          ConversationMessage parent,
          MediaAttachment pending,
          MediaAttachment prepared,
          DirectMediaBlobCustodyRow custody,
        })
        forwardCandidate({
          required String suffix,
          String? dedupKeyOverride,
          bool isForwarded = true,
        }) {
          final messageId = 'tc350-repo-$suffix';
          final attachmentId = 'tc350-repo-$suffix-attachment';
          const createdAt = '2026-08-09T15:30:00.000Z';
          final parent = ConversationMessage(
            id: messageId,
            contactPeerId: 'tc350-repo-recipient-$suffix',
            senderPeerId: 'tc350-repo-local',
            text: 'forwarded repository media',
            timestamp: createdAt,
            status: 'sending',
            isIncoming: false,
            createdAt: createdAt,
            directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
              messageId: messageId,
              attachmentIds: <String>[attachmentId],
            ),
            dedupKey: dedupKeyOverride ?? forwardToken,
            isForwarded: isForwarded,
          );
          final pending = MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 31,
            mediaType: 'image',
            localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
            downloadStatus: 'upload_pending',
            createdAt: createdAt,
            ownerLane: MediaOwnerLane.direct,
          );
          final hash = 'd' * 64;
          return (
            parent: parent,
            pending: pending,
            prepared: pending.copyWith(
              contentHash: hash,
              encryptionKeyBase64: 'tc350-key-$suffix',
              encryptionNonce: 'tc350-nonce-$suffix',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            custody: DirectMediaBlobCustodyRow(
              attachmentId: attachmentId,
              messageId: messageId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: parent.contactPeerId,
              ciphertextRelativePath:
                  'direct_media_blob_custody_v1/${'3' * 64}/$attachmentId.blob',
              contentHash: hash,
              ciphertextSize: 47,
              expiresAtMs: null,
              custodyRelayPeerId: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
          );
        }

        Future<FreshOutgoingDirectMediaBlobGenerationStageResult> stageFresh(
          ({
            ConversationMessage parent,
            MediaAttachment pending,
            MediaAttachment prepared,
            DirectMediaBlobCustodyRow custody,
          })
          candidate, {
          required String? authorizedForwardDedupKey,
        }) => (fixture.repo as FreshOutgoingDirectMediaBlobGenerationRepository)
            .stageFreshOutgoingDirectMediaBlobGeneration(
              parent: candidate.parent,
              expectedAttachments: <MediaAttachment>[candidate.pending],
              preparedAttachments: <MediaAttachment>[candidate.prepared],
              custodyRows: <DirectMediaBlobCustodyRow>[candidate.custody],
              authorizedForwardDedupKey: authorizedForwardDedupKey,
            );

        // The one authorized forwarded alternative applies.
        final authorized = forwardCandidate(suffix: 'authorized');
        final applied = await stageFresh(
          authorized,
          authorizedForwardDedupKey: forwardToken,
        );
        expect(applied.outcome.name, 'applied');
        expect(applied.hasDurableAuthority, isTrue);
        final durable = await fixture.messageRepo.getMessage(
          authorized.parent.id,
        );
        expect(durable?.isForwarded, isTrue);
        expect(durable?.dedupKey, forwardToken);

        // Every crossed shape refuses with no parent, attachment, key, or row.
        final refusals =
            <
              String,
              ({
                ConversationMessage parent,
                MediaAttachment pending,
                String? token,
              })
            >{
              'no authorization for a forwarded parent': (
                parent: forwardCandidate(suffix: 'no-auth').parent,
                pending: forwardCandidate(suffix: 'no-auth').pending,
                token: null,
              ),
              'blank authorization': (
                parent: forwardCandidate(suffix: 'blank-auth').parent,
                pending: forwardCandidate(suffix: 'blank-auth').pending,
                token: '   ',
              ),
              'mismatched authorization': (
                parent: forwardCandidate(suffix: 'mismatch').parent,
                pending: forwardCandidate(suffix: 'mismatch').pending,
                token: 'tc350-other-token',
              ),
              'authorization on a non-forwarded parent': (
                parent: forwardCandidate(
                  suffix: 'not-forwarded',
                  isForwarded: false,
                ).parent,
                pending: forwardCandidate(
                  suffix: 'not-forwarded',
                  isForwarded: false,
                ).pending,
                token: forwardToken,
              ),
              'forwarded parent under the external alternative': (
                parent: forwardCandidate(
                  suffix: 'external-shaped',
                  dedupKeyOverride: 'tc350-repo-external-shaped',
                ).parent,
                pending: forwardCandidate(
                  suffix: 'external-shaped',
                  dedupKeyOverride: 'tc350-repo-external-shaped',
                ).pending,
                token: null,
              ),
            };
        for (final entry in refusals.entries) {
          final suffix = entry.value.parent.id.replaceFirst('tc350-repo-', '');
          final candidate = forwardCandidate(
            suffix: suffix,
            dedupKeyOverride: entry.value.parent.dedupKey,
            isForwarded: entry.value.parent.isForwarded,
          );
          final keyName = mediaAttachmentEncryptionKeyStoreName(
            candidate.pending.id,
          );
          final keyBefore = await fixture.secureKeyStore.read(keyName);
          final refused = await stageFresh(
            candidate,
            authorizedForwardDedupKey: entry.value.token,
          );
          expect(refused.outcome.name, 'refused', reason: entry.key);
          expect(refused.hasDurableAuthority, isFalse, reason: entry.key);
          expect(
            await fixture.messageRepo.getMessage(candidate.parent.id),
            isNull,
            reason: entry.key,
          );
          expect(
            await fixture.repo.getAttachmentById(candidate.pending.id),
            isNull,
            reason: entry.key,
          );
          expect(
            await fixture.repo.loadDirectMediaBlobCustodyForMessage(
              candidate.parent.id,
            ),
            isEmpty,
            reason: entry.key,
          );
          expect(
            await fixture.secureKeyStore.read(keyName),
            keyBefore,
            reason: entry.key,
          );
        }

        // The exact external alternative remains publishable.
        final external = forwardCandidate(
          suffix: 'external-canonical',
          dedupKeyOverride: 'tc350-repo-external-canonical',
          isForwarded: false,
        );
        expect(
          (await stageFresh(
            external,
            authorizedForwardDedupKey: null,
          )).outcome.name,
          'applied',
        );
      },
    );

    test(
      'TC-347-02c concurrent preparers adopt one artifact generation',
      () async {
        final documents = await Directory.systemTemp.createTemp(
          'tc347-concurrent-generation-',
        );
        addTearDown(() => documents.delete(recursive: true));
        const messageId = 'tc347-concurrent-parent';
        const attachmentId = 'tc347-concurrent-attachment';
        const identityPeerId = 'tc347-concurrent-identity';
        const createdAt = '2026-08-08T09:00:00.000Z';
        final intent = computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: const <String>[attachmentId],
        );
        final parent = ConversationMessage(
          id: messageId,
          contactPeerId: 'tc347-concurrent-recipient',
          senderPeerId: 'tc347-local',
          text: 'one generation',
          timestamp: createdAt,
          status: 'sending',
          isIncoming: false,
          createdAt: createdAt,
          directMediaCustodyIntentId: intent,
        );
        const pending = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 23,
          mediaType: 'image',
          localPath:
              'pending_uploads/tc347-concurrent-parent/tc347-concurrent-attachment.jpg',
          downloadStatus: 'upload_pending',
          createdAt: createdAt,
          ownerLane: MediaOwnerLane.direct,
        );
        await fixture.messageRepo.saveMessage(parent);
        await fixture.repo.saveAttachment(
          pending,
          owner: MediaOwnerLane.direct,
        );
        final store = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => documents,
        );

        Future<
          ({
            DirectMediaBlobArtifact artifact,
            MediaAttachment prepared,
            DirectMediaBlobCustodyRow custody,
            String key,
          })
        >
        candidate(String suffix, List<int> bytes) async {
          final source = File('${documents.path}/candidate-$suffix.enc');
          await source.writeAsBytes(bytes, flush: true);
          final hash = sha256.convert(bytes).toString();
          final artifact = await store.persistCandidate(
            identityPeerId: identityPeerId,
            attachmentId: attachmentId,
            encryptedSourcePath: source.path,
            expectedContentHash: hash,
          );
          final key = 'tc347-key-$suffix';
          return (
            artifact: artifact,
            prepared: pending.copyWith(
              contentHash: hash,
              encryptionKeyBase64: key,
              encryptionNonce: 'tc347-nonce-$suffix',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            custody: DirectMediaBlobCustodyRow(
              attachmentId: attachmentId,
              messageId: messageId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: parent.contactPeerId,
              ciphertextRelativePath: artifact.relativePath,
              contentHash: hash,
              ciphertextSize: bytes.length,
              expiresAtMs: null,
              custodyRelayPeerId: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
            key: key,
          );
        }

        final first = await candidate('first', const <int>[1, 2, 3, 4]);
        final second = await candidate('second', const <int>[4, 3, 2, 1]);
        final custodyRepository =
            fixture.repo as DirectMediaBlobCustodyRepository;
        final results = await Future.wait([
          custodyRepository.stageOutgoingDirectMediaBlobGeneration(
            expectedParent: parent,
            expectedAttachments: const <MediaAttachment>[pending],
            preparedAttachments: <MediaAttachment>[first.prepared],
            custodyRows: <DirectMediaBlobCustodyRow>[first.custody],
          ),
          custodyRepository.stageOutgoingDirectMediaBlobGeneration(
            expectedParent: parent,
            expectedAttachments: const <MediaAttachment>[pending],
            preparedAttachments: <MediaAttachment>[second.prepared],
            custodyRows: <DirectMediaBlobCustodyRow>[second.custody],
          ),
        ]);

        expect(results.map((result) => result.outcome.name).toSet(), {
          'applied',
          'idempotent',
        });
        final winnerIndex = results.indexWhere(
          (result) => result.outcome.name == 'applied',
        );
        final winner = winnerIndex == 0 ? first : second;
        final loser = winnerIndex == 0 ? second : first;
        for (final result in results) {
          expect(result.attachments, hasLength(1));
          expect(
            result.attachments.single.contentHash,
            winner.artifact.contentHash,
          );
          expect(result.custodyRows, hasLength(1));
          expect(
            result.custodyRows.single.ciphertextRelativePath,
            winner.artifact.relativePath,
          );
        }
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          winner.key,
          reason: 'the idempotent loser must restore the winning stable key',
        );
        expect(
          fixture.secureKeyStore.writtenKeys,
          <String>[mediaAttachmentEncryptionKeyStoreName(attachmentId)],
          reason:
              'DB winner preflight must adopt before the losing candidate can '
              'write the stable key slot',
        );
        expect(
          await fixture.db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: const <Object?>[messageId],
          ),
          hasLength(1),
        );

        final cleanup = await custodyRepository
            .runDirectMediaBlobCustodyLifecycle(() async {
              final rows = await custodyRepository
                  .loadDirectMediaBlobCustodyForMessage(messageId);
              return store.cleanupUnreferencedArtifacts(
                identityPeerId: identityPeerId,
                referencedRelativePaths: rows
                    .map((row) => row.ciphertextRelativePath!)
                    .toSet(),
              );
            });
        expect(cleanup.deleted, 1);
        expect(cleanup.retained, 1);
        expect(File(winner.artifact.absolutePath).existsSync(), isTrue);
        expect(File(loser.artifact.absolutePath).existsSync(), isFalse);
      },
    );

    test(
      'TC-347-02f post-commit hydration error retains referenced generation',
      () async {
        await fixture.dispose();
        final secureStore = _FailingSnapshotSecureKeyStore();
        fixture = await MediaRepositoryRealDbFixture.create(
          secureKeyStore: secureStore,
        );
        final documents = await Directory.systemTemp.createTemp(
          'tc347-post-commit-retain-',
        );
        addTearDown(() => documents.delete(recursive: true));
        const identityPeerId = 'tc347-post-commit-identity';
        const messageId = 'tc347-post-commit-message';
        const attachmentId = 'tc347-post-commit-attachment';
        const createdAt = '2026-08-08T09:05:00.000Z';
        final now = DateTime.utc(2026, 8, 8, 9, 5);
        final parent = ConversationMessage(
          id: messageId,
          contactPeerId: 'tc347-post-commit-recipient',
          senderPeerId: identityPeerId,
          text: 'retain committed candidate',
          timestamp: createdAt,
          status: 'sending',
          isIncoming: false,
          createdAt: createdAt,
          directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: const <String>[attachmentId],
          ),
        );
        const pending = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 4,
          mediaType: 'image',
          localPath:
              'pending_uploads/tc347-post-commit-message/tc347-post-commit-attachment.jpg',
          downloadStatus: 'upload_pending',
          createdAt: createdAt,
          ownerLane: MediaOwnerLane.direct,
        );
        await fixture.messageRepo.saveMessage(parent);
        await fixture.repo.saveAttachment(
          pending,
          owner: MediaOwnerLane.direct,
        );
        final encryptedTemp = File('${documents.path}/post-commit.enc');
        const ciphertext = <int>[7, 4, 7, 2, 9, 1];
        await encryptedTemp.writeAsBytes(ciphertext, flush: true);
        final contentHash = sha256.convert(ciphertext).toString();
        final store = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => documents,
        );
        final custodyRepository =
            fixture.repo as DirectMediaBlobCustodyRepository;
        var strictUploadCalls = 0;
        final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: custodyRepository,
          artifactStore: store,
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                strictUploadCalls++;
                return const <String, dynamic>{};
              },
          clock: () => now,
        );

        secureStore.failRead = true;
        final first = await coordinator.prepareAndUploadFresh(
          bridge: RecordingFakeBridge(),
          identityPeerId: identityPeerId,
          recipientPeerId: parent.contactPeerId,
          expectedParent: parent,
          sources: <PreparedDirectMediaBlobSource>[
            PreparedDirectMediaBlobSource(
              attachment: pending,
              plaintextPath: '${documents.path}/unused.jpg',
              preparedArtifact: EncryptedMediaArtifact(
                encryptedPath: encryptedTemp.path,
                keyBase64: 'tc347-post-commit-key',
                nonce: 'tc347-post-commit-nonce',
                scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                contentHash: contentHash,
                plaintextSize: pending.size,
              ),
            ),
          ],
        );
        expect(first.state, PreparedDirectMediaBlobUploadState.refused);
        expect(strictUploadCalls, 0);

        secureStore.failRead = false;
        final rows = await custodyRepository
            .loadDirectMediaBlobCustodyForMessage(messageId);
        expect(rows, hasLength(1));
        expect(rows.single.state, DirectMediaBlobCustodyState.outgoingPrepared);
        final retained = await store.verifyOwnedArtifact(
          identityPeerId: identityPeerId,
          relativePath: rows.single.ciphertextRelativePath!,
          expectedContentHash: rows.single.contentHash,
          expectedCiphertextSize: rows.single.ciphertextSize,
        );
        expect(retained, isNotNull);
        expect(await encryptedTemp.exists(), isFalse);

        final persistedAttachments = await fixture.repo
            .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.direct);
        expect(persistedAttachments, hasLength(1));
        final recovered =
            await PreparedDirectMediaBlobCustodyCoordinator(
              repository: custodyRepository,
              artifactStore: store,
              strictUpload:
                  ({
                    required bridge,
                    required attachmentId,
                    required recipientPeerId,
                    required ciphertextPath,
                    required contentHash,
                    required ciphertextSize,
                  }) async {
                    strictUploadCalls++;
                    return <String, dynamic>{
                      'ok': true,
                      'id': attachmentId,
                      'storeStatus': 'stored',
                      'custodyKind': kDirectMediaBlobCustodyKind,
                      'custodyContract': kDirectMediaBlobCustodyContract,
                      'contentHash': contentHash,
                      'size': ciphertextSize,
                      'mime': kDirectMediaBlobTransportMime,
                      'expiresAtMs': now
                          .add(const Duration(hours: 1))
                          .millisecondsSinceEpoch,
                      'custodyRelayPeerId': 'tc347-post-commit-relay',
                    };
                  },
              clock: () => now,
            ).reopenAndUpload(
              bridge: RecordingFakeBridge(),
              identityPeerId: identityPeerId,
              recipientPeerId: parent.contactPeerId,
              expectedParent: parent,
              expectedAttachments: persistedAttachments,
            );
        expect(recovered.state, PreparedDirectMediaBlobUploadState.complete);
        expect(strictUploadCalls, 1);
      },
    );

    test('TC-347-02d active blob generation rejects generic crypto mutation', () async {
      const messageId = 'tc347-generic-mutation-parent';
      const attachmentId = 'tc347-generic-mutation-attachment';
      const createdAt = '2026-08-08T09:10:00.000Z';
      final parent = ConversationMessage(
        id: messageId,
        contactPeerId: 'tc347-generic-recipient',
        senderPeerId: 'tc347-local',
        text: 'immutable generation',
        timestamp: createdAt,
        status: 'sending',
        isIncoming: false,
        createdAt: createdAt,
        directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: const <String>[attachmentId],
        ),
      );
      const pending = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 29,
        mediaType: 'image',
        localPath:
            'pending_uploads/tc347-generic-mutation-parent/tc347-generic-mutation-attachment.jpg',
        downloadStatus: 'upload_pending',
        createdAt: createdAt,
        ownerLane: MediaOwnerLane.direct,
      );
      const winnerHash =
          'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      const winnerKey = 'tc347-generic-winner-key';
      final winnerAttachment = pending.copyWith(
        contentHash: winnerHash,
        encryptionKeyBase64: winnerKey,
        encryptionNonce: 'tc347-generic-winner-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      final winnerCustody = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: DirectMediaBlobCustodyDirection.outgoing,
        state: DirectMediaBlobCustodyState.outgoingPrepared,
        inboxCustodyIncarnationId: null,
        recipientPeerId: parent.contactPeerId,
        ciphertextRelativePath:
            'direct_media_blob_custody_v1/${'e' * 64}/winner.blob',
        contentHash: winnerHash,
        ciphertextSize: 47,
        expiresAtMs: null,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      await fixture.messageRepo.saveMessage(parent);
      await fixture.repo.saveAttachment(pending, owner: MediaOwnerLane.direct);
      final custodyRepository =
          fixture.repo as DirectMediaBlobCustodyRepository;
      expect(
        (await custodyRepository.stageOutgoingDirectMediaBlobGeneration(
          expectedParent: parent,
          expectedAttachments: const <MediaAttachment>[pending],
          preparedAttachments: <MediaAttachment>[winnerAttachment],
          custodyRows: <DirectMediaBlobCustodyRow>[winnerCustody],
        )).outcome.name,
        'applied',
      );
      final exactWinnerRow = Map<String, Object?>.from(
        (await rawRow(attachmentId))!,
      );
      final secureWritesAfterWinner = fixture.secureKeyStore.writtenKeys.length;

      await fixture.repo.saveAttachment(
        winnerAttachment.copyWith(
          downloadStatus: 'done',
          localPath: 'media/tc347-generic-recipient/$attachmentId.jpg',
          contentHash:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          encryptionKeyBase64: 'tc347-attacker-key',
          encryptionNonce: 'tc347-attacker-nonce',
        ),
        owner: MediaOwnerLane.direct,
      );

      expect(
        await rawRow(attachmentId),
        exactWinnerRow,
        reason:
            'an active v111 generation owns hash, key, nonce, and pending path',
      );
      expect(
        fixture.secureKeyStore.writtenKeys.length,
        secureWritesAfterWinner,
        reason: 'generic rejection must happen before secure-key mutation',
      );
      expect(
        await fixture.secureKeyStore.read(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        winnerKey,
      );
      final custodyAfter = await custodyRepository
          .loadOutgoingDirectMediaBlobCustodyForTarget(
            attachmentId: attachmentId,
            recipientPeerId: parent.contactPeerId,
          );
      expect(
        custodyAfter!.exactDatabaseProjectionMatches(winnerCustody),
        isTrue,
      );

      // The arbitration is scoped to active v111 authority. A historical
      // ordinary retry with no blob row keeps its established generic
      // upload_pending -> done completion behavior.
      const legacyMessageId = 'tc347-generic-legacy-parent';
      const legacyAttachmentId = 'tc347-generic-legacy-attachment';
      final legacyParent = ConversationMessage(
        id: legacyMessageId,
        contactPeerId: 'tc347-generic-legacy-recipient',
        senderPeerId: 'tc347-local',
        text: 'legacy retry',
        timestamp: createdAt,
        status: 'sending',
        isIncoming: false,
        createdAt: createdAt,
      );
      const legacyPending = MediaAttachment(
        id: legacyAttachmentId,
        messageId: legacyMessageId,
        mime: 'image/jpeg',
        size: 31,
        mediaType: 'image',
        localPath:
            'pending_uploads/tc347-generic-legacy-parent/tc347-generic-legacy-attachment.jpg',
        downloadStatus: 'upload_pending',
        createdAt: createdAt,
        ownerLane: MediaOwnerLane.direct,
      );
      await fixture.messageRepo.saveMessage(legacyParent);
      await fixture.repo.saveAttachment(
        legacyPending,
        owner: MediaOwnerLane.direct,
      );
      await fixture.repo.saveAttachment(
        legacyPending.copyWith(
          downloadStatus: 'done',
          localPath:
              'media/tc347-generic-legacy-recipient/$legacyAttachmentId.jpg',
          contentHash: 'a' * 64,
          encryptionKeyBase64: 'tc347-generic-legacy-key',
          encryptionNonce: 'tc347-generic-legacy-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ),
        owner: MediaOwnerLane.direct,
      );
      final legacyCompleted = await rawRow(legacyAttachmentId);
      expect(legacyCompleted!['download_status'], 'done');
      expect(legacyCompleted['content_hash'], 'a' * 64);
      expect(
        await fixture.secureKeyStore.read(
          mediaAttachmentEncryptionKeyStoreName(legacyAttachmentId),
        ),
        'tc347-generic-legacy-key',
      );
    });

    test(
      'TC-347-06 incoming strict parent attachments and custody commit atomically',
      () async {
        const messageId = 'tc347-incoming-atomic';
        const contactPeerId = 'tc347-sender';
        const createdAt = '2026-08-08T10:00:00.000Z';
        const expiresAtMs = 1_900_000_000_000;
        final message = ConversationMessage(
          id: messageId,
          contactPeerId: contactPeerId,
          senderPeerId: contactPeerId,
          text: 'strict incoming media',
          timestamp: createdAt,
          status: 'delivered',
          isIncoming: true,
          createdAt: createdAt,
        );

        MediaAttachment attachment(String id, String hash, int cipherSize) {
          return MediaAttachment(
            id: id,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 17,
            mediaType: 'image',
            downloadStatus: 'pending',
            createdAt: createdAt,
            contentHash: hash,
            encryptionKeyBase64: 'raw-key-$id',
            encryptionNonce: 'nonce-$id',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            blobCustody: DirectMediaBlobCustodyCommitment(
              contentHash: hash,
              ciphertextSize: cipherSize,
              expiresAtMs: expiresAtMs,
            ),
            ownerLane: MediaOwnerLane.direct,
          );
        }

        DirectMediaBlobCustodyRow custody(
          MediaAttachment attachment,
          int cipherSize,
        ) {
          return DirectMediaBlobCustodyRow(
            attachmentId: attachment.id,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.incoming,
            state: DirectMediaBlobCustodyState.incomingCommitted,
            inboxCustodyIncarnationId: null,
            recipientPeerId: null,
            ciphertextRelativePath: null,
            contentHash: attachment.contentHash!,
            ciphertextSize: cipherSize,
            expiresAtMs: expiresAtMs,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: createdAt,
            updatedAt: createdAt,
          );
        }

        final first = attachment('tc347-incoming-a', 'a' * 64, 31);
        final second = attachment('tc347-incoming-b', 'b' * 64, 37);
        final rows = <DirectMediaBlobCustodyRow>[
          custody(first, 31),
          custody(second, 37),
        ];
        final incoming =
            fixture.repo as IncomingDirectMediaBlobCustodyRepository;

        final staged = await incoming.stageIncomingDirectMediaBlobCustody(
          message: message,
          attachments: <MediaAttachment>[first, second],
          custodyRows: rows,
        );
        expect(staged.outcome.name, 'applied');
        expect(staged.attachments.map((value) => value.id).toSet(), {
          first.id,
          second.id,
        });
        expect(
          await fixture.db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[messageId],
          ),
          hasLength(1),
        );
        expect(
          await fixture.db.query(
            'media_attachments',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          hasLength(2),
        );
        expect(
          await fixture.db.query(
            'direct_media_blob_custody',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          hasLength(2),
        );

        final replay = await incoming.stageIncomingDirectMediaBlobCustody(
          message: message,
          attachments: <MediaAttachment>[first, second],
          custodyRows: rows,
        );
        expect(replay.outcome.name, 'idempotent');

        final crossed = first.copyWith(
          blobCustody: const DirectMediaBlobCustodyCommitment(
            contentHash:
                'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
            ciphertextSize: 31,
            expiresAtMs: expiresAtMs,
          ),
        );
        final refused = await incoming.stageIncomingDirectMediaBlobCustody(
          message: message,
          attachments: <MediaAttachment>[crossed, second],
          custodyRows: rows,
        );
        expect(refused.outcome.name, 'refused');
        expect(
          await fixture.db.query(
            'media_attachments',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          hasLength(2),
          reason: 'a crossed replay must neither patch nor prefix-stage rows',
        );
      },
    );

    test(
      'TC-347-06c incoming ACK obligation survives restart and parent deletion',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'tc347-incoming-ack-restart-',
        );
        addTearDown(() => temp.delete(recursive: true));
        var restarted = await MediaRepositoryRealDbFixture.create(
          databasePath: '${temp.path}/identity.db',
        );
        try {
          const messageId = 'tc347-incoming-restart';
          const attachmentId = 'tc347-incoming-restart-blob';
          const contactPeerId = 'tc347-restart-sender';
          const hash =
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
          const createdAt = '2026-08-08T10:10:00.000Z';
          const expiresAtMs = 1_900_000_100_000;
          const commitment = DirectMediaBlobCustodyCommitment(
            contentHash: hash,
            ciphertextSize: 41,
            expiresAtMs: expiresAtMs,
          );
          const attachment = MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 19,
            mediaType: 'image',
            downloadStatus: 'pending',
            createdAt: createdAt,
            contentHash: hash,
            encryptionKeyBase64: 'tc347-restart-key',
            encryptionNonce: 'tc347-restart-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            blobCustody: commitment,
            ownerLane: MediaOwnerLane.direct,
          );
          final message = ConversationMessage(
            id: messageId,
            contactPeerId: contactPeerId,
            senderPeerId: contactPeerId,
            text: '',
            timestamp: createdAt,
            status: 'delivered',
            isIncoming: true,
            createdAt: createdAt,
          );
          final committed = DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.incoming,
            state: DirectMediaBlobCustodyState.incomingCommitted,
            inboxCustodyIncarnationId: null,
            recipientPeerId: null,
            ciphertextRelativePath: null,
            contentHash: hash,
            ciphertextSize: 41,
            expiresAtMs: expiresAtMs,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: createdAt,
            updatedAt: createdAt,
          );
          final incoming =
              restarted.repo as IncomingDirectMediaBlobCustodyRepository;
          expect(
            (await incoming.stageIncomingDirectMediaBlobCustody(
              message: message,
              attachments: const <MediaAttachment>[attachment],
              custodyRows: <DirectMediaBlobCustodyRow>[committed],
            )).outcome.name,
            'applied',
          );
          expect(
            await incoming.commitIncomingDirectMediaBlobLocalPath(
              expectedAttachment: attachment,
              expectedCustody: committed,
              localPath: 'media/$contactPeerId/$attachmentId.jpg',
              sourceRelayPeerId: 'relay-source-exact',
              updatedAt: '2026-08-08T10:10:01.000Z',
              nowMs: 1_800_000_000_000,
            ),
            isTrue,
          );
          final pendingBeforeDelete =
              await (restarted.repo as DirectMediaBlobCustodyRepository)
                  .loadIncomingDirectMediaBlobCustodyForAttachment(
                    attachmentId,
                  );
          expect(
            pendingBeforeDelete!.state,
            DirectMediaBlobCustodyState.incomingAckPending,
          );

          await restarted.db.delete(
            'messages',
            where: 'id = ?',
            whereArgs: const <Object?>[messageId],
          );
          restarted = await restarted.reopen();
          final afterRestart =
              await (restarted.repo as DirectMediaBlobCustodyRepository)
                  .loadIncomingDirectMediaBlobCustodyForAttachment(
                    attachmentId,
                  );
          expect(afterRestart, isNotNull);
          expect(
            afterRestart!.state,
            DirectMediaBlobCustodyState.incomingAckPending,
          );
          expect(afterRestart.custodyRelayPeerId, 'relay-source-exact');
          expect(
            await (restarted.repo as IncomingDirectMediaBlobCustodyRepository)
                .deleteIncomingDirectMediaBlobAckIfExact(afterRestart),
            isTrue,
          );
        } finally {
          await restarted.dispose();
        }
      },
    );

    test('TC-362-04b linked loader and drain include outgoing survivors and '
        'cleanup while excluding historical outgoing rows', () async {
      final documents = await Directory.systemTemp.createTemp(
        'tc362-linked-loader-drain-',
      );
      addTearDown(() => documents.delete(recursive: true));
      const identityPeerId = 'tc362-linked-loader-identity';
      const contactPeerId = 'tc362-logical-contact';
      const activeMessageId = 'tc362-linked-active-parent';
      const createdAt = '2026-08-12T09:00:00.000Z';
      final now = DateTime.utc(2026, 8, 12, 9, 5);
      final store = DirectMediaBlobArtifactStore(
        documentsDirectoryProvider: () async => documents,
      );

      Future<DirectMediaBlobArtifact> artifact(
        String attachmentId,
        List<int> bytes,
      ) async {
        final source = File('${documents.path}/$attachmentId.source')
          ..writeAsBytesSync(bytes);
        return store.persistCandidate(
          identityPeerId: identityPeerId,
          attachmentId: attachmentId,
          encryptedSourcePath: source.path,
          expectedContentHash: sha256.convert(bytes).toString(),
        );
      }

      final activeArtifact = await artifact(
        'tc362-linked-active-att',
        const <int>[1, 2, 3, 4],
      );
      final cleanupArtifact = await artifact(
        'tc362-linked-cleanup-att',
        const <int>[5, 6, 7, 8],
      );
      final historicalArtifact = await artifact(
        'tc362-historical-att',
        const <int>[9, 10, 11, 12],
      );

      DirectMediaBlobCustodyRow outgoingRow({
        required String attachmentId,
        required String messageId,
        required DirectMediaBlobCustodyState state,
        required DirectMediaBlobArtifact artifact,
        required bool linked,
      }) => DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: DirectMediaBlobCustodyDirection.outgoing,
        state: state,
        inboxCustodyIncarnationId: null,
        recipientPeerId: linked
            ? 'tc362-linked-recipient-$attachmentId'
            : 'tc362-historical-recipient',
        contactAccountPeerId: linked ? contactPeerId : null,
        recipientMlKemPublicKey: linked ? 'mlkem-$attachmentId' : null,
        ciphertextRelativePath: artifact.relativePath,
        contentHash: artifact.contentHash,
        ciphertextSize: artifact.ciphertextSize,
        expiresAtMs: null,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final linkedActive = outgoingRow(
        attachmentId: 'tc362-linked-active-att',
        messageId: activeMessageId,
        state: DirectMediaBlobCustodyState.outgoingPrepared,
        artifact: activeArtifact,
        linked: true,
      );
      final linkedCleanup = outgoingRow(
        attachmentId: 'tc362-linked-cleanup-att',
        messageId: 'tc362-linked-cleanup-parent',
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        artifact: cleanupArtifact,
        linked: true,
      );
      final historical = outgoingRow(
        attachmentId: 'tc362-historical-att',
        messageId: 'tc362-historical-parent',
        state: DirectMediaBlobCustodyState.outgoingPrepared,
        artifact: historicalArtifact,
        linked: false,
      );
      final incoming = DirectMediaBlobCustodyRow(
        attachmentId: 'tc362-linked-local-incoming-att',
        messageId: 'tc362-linked-local-incoming-parent',
        direction: DirectMediaBlobCustodyDirection.incoming,
        state: DirectMediaBlobCustodyState.incomingCommitted,
        inboxCustodyIncarnationId: null,
        recipientPeerId: null,
        ciphertextRelativePath: null,
        contentHash: 'd' * 64,
        ciphertextSize: 99,
        expiresAtMs: now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      for (final row in <DirectMediaBlobCustodyRow>[
        linkedActive,
        linkedCleanup,
        historical,
        incoming,
      ]) {
        await fixture.db.insert(kDirectMediaBlobCustodyTable, row.toMap());
      }
      await fixture.messageRepo.saveMessage(
        const ConversationMessage(
          id: activeMessageId,
          contactPeerId: contactPeerId,
          senderPeerId: identityPeerId,
          text: '',
          timestamp: createdAt,
          status: 'failed',
          isIncoming: false,
          createdAt: createdAt,
        ),
      );

      final linkedRepository =
          fixture.repo as LinkedDirectMediaBlobCustodyDrainRepository;
      expect(
        linkedRepository.supportsLinkedDirectMediaBlobCustodyDrain,
        isTrue,
      );
      final scoped = await linkedRepository
          .loadLinkedDirectMediaBlobCustodyByStates(
            DirectMediaBlobCustodyState.values.toSet(),
          );
      expect(
        scoped.map((row) => row.attachmentId).toSet(),
        <String>{
          linkedActive.attachmentId,
          linkedCleanup.attachmentId,
          incoming.attachmentId,
        },
        reason:
            'incoming rows are device-local, while only marker-bearing '
            'outgoing rows belong to the linked runtime',
      );

      final outgoingRetries = <String>[];
      final incomingRetries = <String>[];
      final bridge = RecordingFakeBridge();
      final drain = DirectMediaBlobCustodyDrain(
        repository: fixture.repo,
        incomingRepository:
            fixture.repo as IncomingDirectMediaBlobCustodyRepository,
        artifactStore: store,
        identityPeerId: () async => identityPeerId,
        strictDownloadAckOwner: StrictDirectMediaBlobDownloadAckOwner(
          bridge: bridge,
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: MediaFileManager(),
        ),
        retryOutgoingLinkedMessage: (messageId) async {
          outgoingRetries.add(messageId);
          return true;
        },
        retryIncomingDownload: (row) async {
          incomingRetries.add(row.attachmentId);
          return true;
        },
        countOtherArtifactReferences:
            ({
              required ciphertextRelativePath,
              required contentHash,
              required ciphertextSize,
              required excluding,
            }) => dbCountOtherDirectMediaBlobCustodyRowsReferencingArtifact(
              fixture.db,
              ciphertextRelativePath: ciphertextRelativePath,
              contentHash: contentHash,
              ciphertextSize: ciphertextSize,
              excluding: excluding,
            ),
        now: () => now,
      );

      final result = await drain.runNetworkBoundedLinked();

      expect(result.failed, 0);
      expect(result.completed, 3);
      expect(outgoingRetries, const <String>[activeMessageId]);
      expect(incomingRetries, <String>[incoming.attachmentId]);
      expect(File(cleanupArtifact.absolutePath).existsSync(), isFalse);
      expect(
        await (fixture.repo as DirectMediaBlobCustodyRepository)
            .loadDirectMediaBlobCustodyForMessage(linkedCleanup.messageId),
        isEmpty,
      );
      expect(
        await (fixture.repo as DirectMediaBlobCustodyRepository)
            .loadDirectMediaBlobCustodyForMessage(historical.messageId),
        hasLength(1),
        reason: 'the linked drain never owns historical primary rows',
      );
      expect(File(historicalArtifact.absolutePath).existsSync(), isTrue);
    });

    test(
      'TC-347-07 blob custody lifecycle and authority-safe cleanup',
      () async {
        final documents = await Directory.systemTemp.createTemp(
          'tc347-custody-cleanup-',
        );
        addTearDown(() => documents.delete(recursive: true));
        const identityPeerId = 'tc347-cleanup-identity';
        const messageId = 'tc347-cleanup-message';
        final store = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => documents,
        );
        final custodyRepo = fixture.repo as DirectMediaBlobCustodyRepository;
        final candidateReady = Completer<DirectMediaBlobArtifact>();
        final allowRowPublication = Completer<void>();

        Future<DirectMediaBlobArtifact> sourceAndCandidate(
          String name,
          List<int> bytes,
        ) async {
          final source = File('${documents.path}/$name.enc');
          await source.writeAsBytes(bytes, flush: true);
          return store.persistCandidate(
            identityPeerId: identityPeerId,
            attachmentId: name,
            encryptedSourcePath: source.path,
            expectedContentHash: sha256.convert(bytes).toString(),
          );
        }

        DirectMediaBlobCustodyRow outgoingRow({
          required String attachmentId,
          required DirectMediaBlobArtifact artifact,
          required DirectMediaBlobCustodyState state,
        }) {
          return DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: state,
            inboxCustodyIncarnationId: null,
            recipientPeerId: 'tc347-cleanup-recipient',
            ciphertextRelativePath: artifact.relativePath,
            contentHash: artifact.contentHash,
            ciphertextSize: artifact.ciphertextSize,
            expiresAtMs: null,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: '2026-08-08T10:20:00.000Z',
            updatedAt: '2026-08-08T10:20:00.000Z',
          );
        }

        final publication = custodyRepo.runDirectMediaBlobCustodyLifecycle(
          () async {
            final artifact = await sourceAndCandidate(
              'file-before-row',
              const <int>[1, 3, 5, 7],
            );
            candidateReady.complete(artifact);
            await allowRowPublication.future;
            await fixture.db.insert(
              kDirectMediaBlobCustodyTable,
              outgoingRow(
                attachmentId: 'file-before-row',
                artifact: artifact,
                state: DirectMediaBlobCustodyState.outgoingPrepared,
              ).toMap(),
            );
            return artifact;
          },
        );
        final publishedArtifact = await candidateReady.future;
        final concurrentCleanup = custodyRepo
            .runDirectMediaBlobCustodyLifecycle(() async {
              final rows = await custodyRepo.loadDirectMediaBlobCustodyByStates(
                const <DirectMediaBlobCustodyState>{
                  DirectMediaBlobCustodyState.outgoingPrepared,
                },
              );
              return store.cleanupUnreferencedArtifacts(
                identityPeerId: identityPeerId,
                referencedRelativePaths: rows
                    .map((row) => row.ciphertextRelativePath!)
                    .toSet(),
              );
            });
        allowRowPublication.complete();
        await publication;
        final cleanupAfterPublication = await concurrentCleanup;
        expect(cleanupAfterPublication.deleted, 0);
        expect(File(publishedArtifact.absolutePath).existsSync(), isTrue);

        final orphan = await sourceAndCandidate(
          'orphan-after-crash',
          const <int>[2, 4, 6, 8],
        );
        final orphanCleanup = await custodyRepo
            .runDirectMediaBlobCustodyLifecycle(() async {
              final rows = await custodyRepo.loadDirectMediaBlobCustodyByStates(
                const <DirectMediaBlobCustodyState>{
                  DirectMediaBlobCustodyState.outgoingPrepared,
                },
              );
              return store.cleanupUnreferencedArtifacts(
                identityPeerId: identityPeerId,
                referencedRelativePaths: rows
                    .map((row) => row.ciphertextRelativePath!)
                    .toSet(),
              );
            });
        expect(orphanCleanup.deleted, 1);
        expect(File(orphan.absolutePath).existsSync(), isFalse);

        final cleanupArtifact = await sourceAndCandidate(
          'cleanup-pending',
          const <int>[9, 8, 7, 6],
        );
        final cleanupRow = outgoingRow(
          attachmentId: 'cleanup-pending',
          artifact: cleanupArtifact,
          state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        );
        await fixture.db.insert(
          kDirectMediaBlobCustodyTable,
          cleanupRow.toMap(),
        );
        final removed = await custodyRepo.runDirectMediaBlobCustodyLifecycle(
          () async {
            if (!await store.deleteOwnedArtifact(
              identityPeerId: identityPeerId,
              relativePath: cleanupArtifact.relativePath,
            )) {
              return false;
            }
            return custodyRepo.deleteDirectMediaBlobCleanupPendingIfExact(
              cleanupRow,
            );
          },
        );
        expect(removed, isTrue);
        expect(File(cleanupArtifact.absolutePath).existsSync(), isFalse);
        expect(
          await custodyRepo.loadOutgoingDirectMediaBlobCustodyForTarget(
            attachmentId: cleanupRow.attachmentId,
            recipientPeerId: cleanupRow.recipientPeerId!,
          ),
          isNull,
        );
      },
    );

    test(
      'TC-347-07d cancellation and missing parent terminalize complete generation',
      () async {
        final documents = await Directory.systemTemp.createTemp(
          'tc347-terminal-cancel-',
        );
        addTearDown(() => documents.delete(recursive: true));
        const identityPeerId = 'tc347-terminal-identity';
        final store = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => documents,
        );
        final custodyRepository =
            fixture.repo as DirectMediaBlobCustodyRepository;
        final terminalizationRepository =
            fixture.repo as OutgoingDirectMediaBlobTerminalizationRepository;
        final generation = await stageOutgoingBlobGeneration(
          store: store,
          sourceDirectory: documents,
          identityPeerId: identityPeerId,
          messageId: 'tc347-cancel-complete-parent',
          attachmentIds: const <String>[
            'tc347-cancel-complete-a',
            'tc347-cancel-complete-b',
          ],
        );
        final now = DateTime.utc(2026, 8, 8, 11, 30);

        expect(
          await terminalizationRepository
              .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
                expectedRows: <DirectMediaBlobCustodyRow>[
                  generation.rows.first,
                ],
                reason:
                    DirectMediaBlobTerminalizationReason.explicitCancellation,
                nowMs: now.millisecondsSinceEpoch,
              ),
          DirectMediaBlobTerminalizationOutcome.refused,
          reason: 'a strict generation cannot be terminalized as a prefix',
        );
        final forbiddenSingleRowCleanup = generation.rows.first.copyWith(
          state: DirectMediaBlobCustodyState.outgoingCleanupPending,
          updatedAt: now.toIso8601String(),
        );
        expect(
          await custodyRepository.transitionDirectMediaBlobCustodyIfExact(
            expected: generation.rows.first,
            next: forbiddenSingleRowCleanup,
          ),
          isFalse,
          reason: 'the raw public per-row transition has no cleanup authority',
        );
        expect(
          (await custodyRepository.loadDirectMediaBlobCustodyForMessage(
            generation.parent.id,
          )).map((row) => row.state),
          everyElement(DirectMediaBlobCustodyState.outgoingPrepared),
        );

        expect(
          await terminalizationRepository
              .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
                expectedRows: generation.rows,
                reason:
                    DirectMediaBlobTerminalizationReason.explicitCancellation,
                nowMs: now.millisecondsSinceEpoch,
              ),
          DirectMediaBlobTerminalizationOutcome.applied,
        );
        final cleanupRows = await custodyRepository
            .loadDirectMediaBlobCustodyForMessage(generation.parent.id);
        expect(cleanupRows, hasLength(2));
        expect(
          cleanupRows.map((row) => row.state),
          everyElement(DirectMediaBlobCustodyState.outgoingCleanupPending),
        );
        for (final artifact in generation.artifacts) {
          expect(
            File(artifact.absolutePath).existsSync(),
            isTrue,
            reason: 'terminal commit must precede lifecycle unlink',
          );
        }

        var strictUploadCalls = 0;
        final bridge = RecordingFakeBridge();
        final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: custodyRepository,
          artifactStore: store,
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                strictUploadCalls++;
                return const <String, dynamic>{};
              },
          clock: () => now,
        );
        final reopen = await coordinator.reopenAndUpload(
          bridge: bridge,
          identityPeerId: identityPeerId,
          recipientPeerId: generation.parent.contactPeerId,
          expectedParent: generation.parent,
          expectedAttachments: generation.attachments,
        );
        expect(reopen.state, PreparedDirectMediaBlobUploadState.refused);
        expect(strictUploadCalls, 0);

        final drain = DirectMediaBlobCustodyDrain(
          repository: custodyRepository,
          incomingRepository:
              fixture.repo as IncomingDirectMediaBlobCustodyRepository,
          artifactStore: store,
          identityPeerId: () async => identityPeerId,
          strictDownloadAckOwner: StrictDirectMediaBlobDownloadAckOwner(
            bridge: bridge,
            mediaAttachmentRepository: fixture.repo,
            mediaFileManager: MediaFileManager(),
          ),
          now: () => now,
        );
        final cancelledCleanup = await drain.runLocalCleanupBounded();
        expect(cancelledCleanup.failed, 0);
        expect(
          await custodyRepository.loadDirectMediaBlobCustodyForMessage(
            generation.parent.id,
          ),
          isEmpty,
        );
        for (final artifact in generation.artifacts) {
          expect(File(artifact.absolutePath).existsSync(), isFalse);
        }

        // Simulate a crash between an ordinary parent delete and the next
        // lifecycle pass. v111 has no parent FK, so recovery must qualify the
        // complete surviving generation before it can unlink the artifact.
        final missingParentGeneration = await stageOutgoingBlobGeneration(
          store: store,
          sourceDirectory: documents,
          identityPeerId: identityPeerId,
          messageId: 'tc347-missing-parent-recovery',
          attachmentIds: const <String>['tc347-missing-parent-blob'],
        );
        expect(
          await fixture.db.delete(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[missingParentGeneration.parent.id],
          ),
          1,
        );
        expect(
          await custodyRepository.loadDirectMediaBlobCustodyForMessage(
            missingParentGeneration.parent.id,
          ),
          hasLength(1),
        );
        final missingParentCleanup = await drain.runLocalCleanupBounded();
        expect(missingParentCleanup.failed, 0);
        expect(
          await custodyRepository.loadDirectMediaBlobCustodyForMessage(
            missingParentGeneration.parent.id,
          ),
          isEmpty,
        );
        expect(
          File(
            missingParentGeneration.artifacts.single.absolutePath,
          ).existsSync(),
          isFalse,
        );

        // Exact v108 custody is independent authority: explicit local
        // cancellation must not publish cleanup while that binding exists.
        final boundGeneration = await stageOutgoingBlobGeneration(
          store: store,
          sourceDirectory: documents,
          identityPeerId: identityPeerId,
          messageId: 'tc347-bound-parent',
          attachmentIds: const <String>['tc347-bound-blob'],
        );
        const incarnationId = '1234567890abcdef1234567890abcdef';
        final proofExpiry = now.add(const Duration(hours: 1));
        final stored = boundGeneration.rows.single.copyWith(
          state: DirectMediaBlobCustodyState.outgoingStored,
          expiresAtMs: proofExpiry.millisecondsSinceEpoch,
          custodyRelayPeerId: 'tc347-proof-relay',
          updatedAt: now.toIso8601String(),
        );
        expect(
          await custodyRepository.transitionDirectMediaBlobCustodyIfExact(
            expected: boundGeneration.rows.single,
            next: stored,
          ),
          isTrue,
        );
        await fixture.db.insert('direct_inbox_custody_outbox', {
          'recipient_peer_id': boundGeneration.parent.contactPeerId,
          'message_id': boundGeneration.parent.id,
          'incarnation_id': incarnationId,
          'wire_envelope': '{"type":"encrypted","payload":"opaque"}',
          'retry_count': 0,
          'last_attempt_at': null,
          'last_error_code': null,
          'media_blob_manifest_hash': 'a' * 64,
          'media_blob_expires_at_ms': proofExpiry.millisecondsSinceEpoch,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        final bound = stored.copyWith(
          inboxCustodyIncarnationId: incarnationId,
          updatedAt: now.add(const Duration(seconds: 1)).toIso8601String(),
        );
        expect(
          await fixture.db.transaction(
            (txn) => dbTransitionDirectMediaBlobCustodyIfExactWithinTransaction(
              txn,
              expected: stored,
              next: bound,
            ),
          ),
          isTrue,
        );
        expect(
          await terminalizationRepository
              .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
                expectedRows: <DirectMediaBlobCustodyRow>[bound],
                reason:
                    DirectMediaBlobTerminalizationReason.explicitCancellation,
                nowMs: now.millisecondsSinceEpoch,
              ),
          DirectMediaBlobTerminalizationOutcome.blockedByV108,
        );
        expect(
          (await custodyRepository.loadDirectMediaBlobCustodyForMessage(
            boundGeneration.parent.id,
          )).single.state,
          DirectMediaBlobCustodyState.outgoingStored,
        );
        expect(
          File(boundGeneration.artifacts.single.absolutePath).existsSync(),
          isTrue,
        );
      },
    );

    test(
      'TC-347-07e expired unbound proof terminalizes and cannot reopen',
      () async {
        final documents = await Directory.systemTemp.createTemp(
          'tc347-terminal-expiry-',
        );
        addTearDown(() => documents.delete(recursive: true));
        const identityPeerId = 'tc347-expiry-identity';
        final store = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => documents,
        );
        final custodyRepository =
            fixture.repo as DirectMediaBlobCustodyRepository;
        final generation = await stageOutgoingBlobGeneration(
          store: store,
          sourceDirectory: documents,
          identityPeerId: identityPeerId,
          messageId: 'tc347-expiry-parent',
          attachmentIds: const <String>['tc347-expiry-a', 'tc347-expiry-b'],
        );
        var currentNow = DateTime.utc(2026, 8, 8, 12);
        final expiries = <int>[
          currentNow
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
          currentNow.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        ];
        for (var index = 0; index < generation.rows.length; index++) {
          final stored = generation.rows[index].copyWith(
            state: DirectMediaBlobCustodyState.outgoingStored,
            expiresAtMs: expiries[index],
            custodyRelayPeerId: 'tc347-expiry-relay',
            updatedAt: currentNow.toIso8601String(),
          );
          expect(
            await custodyRepository.transitionDirectMediaBlobCustodyIfExact(
              expected: generation.rows[index],
              next: stored,
            ),
            isTrue,
          );
        }

        var strictUploadCalls = 0;
        final bridge = RecordingFakeBridge();
        final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: custodyRepository,
          artifactStore: store,
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                strictUploadCalls++;
                return const <String, dynamic>{};
              },
          clock: () => currentNow,
        );
        expect(
          (await coordinator.reopenAndUpload(
            bridge: bridge,
            identityPeerId: identityPeerId,
            recipientPeerId: generation.parent.contactPeerId,
            expectedParent: generation.parent,
            expectedAttachments: generation.attachments,
          )).state,
          PreparedDirectMediaBlobUploadState.refused,
          reason: 'one expired proof closes the complete generation to reopen',
        );
        expect(strictUploadCalls, 0);

        final drain = DirectMediaBlobCustodyDrain(
          repository: custodyRepository,
          incomingRepository:
              fixture.repo as IncomingDirectMediaBlobCustodyRepository,
          artifactStore: store,
          identityPeerId: () async => identityPeerId,
          strictDownloadAckOwner: StrictDirectMediaBlobDownloadAckOwner(
            bridge: bridge,
            mediaAttachmentRepository: fixture.repo,
            mediaFileManager: MediaFileManager(),
          ),
          now: () => currentNow,
        );
        final partialExpiry = await drain.runLocalCleanupBounded();
        expect(partialExpiry.failed, 0);
        expect(
          await custodyRepository.loadDirectMediaBlobCustodyForMessage(
            generation.parent.id,
          ),
          isEmpty,
          reason:
              'the earliest expired proof terminalizes the complete generation',
        );
        for (final artifact in generation.artifacts) {
          expect(File(artifact.absolutePath).existsSync(), isFalse);
        }

        currentNow = currentNow.add(const Duration(minutes: 2));
        final completeExpiry = await drain.runLocalCleanupBounded();
        expect(completeExpiry.failed, 0);
        expect(
          await custodyRepository.loadDirectMediaBlobCustodyForMessage(
            generation.parent.id,
          ),
          isEmpty,
        );
        for (final artifact in generation.artifacts) {
          expect(File(artifact.absolutePath).existsSync(), isFalse);
        }
        expect(
          (await coordinator.reopenAndUpload(
            bridge: bridge,
            identityPeerId: identityPeerId,
            recipientPeerId: generation.parent.contactPeerId,
            expectedParent: generation.parent,
            expectedAttachments: generation.attachments,
          )).state,
          PreparedDirectMediaBlobUploadState.refused,
        );
        expect(strictUploadCalls, 0);
      },
    );

    test(
      'TC-347-07f lifecycle lease orders reopen terminalization and stored winner adoption',
      () async {
        final documents = await Directory.systemTemp.createTemp(
          'tc347-lifecycle-ordering-',
        );
        addTearDown(() => documents.delete(recursive: true));
        const identityPeerId = 'tc347-ordering-identity';
        final now = DateTime.utc(2026, 8, 8, 13);
        final expiresAtMs = now
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch;
        final store = DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => documents,
        );
        final custodyRepository =
            fixture.repo as DirectMediaBlobCustodyRepository;
        final terminalizationRepository =
            fixture.repo as OutgoingDirectMediaBlobTerminalizationRepository;

        Map<String, dynamic> exactReceipt({
          required String attachmentId,
          required String contentHash,
          required int ciphertextSize,
          required String relayPeerId,
        }) => <String, dynamic>{
          'ok': true,
          'id': attachmentId,
          'storeStatus': 'stored',
          'custodyKind': kDirectMediaBlobCustodyKind,
          'custodyContract': kDirectMediaBlobCustodyContract,
          'contentHash': contentHash,
          'size': ciphertextSize,
          'mime': kDirectMediaBlobTransportMime,
          'expiresAtMs': expiresAtMs,
          'custodyRelayPeerId': relayPeerId,
        };

        // Cancellation owns the lifecycle lease first. Reopen queues behind
        // it, observes cleanup authority, and emits neither LAN nor relay work.
        final cancellationGeneration = await stageOutgoingBlobGeneration(
          store: store,
          sourceDirectory: documents,
          identityPeerId: identityPeerId,
          messageId: 'tc347-order-cancellation-wins',
          attachmentIds: const <String>['tc347-order-cancellation-blob'],
        );
        var cancelledLanCalls = 0;
        var cancelledStrictCalls = 0;
        final cancelledCoordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: custodyRepository,
          artifactStore: store,
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                cancelledStrictCalls++;
                return exactReceipt(
                  attachmentId: attachmentId,
                  contentHash: contentHash,
                  ciphertextSize: ciphertextSize,
                  relayPeerId: 'tc347-cancel-unreachable-relay',
                );
              },
          clock: () => now,
        );
        final cancellationCommitted = Completer<void>();
        final releaseCancellationLease = Completer<void>();
        final cancellationFuture = custodyRepository
            .runDirectMediaBlobCustodyLifecycle(() async {
              final outcome = await terminalizationRepository
                  .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
                    expectedRows: cancellationGeneration.rows,
                    reason: DirectMediaBlobTerminalizationReason
                        .explicitCancellation,
                    nowMs: now.millisecondsSinceEpoch,
                  );
              cancellationCommitted.complete();
              await releaseCancellationLease.future;
              return outcome;
            });
        await cancellationCommitted.future.timeout(const Duration(seconds: 5));
        var cancelledReopenFinished = false;
        final cancelledReopenFuture = cancelledCoordinator
            .reopenAndUpload(
              bridge: RecordingFakeBridge(),
              identityPeerId: identityPeerId,
              recipientPeerId: cancellationGeneration.parent.contactPeerId,
              expectedParent: cancellationGeneration.parent,
              expectedAttachments: cancellationGeneration.attachments,
              onGenerationReady: (_) async {
                cancelledLanCalls++;
              },
            )
            .whenComplete(() => cancelledReopenFinished = true);
        await Future<void>.delayed(Duration.zero);
        final cancellationHeldReopen = !cancelledReopenFinished;
        final cancellationLanCallsWhileHeld = cancelledLanCalls;
        final cancellationStrictCallsWhileHeld = cancelledStrictCalls;
        releaseCancellationLease.complete();
        expect(cancellationHeldReopen, isTrue);
        expect(cancellationLanCallsWhileHeld, 0);
        expect(cancellationStrictCallsWhileHeld, 0);
        expect(
          await cancellationFuture,
          DirectMediaBlobTerminalizationOutcome.applied,
        );
        expect(
          (await cancelledReopenFuture).state,
          PreparedDirectMediaBlobUploadState.refused,
        );
        expect(cancelledLanCalls, 0);
        expect(cancelledStrictCalls, 0);

        // Reopen owns the lease first. Terminalization is queued while the
        // exact strict call is in flight, then applies to its stored winner
        // immediately after the upload owner releases the shared lease.
        final uploadGeneration = await stageOutgoingBlobGeneration(
          store: store,
          sourceDirectory: documents,
          identityPeerId: identityPeerId,
          messageId: 'tc347-order-upload-wins',
          attachmentIds: const <String>['tc347-order-upload-blob'],
        );
        const uploadRelayPeerId = 'tc347-order-upload-relay';
        var uploadLanCalls = 0;
        var uploadStrictCalls = 0;
        final strictUploadEntered = Completer<void>();
        final releaseStrictUpload = Completer<void>();
        final uploadCoordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: custodyRepository,
          artifactStore: store,
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                uploadStrictCalls++;
                strictUploadEntered.complete();
                await releaseStrictUpload.future;
                return exactReceipt(
                  attachmentId: attachmentId,
                  contentHash: contentHash,
                  ciphertextSize: ciphertextSize,
                  relayPeerId: uploadRelayPeerId,
                );
              },
          clock: () => now,
        );
        final uploadFuture = uploadCoordinator.reopenAndUpload(
          bridge: RecordingFakeBridge(),
          identityPeerId: identityPeerId,
          recipientPeerId: uploadGeneration.parent.contactPeerId,
          expectedParent: uploadGeneration.parent,
          expectedAttachments: uploadGeneration.attachments,
          onGenerationReady: (_) async {
            uploadLanCalls++;
          },
        );
        await strictUploadEntered.future.timeout(const Duration(seconds: 5));
        expect(uploadLanCalls, 1);
        expect(uploadStrictCalls, 1);
        final expectedStoredWinner = uploadGeneration.rows.single.copyWith(
          state: DirectMediaBlobCustodyState.outgoingStored,
          expiresAtMs: expiresAtMs,
          custodyRelayPeerId: uploadRelayPeerId,
          updatedAt: now.toIso8601String(),
        );
        var uploadTerminalizationFinished = false;
        final uploadTerminalizationFuture = terminalizationRepository
            .terminalizeOutgoingDirectMediaBlobGenerationIfExact(
              expectedRows: <DirectMediaBlobCustodyRow>[expectedStoredWinner],
              reason: DirectMediaBlobTerminalizationReason.explicitCancellation,
              nowMs: now.millisecondsSinceEpoch,
            )
            .whenComplete(() => uploadTerminalizationFinished = true);
        await Future<void>.delayed(Duration.zero);
        final uploadHeldTerminalization = !uploadTerminalizationFinished;
        final stateWhileUploadHeld =
            (await custodyRepository.loadDirectMediaBlobCustodyForMessage(
              uploadGeneration.parent.id,
            )).single.state;
        releaseStrictUpload.complete();
        expect(uploadHeldTerminalization, isTrue);
        expect(
          stateWhileUploadHeld,
          DirectMediaBlobCustodyState.outgoingPrepared,
        );
        expect(
          (await uploadFuture).state,
          PreparedDirectMediaBlobUploadState.complete,
        );
        expect(
          await uploadTerminalizationFuture,
          DirectMediaBlobTerminalizationOutcome.applied,
        );
        expect(uploadLanCalls, 1);
        expect(uploadStrictCalls, 1);
        expect(
          (await custodyRepository.loadDirectMediaBlobCustodyForMessage(
            uploadGeneration.parent.id,
          )).single.state,
          DirectMediaBlobCustodyState.outgoingCleanupPending,
        );

        // Two fresh owners start concurrently. The first holds the lifecycle
        // lease through strict upload and publishes outgoing_stored. The
        // queued loser stages afterward, idempotently adopts that exact winner,
        // and performs no second strict upload or stable-key overwrite.
        const freshMessageId = 'tc347-order-fresh-stored-winner';
        const freshAttachmentId = 'tc347-order-fresh-stored-blob';
        const freshCreatedAt = '2026-08-08T13:00:00.000Z';
        final freshParent = ConversationMessage(
          id: freshMessageId,
          contactPeerId: 'tc347-order-fresh-recipient',
          senderPeerId: identityPeerId,
          text: 'concurrent stored winner',
          timestamp: freshCreatedAt,
          status: 'sending',
          isIncoming: false,
          createdAt: freshCreatedAt,
          directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
            messageId: freshMessageId,
            attachmentIds: const <String>[freshAttachmentId],
          ),
        );
        const freshPending = MediaAttachment(
          id: freshAttachmentId,
          messageId: freshMessageId,
          mime: 'image/jpeg',
          size: 5,
          mediaType: 'image',
          localPath:
              'pending_uploads/tc347-order-fresh-stored-winner/tc347-order-fresh-stored-blob.jpg',
          downloadStatus: 'upload_pending',
          createdAt: freshCreatedAt,
          ownerLane: MediaOwnerLane.direct,
        );
        await fixture.messageRepo.saveMessage(freshParent);
        await fixture.repo.saveAttachment(
          freshPending,
          owner: MediaOwnerLane.direct,
        );
        final winnerTemp = File('${documents.path}/fresh-winner.enc');
        final loserTemp = File('${documents.path}/fresh-loser.enc');
        const winnerBytes = <int>[1, 2, 3, 4, 5, 6];
        const loserBytes = <int>[6, 5, 4, 3, 2, 1];
        await winnerTemp.writeAsBytes(winnerBytes, flush: true);
        await loserTemp.writeAsBytes(loserBytes, flush: true);
        final winnerHash = sha256.convert(winnerBytes).toString();
        final loserHash = sha256.convert(loserBytes).toString();
        const winnerKey = 'tc347-order-fresh-winner-key';
        final winnerSource = PreparedDirectMediaBlobSource(
          attachment: freshPending,
          plaintextPath: '${documents.path}/unused-winner.jpg',
          preparedArtifact: EncryptedMediaArtifact(
            encryptedPath: winnerTemp.path,
            keyBase64: winnerKey,
            nonce: 'tc347-order-fresh-winner-nonce',
            scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            contentHash: winnerHash,
            plaintextSize: freshPending.size,
          ),
        );
        final loserSource = PreparedDirectMediaBlobSource(
          attachment: freshPending,
          plaintextPath: '${documents.path}/unused-loser.jpg',
          preparedArtifact: EncryptedMediaArtifact(
            encryptedPath: loserTemp.path,
            keyBase64: 'tc347-order-fresh-loser-key',
            nonce: 'tc347-order-fresh-loser-nonce',
            scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            contentHash: loserHash,
            plaintextSize: freshPending.size,
          ),
        );
        var freshStrictCalls = 0;
        final freshStrictEntered = Completer<void>();
        final releaseFreshStrict = Completer<void>();
        Future<Map<String, dynamic>> strictFreshUpload({
          required bridge,
          required String attachmentId,
          required String recipientPeerId,
          required String ciphertextPath,
          required String contentHash,
          required int ciphertextSize,
        }) async {
          freshStrictCalls++;
          if (!freshStrictEntered.isCompleted) freshStrictEntered.complete();
          await releaseFreshStrict.future;
          return exactReceipt(
            attachmentId: attachmentId,
            contentHash: contentHash,
            ciphertextSize: ciphertextSize,
            relayPeerId: 'tc347-order-fresh-relay',
          );
        }

        final winnerCoordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: custodyRepository,
          artifactStore: store,
          strictUpload: strictFreshUpload,
          clock: () => now,
        );
        final loserCoordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: custodyRepository,
          artifactStore: store,
          strictUpload: strictFreshUpload,
          clock: () => now,
        );
        final freshBridge = RecordingFakeBridge();
        final winnerFuture = winnerCoordinator.prepareAndUploadFresh(
          bridge: freshBridge,
          identityPeerId: identityPeerId,
          recipientPeerId: freshParent.contactPeerId,
          expectedParent: freshParent,
          sources: <PreparedDirectMediaBlobSource>[winnerSource],
        );
        await freshStrictEntered.future.timeout(const Duration(seconds: 5));
        final writesAfterWinnerPublication =
            fixture.secureKeyStore.writtenKeys.length;
        var loserFinished = false;
        final loserFuture = loserCoordinator
            .prepareAndUploadFresh(
              bridge: freshBridge,
              identityPeerId: identityPeerId,
              recipientPeerId: freshParent.contactPeerId,
              expectedParent: freshParent,
              sources: <PreparedDirectMediaBlobSource>[loserSource],
            )
            .whenComplete(() => loserFinished = true);
        await Future<void>.delayed(Duration.zero);
        final freshLoserWaited = !loserFinished;
        final callsWhileWinnerHeldLease = freshStrictCalls;
        releaseFreshStrict.complete();
        expect(freshLoserWaited, isTrue);
        expect(callsWhileWinnerHeldLease, 1);
        expect(
          (await winnerFuture).state,
          PreparedDirectMediaBlobUploadState.complete,
        );
        expect(
          (await loserFuture).state,
          PreparedDirectMediaBlobUploadState.complete,
          reason: 'the fresh loser must adopt the complete stored winner',
        );
        expect(freshStrictCalls, 1);
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesAfterWinnerPublication,
          reason: 'stored-winner adoption must precede loser key mutation',
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(freshAttachmentId),
          ),
          winnerKey,
        );
        final storedWinner =
            (await custodyRepository.loadDirectMediaBlobCustodyForMessage(
              freshMessageId,
            )).single;
        expect(storedWinner.state, DirectMediaBlobCustodyState.outgoingStored);
        expect(storedWinner.contentHash, winnerHash);
        expect(storedWinner.contentHash, isNot(loserHash));
        expect(await loserTemp.exists(), isFalse);
      },
    );

    test(
      'ordinary media attempt stages parent and attachments atomically or writes nothing',
      () async {
        ConversationMessage outgoing({
          required String id,
          String text = 'ordinary media',
          String status = 'sending',
          String? wireEnvelope = 'envelope-v1',
          String? editedAt,
          String? transport,
          int? relayExpiresAt,
          String? custodyCheckedAt,
        }) => ConversationMessage(
          id: id,
          contactPeerId: 'peer-ordinary',
          senderPeerId: 'peer-local',
          text: text,
          timestamp: '2026-08-05T10:00:00.000Z',
          status: status,
          isIncoming: false,
          createdAt: '2026-08-05T10:00:00.000Z',
          editedAt: editedAt,
          transport: transport,
          wireEnvelope: wireEnvelope,
          relayExpiresAt: relayExpiresAt,
          custodyCheckedAt: custodyCheckedAt,
        );

        MediaAttachment attemptAttachment({
          required String id,
          required String messageId,
          required String key,
          String mime = 'image/jpeg',
          int size = 101,
        }) => makeAttachment(
          id: id,
          messageId: messageId,
          mime: mime,
          size: size,
          mediaType: mime.startsWith('video/') ? 'video' : 'image',
          downloadStatus: 'upload_pending',
          localPath: 'pending_uploads/$messageId/$id.bin',
          encryptionKeyBase64: key,
          encryptionNonce: 'nonce-$id',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        Future<void> expectFreshPair(String messageId) async {
          final attachment = attemptAttachment(
            id: '$messageId-attachment',
            messageId: messageId,
            key: 'key-$messageId',
          );
          final staged = await fixture.repo
              .stageOutgoingOrdinaryAttemptWithMedia(
                messageMutationRepository:
                    fixture.messageRepo as OutgoingTransportMutationRepository,
                expected: null,
                staged: outgoing(id: messageId),
                attachments: <MediaAttachment>[attachment],
                kind: OutgoingOrdinaryAttemptKind.fresh,
              );
          expect(staged.outcome, OutgoingOrdinaryMutationOutcome.applied);
          expect(staged.message!.id, messageId);
          expect(staged.message!.wireEnvelope, 'envelope-v1');
          expect(staged.message!.media.map((media) => media.id), <String>[
            '$messageId-attachment',
          ]);
          expect(
            await fixture.secureKeyStore.read(
              mediaAttachmentEncryptionKeyStoreName('$messageId-attachment'),
            ),
            'key-$messageId',
          );
        }

        // Generated and explicitly preassigned caller-owned IDs both use the
        // same insert-only fresh authority.
        await expectFreshPair('generated-fresh-parent');
        await expectFreshPair('preassigned-fresh-parent');

        // A legacy zero-byte upload placeholder can exist without its parent
        // after the old split writer crashed. Explicit fresh authority replaces
        // only that non-cryptographic placeholder inside the same transaction.
        const placeholderParentId = 'fresh-placeholder-parent';
        const placeholderId = 'legacy-zero-byte-placeholder';
        await fixture.db.insert(
          'media_attachments',
          makeAttachment(
            id: placeholderId,
            messageId: placeholderParentId,
            size: 0,
            downloadStatus: 'upload_pending',
            localPath: '/tmp/legacy-placeholder.jpg',
          ).copyWith(ownerLane: MediaOwnerLane.direct).toMap(),
        );
        final replacement = attemptAttachment(
          id: 'fresh-placeholder-replacement',
          messageId: placeholderParentId,
          key: 'fresh-placeholder-key',
        );
        final replacedPlaceholder = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: null,
              staged: outgoing(id: placeholderParentId),
              attachments: <MediaAttachment>[replacement],
              kind: OutgoingOrdinaryAttemptKind.fresh,
            );
        expect(
          replacedPlaceholder.outcome,
          OutgoingOrdinaryMutationOutcome.applied,
        );
        expect(await rawRow(placeholderId), isNull);
        expect(
          (await rawRow(replacement.id))?['download_status'],
          'upload_pending',
        );

        // The compatibility exception is deliberately narrow: any durable,
        // hashed, or encrypted extra row is authoritative projection state and
        // cannot be discarded by a fresh attempt.
        final refusedLegacyRows = <({String label, MediaAttachment attachment})>[
          (
            label: 'positive-size',
            attachment: makeAttachment(
              id: 'legacy-positive-size',
              messageId: 'fresh-refused-positive-size',
              size: 1,
              downloadStatus: 'upload_pending',
            ),
          ),
          (
            label: 'hashed',
            attachment:
                makeAttachment(
                  id: 'legacy-hashed',
                  messageId: 'fresh-refused-hashed',
                  size: 0,
                  downloadStatus: 'upload_pending',
                ).copyWith(
                  contentHash:
                      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
                ),
          ),
          (
            label: 'thumbnail-hashed',
            attachment:
                makeAttachment(
                  id: 'legacy-thumbnail-hashed',
                  messageId: 'fresh-refused-thumbnail-hashed',
                  size: 0,
                  downloadStatus: 'upload_pending',
                ).copyWith(
                  thumbnailHash:
                      'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
                ),
          ),
          (
            label: 'encrypted',
            attachment: makeAttachment(
              id: 'legacy-encrypted',
              messageId: 'fresh-refused-encrypted',
              size: 0,
              downloadStatus: 'upload_pending',
              encryptionKeyBase64: 'legacy-encrypted-key',
              encryptionNonce: 'legacy-encrypted-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
          ),
        ];
        for (final fixtureCase in refusedLegacyRows) {
          final stale = fixtureCase.attachment.copyWith(
            ownerLane: MediaOwnerLane.direct,
          );
          await fixture.db.insert('media_attachments', stale.toMap());
          final staleBefore = await rawRow(stale.id);
          final candidate = attemptAttachment(
            id: 'replacement-${fixtureCase.label}',
            messageId: stale.messageId,
            key: 'replacement-key-${fixtureCase.label}',
          );
          final refused = await fixture.repo
              .stageOutgoingOrdinaryAttemptWithMedia(
                messageMutationRepository:
                    fixture.messageRepo as OutgoingTransportMutationRepository,
                expected: null,
                staged: outgoing(id: stale.messageId),
                attachments: <MediaAttachment>[candidate],
                kind: OutgoingOrdinaryAttemptKind.fresh,
              );
          expect(
            refused.outcome,
            OutgoingOrdinaryMutationOutcome.refused,
            reason: fixtureCase.label,
          );
          expect(
            await fixture.messageRepo.getMessage(stale.messageId),
            isNull,
            reason: fixtureCase.label,
          );
          expect(
            await rawRow(stale.id),
            staleBefore,
            reason: fixtureCase.label,
          );
          expect(await rawRow(candidate.id), isNull, reason: fixtureCase.label);
          expect(
            await fixture.secureKeyStore.containsKey(
              mediaAttachmentEncryptionKeyStoreName(candidate.id),
            ),
            false,
            reason: fixtureCase.label,
          );
        }

        const existingId = 'existing-attempt-parent';
        final expectedExisting = outgoing(
          id: existingId,
          status: 'failed',
          wireEnvelope: 'old-envelope',
          transport: 'direct',
          relayExpiresAt: 99,
          custodyCheckedAt: '2026-08-05T10:01:00.000Z',
        );
        await fixture.db.insert('messages', expectedExisting.toMap());
        final existingAttachment = attemptAttachment(
          id: 'existing-attempt-attachment',
          messageId: existingId,
          key: 'existing-attempt-key',
        );
        final stagedExisting = expectedExisting.copyWith(
          status: 'sending',
          transport: null,
          wireEnvelope: 'existing-envelope-v2',
          relayExpiresAt: null,
          custodyCheckedAt: null,
        );
        final existingResult = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: expectedExisting,
              staged: stagedExisting,
              attachments: <MediaAttachment>[existingAttachment],
              kind: OutgoingOrdinaryAttemptKind.existing,
            );
        expect(existingResult.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(existingResult.message!.wireEnvelope, 'existing-envelope-v2');
        expect(existingResult.message!.media.single.id, existingAttachment.id);

        // An uncertain retry may repair a missing secure-store key while the
        // already-committed parent/media projection is idempotent. Successful
        // idempotence authorizes transport and must retain that repaired key.
        final existingKeyName = mediaAttachmentEncryptionKeyStoreName(
          existingAttachment.id,
        );
        await fixture.secureKeyStore.delete(existingKeyName);
        expect(
          await fixture.secureKeyStore.containsKey(existingKeyName),
          false,
        );
        final idempotentExisting = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: expectedExisting,
              staged: stagedExisting,
              attachments: <MediaAttachment>[existingAttachment],
              kind: OutgoingOrdinaryAttemptKind.existing,
            );
        expect(
          idempotentExisting.outcome,
          OutgoingOrdinaryMutationOutcome.idempotent,
        );
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'existing-attempt-key',
        );

        // A crossed uncertain retry has the same stable secure:<id> SQL
        // reference even when it carries different raw key material. The
        // durable envelope still owns the original key; idempotence may
        // authorize that envelope, but must not silently rotate its key.
        final conflictingIdempotent = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: expectedExisting,
              staged: stagedExisting,
              attachments: <MediaAttachment>[
                existingAttachment.copyWith(
                  encryptionKeyBase64: 'crossed-idempotent-key',
                ),
              ],
              kind: OutgoingOrdinaryAttemptKind.existing,
            );
        expect(
          conflictingIdempotent.outcome,
          OutgoingOrdinaryMutationOutcome.idempotent,
        );
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'existing-attempt-key',
        );
        expect(
          conflictingIdempotent.message!.media.single.encryptionKeyBase64,
          'existing-attempt-key',
        );

        // Legacy placeholder replacement belongs only to explicit fresh
        // authority. An existing retry must not turn an otherwise-idempotent
        // parent into an applied cleanup that could retain a crossed raw key.
        const existingRetryPlaceholderId = 'existing-retry-legacy-placeholder';
        await fixture.db.insert(
          'media_attachments',
          makeAttachment(
            id: existingRetryPlaceholderId,
            messageId: existingId,
            size: 0,
            downloadStatus: 'upload_pending',
          ).copyWith(ownerLane: MediaOwnerLane.direct).toMap(),
        );
        final refusedPlaceholderCleanup = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: expectedExisting,
              staged: stagedExisting,
              attachments: <MediaAttachment>[
                existingAttachment.copyWith(
                  encryptionKeyBase64: 'crossed-placeholder-key',
                ),
              ],
              kind: OutgoingOrdinaryAttemptKind.existing,
            );
        expect(
          refusedPlaceholderCleanup.outcome,
          OutgoingOrdinaryMutationOutcome.refused,
        );
        expect(await rawRow(existingRetryPlaceholderId), isNotNull);
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'existing-attempt-key',
        );
        expect(
          await fixture.db.delete(
            'media_attachments',
            where: 'id = ?',
            whereArgs: <Object?>[existingRetryPlaceholderId],
          ),
          1,
        );

        // A caller that still owns the exact failed predecessor may stage a
        // genuinely new envelope/key pair. Only the idempotent case restores
        // a conflict; an applied CAS retains the replacement key.
        expect(
          await fixture.db.update(
            'messages',
            <String, Object?>{'status': 'failed'},
            where: 'id = ?',
            whereArgs: <Object?>[existingId],
          ),
          1,
        );
        final rotationExpected = stagedExisting.copyWith(status: 'failed');
        final rotatedStage = rotationExpected.copyWith(
          status: 'sending',
          wireEnvelope: 'existing-envelope-v3',
        );
        final appliedRotation = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: rotationExpected,
              staged: rotatedStage,
              attachments: <MediaAttachment>[
                existingAttachment.copyWith(
                  encryptionKeyBase64: 'existing-attempt-key-v3',
                ),
              ],
              kind: OutgoingOrdinaryAttemptKind.existing,
            );
        expect(
          appliedRotation.outcome,
          OutgoingOrdinaryMutationOutcome.applied,
        );
        expect(appliedRotation.message!.wireEnvelope, 'existing-envelope-v3');
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'existing-attempt-key-v3',
        );

        const editId = 'edit-attempt-parent';
        final expectedEdit = outgoing(
          id: editId,
          text: 'before edit',
          status: 'delivered',
          wireEnvelope: null,
          transport: 'direct',
        );
        await fixture.db.insert('messages', expectedEdit.toMap());
        final edited = expectedEdit.copyWith(
          text: 'after edit',
          status: 'sending',
          editedAt: '2026-08-05T10:02:00.000Z',
          transport: null,
          wireEnvelope: 'edit-envelope',
        );
        final editAttachment = attemptAttachment(
          id: 'edit-attempt-attachment',
          messageId: editId,
          key: 'edit-attempt-key',
        );
        final editResult = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: expectedEdit,
              staged: edited,
              attachments: <MediaAttachment>[editAttachment],
              kind: OutgoingOrdinaryAttemptKind.edit,
            );
        expect(editResult.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(editResult.message!.text, 'after edit');
        expect(editResult.message!.editedAt, edited.editedAt);
        expect(editResult.message!.media.single.id, editAttachment.id);

        // A crossed attempt may prepare a different key, but the stale parent
        // snapshot cannot commit envelope B or projection B, and compensation
        // restores the key paired with attempt A.
        const crossedId = 'crossed-attempt-parent';
        final crossedExpected = outgoing(
          id: crossedId,
          status: 'failed',
          wireEnvelope: 'crossed-old-envelope',
        );
        await fixture.db.insert('messages', crossedExpected.toMap());
        final attachmentA = attemptAttachment(
          id: 'crossed-attempt-attachment',
          messageId: crossedId,
          key: 'crossed-key-a',
          mime: 'image/jpeg',
          size: 201,
        );
        final attachmentB = attemptAttachment(
          id: attachmentA.id,
          messageId: crossedId,
          key: 'crossed-key-b',
          mime: 'video/mp4',
          size: 202,
        );
        final attemptA = crossedExpected.copyWith(
          status: 'sending',
          wireEnvelope: 'crossed-envelope-a',
        );
        final attemptB = crossedExpected.copyWith(
          status: 'sending',
          wireEnvelope: 'crossed-envelope-b',
        );
        expect(
          (await fixture.repo.stageOutgoingOrdinaryAttemptWithMedia(
            messageMutationRepository:
                fixture.messageRepo as OutgoingTransportMutationRepository,
            expected: crossedExpected,
            staged: attemptA,
            attachments: <MediaAttachment>[attachmentA],
            kind: OutgoingOrdinaryAttemptKind.existing,
          )).outcome,
          OutgoingOrdinaryMutationOutcome.applied,
        );
        expect(
          (await fixture.repo.stageOutgoingOrdinaryAttemptWithMedia(
            messageMutationRepository:
                fixture.messageRepo as OutgoingTransportMutationRepository,
            expected: crossedExpected,
            staged: attemptB,
            attachments: <MediaAttachment>[attachmentB],
            kind: OutgoingOrdinaryAttemptKind.existing,
          )).outcome,
          OutgoingOrdinaryMutationOutcome.preserved,
        );
        final crossedParent = await fixture.messageRepo.getMessage(crossedId);
        final crossedMedia = await fixture.repo.getAttachmentsForMessage(
          crossedId,
          owner: MediaOwnerLane.direct,
        );
        expect(crossedParent!.wireEnvelope, 'crossed-envelope-a');
        expect(crossedMedia.single.mime, 'image/jpeg');
        expect(crossedMedia.single.size, 201);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(attachmentA.id),
          ),
          'crossed-key-a',
        );

        // An injected attachment insert crash rolls the parent insert back and
        // the repository compensates the prepared secure key.
        const crashParentId = 'atomic-crash-parent';
        const crashAttachmentId = 'atomic-crash-attachment';
        await fixture.db.execute(
          "CREATE TRIGGER reject_atomic_crash_attachment "
          "BEFORE INSERT ON media_attachments "
          "WHEN NEW.id = '$crashAttachmentId' "
          "BEGIN SELECT RAISE(ABORT, 'injected atomic crash'); END",
        );
        await expectLater(
          fixture.repo.stageOutgoingOrdinaryAttemptWithMedia(
            messageMutationRepository:
                fixture.messageRepo as OutgoingTransportMutationRepository,
            expected: null,
            staged: outgoing(id: crashParentId),
            attachments: <MediaAttachment>[
              attemptAttachment(
                id: crashAttachmentId,
                messageId: crashParentId,
                key: 'crash-key',
              ),
            ],
            kind: OutgoingOrdinaryAttemptKind.fresh,
          ),
          throwsA(isA<DatabaseException>()),
        );
        expect(await fixture.messageRepo.getMessage(crashParentId), isNull);
        expect(await rawRow(crashAttachmentId), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(crashAttachmentId),
          ),
          isFalse,
        );

        // Fresh collision and an update-only removal both write neither side
        // and leave no prepared key behind.
        const collisionId = 'fresh-collision-parent';
        final collisionCurrent = outgoing(
          id: collisionId,
          status: 'delivered',
          wireEnvelope: null,
        );
        await fixture.db.insert('messages', collisionCurrent.toMap());
        const collisionAttachmentId = 'fresh-collision-attachment';
        final collision = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: null,
              staged: outgoing(id: collisionId),
              attachments: <MediaAttachment>[
                attemptAttachment(
                  id: collisionAttachmentId,
                  messageId: collisionId,
                  key: 'collision-key',
                ),
              ],
              kind: OutgoingOrdinaryAttemptKind.fresh,
            );
        expect(collision.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(
          (await fixture.messageRepo.getMessage(collisionId))!.status,
          'delivered',
        );
        expect(await rawRow(collisionAttachmentId), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(collisionAttachmentId),
          ),
          isFalse,
        );

        const removedId = 'removed-before-stage-parent';
        final removedExpected = outgoing(
          id: removedId,
          status: 'failed',
          wireEnvelope: 'removed-old-envelope',
        );
        await fixture.db.insert('messages', removedExpected.toMap());
        await fixture.db.delete(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[removedId],
        );
        const removedAttachmentId = 'removed-before-stage-attachment';
        final removed = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: removedExpected,
              staged: removedExpected.copyWith(
                status: 'sending',
                wireEnvelope: 'removed-new-envelope',
              ),
              attachments: <MediaAttachment>[
                attemptAttachment(
                  id: removedAttachmentId,
                  messageId: removedId,
                  key: 'removed-key',
                ),
              ],
              kind: OutgoingOrdinaryAttemptKind.existing,
            );
        expect(removed.outcome, OutgoingOrdinaryMutationOutcome.removed);
        expect(await fixture.messageRepo.getMessage(removedId), isNull);
        expect(await rawRow(removedAttachmentId), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(removedAttachmentId),
          ),
          isFalse,
        );
      },
    );

    test(
      'TC-345-02 manifest-bound ordinary media stages exact v108 custody atomically',
      () async {
        String envelope(String messageId, {String ciphertext = 'cipher'}) =>
            jsonEncode(<String, Object?>{
              'type': 'chat_message',
              'version': '2',
              'id': messageId,
              'senderPeerId': 'peer-local',
              'encrypted': <String, String>{
                'kem': 'kem-$ciphertext',
                'ciphertext': ciphertext,
                'nonce': 'nonce-$ciphertext',
              },
            });

        ConversationMessage preparedParent({
          required String id,
          required List<String> attachmentIds,
        }) => ConversationMessage(
          id: id,
          contactPeerId: 'peer-media-recipient',
          senderPeerId: 'peer-local',
          text: 'caption',
          timestamp: '2026-08-07T12:00:00.000Z',
          status: 'sending',
          isIncoming: false,
          createdAt: '2026-08-07T12:00:00.000Z',
          directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
            messageId: id,
            attachmentIds: attachmentIds,
          ),
        );

        MediaAttachment pending(String messageId, String attachmentId) =>
            MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'image/jpeg',
              size: 321,
              mediaType: 'image',
              width: 640,
              height: 480,
              localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
              downloadStatus: 'upload_pending',
              createdAt: '2026-08-07T12:00:00.000Z',
              ownerLane: MediaOwnerLane.direct,
            );

        MediaAttachment completed(
          String messageId,
          String attachmentId, {
          String? key,
        }) => pending(messageId, attachmentId).copyWith(
          downloadStatus: 'done',
          localPath: 'media/direct/$attachmentId.jpg',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: key ?? 'raw-key-$attachmentId',
          encryptionNonce: 'blob-nonce-$attachmentId',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        const freshId = 'tc345-fresh-media';
        const freshAttachmentId = 'tc345-fresh-attachment';
        final freshEnvelope = envelope(freshId, ciphertext: 'fresh-cipher');
        final freshParent = ConversationMessage(
          id: freshId,
          contactPeerId: 'peer-media-recipient',
          senderPeerId: 'peer-local',
          text: 'fresh caption',
          timestamp: '2026-08-07T11:59:00.000Z',
          status: 'sending',
          isIncoming: false,
          createdAt: '2026-08-07T11:59:00.000Z',
          wireEnvelope: freshEnvelope,
          media: <MediaAttachment>[completed(freshId, freshAttachmentId)],
        );
        final fresh = await fixture.repo.stageOutgoingDirectMediaInboxCustody(
          expected: null,
          staged: freshParent,
          attachments: freshParent.media,
          kind: OutgoingOrdinaryAttemptKind.fresh,
          recipientPeerId: freshParent.contactPeerId,
          wireEnvelope: freshEnvelope,
        );
        expect(fresh.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(fresh.message!.directMediaCustodyIntentId, isNull);
        expect(fresh.message!.media, hasLength(1));
        expect(fresh.custody!.wireEnvelope, freshEnvelope);
        expect(
          fresh.custody!.incarnationId,
          matches(RegExp(r'^[0-9a-f]{32}$')),
        );

        const forgedId = 'tc345-forged-key-reference';
        const forgedAttachmentId = 'tc345-forged-key-attachment';
        final forgedEnvelope = envelope(forgedId, ciphertext: 'forged');
        final forgedParent = freshParent.copyWith(
          id: forgedId,
          timestamp: '2026-08-07T11:59:30.000Z',
          createdAt: '2026-08-07T11:59:30.000Z',
          wireEnvelope: forgedEnvelope,
          media: <MediaAttachment>[
            completed(
              forgedId,
              forgedAttachmentId,
              key: secureStoreReferenceForKey('attacker-selected'),
            ),
          ],
        );
        final forged = await fixture.repo.stageOutgoingDirectMediaInboxCustody(
          expected: null,
          staged: forgedParent,
          attachments: forgedParent.media,
          kind: OutgoingOrdinaryAttemptKind.fresh,
          recipientPeerId: forgedParent.contactPeerId,
          wireEnvelope: forgedEnvelope,
        );
        expect(forged.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(await fixture.messageRepo.getMessage(forgedId), isNull);
        expect(await rawRow(forgedAttachmentId), isNull);
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[forgedId],
          ),
          isEmpty,
        );
        expect(
          await fixture.secureKeyStore.containsKey('attacker-selected'),
          isFalse,
        );

        const messageId = 'tc345-prepared-media';
        const attachmentIds = <String>[
          'tc345-attachment-b',
          'tc345-attachment-a',
        ];
        final expected = preparedParent(
          id: messageId,
          attachmentIds: attachmentIds,
        );
        await fixture.messageRepo.saveMessage(expected);
        for (final attachmentId in attachmentIds) {
          await fixture.repo.saveAttachment(
            pending(messageId, attachmentId),
            owner: MediaOwnerLane.direct,
          );
        }
        final wireEnvelope = envelope(messageId);
        final staged = expected.copyWith(
          wireEnvelope: wireEnvelope,
          directMediaCustodyIntentId: null,
          media: attachmentIds
              .map((id) => completed(messageId, id))
              .toList(growable: false),
        );

        final result = await fixture.repo.stageOutgoingDirectMediaInboxCustody(
          expected: expected,
          staged: staged,
          attachments: staged.media,
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: 'peer-media-recipient',
          wireEnvelope: wireEnvelope,
        );

        expect(result.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(result.authorizesTransport, isTrue);
        expect(result.message!.wireEnvelope, wireEnvelope);
        expect(result.message!.directMediaCustodyIntentId, isNull);
        expect(
          result.message!.media.map((attachment) => attachment.id).toSet(),
          attachmentIds.toSet(),
        );
        expect(
          result.custody!.incarnationId,
          expected.directMediaCustodyIntentId,
        );
        expect(result.custody!.wireEnvelope, wireEnvelope);
        final durableParent = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single;
        expect(durableParent['direct_media_custody_intent_id'], isNull);
        expect(durableParent['wire_envelope'], wireEnvelope);
        expect(
          (await fixture.db.query(
            'media_attachments',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          )).every((row) => row['download_status'] == 'done'),
          isTrue,
        );

        // A differently encrypted finalizer must adopt the exact winner and
        // restore any raw key it temporarily wrote under the stable reference.
        final loserEnvelope = envelope(messageId, ciphertext: 'loser-cipher');
        final adopted = await fixture.repo.stageOutgoingDirectMediaInboxCustody(
          expected: expected,
          staged: staged.copyWith(wireEnvelope: loserEnvelope),
          attachments: staged.media
              .map(
                (attachment) => attachment.copyWith(
                  encryptionKeyBase64: 'loser-${attachment.id}',
                ),
              )
              .toList(growable: false),
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: 'peer-media-recipient',
          wireEnvelope: loserEnvelope,
        );
        expect(adopted.outcome, OutgoingOrdinaryMutationOutcome.idempotent);
        expect(adopted.custody!.wireEnvelope, wireEnvelope);
        expect(adopted.message!.wireEnvelope, wireEnvelope);
        for (final attachmentId in attachmentIds) {
          expect(
            await fixture.secureKeyStore.read(
              mediaAttachmentEncryptionKeyStoreName(attachmentId),
            ),
            'raw-key-$attachmentId',
          );
        }

        // The legacy media-only seam cannot consume or bypass a fresh intent.
        const exclusiveId = 'tc345-exclusive-media';
        const exclusiveAttachmentId = 'tc345-exclusive-attachment';
        final exclusiveExpected = preparedParent(
          id: exclusiveId,
          attachmentIds: const <String>[exclusiveAttachmentId],
        );
        await fixture.messageRepo.saveMessage(exclusiveExpected);
        await fixture.repo.saveAttachment(
          pending(exclusiveId, exclusiveAttachmentId),
          owner: MediaOwnerLane.direct,
        );
        final exclusiveEnvelope = envelope(exclusiveId);
        final legacy = await fixture.repo.stageOutgoingOrdinaryAttemptWithMedia(
          messageMutationRepository:
              fixture.messageRepo as OutgoingTransportMutationRepository,
          expected: exclusiveExpected,
          staged: exclusiveExpected.copyWith(
            wireEnvelope: exclusiveEnvelope,
            directMediaCustodyIntentId: null,
          ),
          attachments: <MediaAttachment>[
            completed(exclusiveId, exclusiveAttachmentId),
          ],
          kind: OutgoingOrdinaryAttemptKind.existing,
        );
        expect(legacy.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(
          (await fixture.messageRepo.getMessage(
            exclusiveId,
          ))!.directMediaCustodyIntentId,
          exclusiveExpected.directMediaCustodyIntentId,
        );
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[exclusiveId],
          ),
          isEmpty,
        );

        // Outbox insertion failure rolls back parent/media/token and restores
        // the pre-commit secure-key snapshot.
        const rollbackId = 'tc345-rollback-media';
        const rollbackAttachmentId = 'tc345-rollback-attachment';
        final rollbackExpected = preparedParent(
          id: rollbackId,
          attachmentIds: const <String>[rollbackAttachmentId],
        );
        await fixture.messageRepo.saveMessage(rollbackExpected);
        await fixture.repo.saveAttachment(
          pending(rollbackId, rollbackAttachmentId),
          owner: MediaOwnerLane.direct,
        );
        await fixture.db.execute(
          "CREATE TRIGGER tc345_reject_custody BEFORE INSERT ON "
          "direct_inbox_custody_outbox WHEN NEW.message_id = '$rollbackId' "
          "BEGIN SELECT RAISE(ABORT, 'tc345 failpoint'); END",
        );
        final rollbackEnvelope = envelope(rollbackId);
        await expectLater(
          fixture.repo.stageOutgoingDirectMediaInboxCustody(
            expected: rollbackExpected,
            staged: rollbackExpected.copyWith(
              wireEnvelope: rollbackEnvelope,
              directMediaCustodyIntentId: null,
            ),
            attachments: <MediaAttachment>[
              completed(rollbackId, rollbackAttachmentId),
            ],
            kind: OutgoingOrdinaryAttemptKind.existing,
            recipientPeerId: 'peer-media-recipient',
            wireEnvelope: rollbackEnvelope,
          ),
          throwsA(isA<DatabaseException>()),
        );
        final rollbackParent = await fixture.messageRepo.getMessage(rollbackId);
        expect(
          rollbackParent!.directMediaCustodyIntentId,
          rollbackExpected.directMediaCustodyIntentId,
        );
        expect(rollbackParent.wireEnvelope, isNull);
        expect(
          (await rawRow(rollbackAttachmentId))!['download_status'],
          'upload_pending',
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(rollbackAttachmentId),
          ),
          isFalse,
        );
      },
    );

    test(
      'TC-345-02b crossed saves preserve one owner through exact completion; TC-345-02c generic media staging cannot overwrite a consumed v108 winner; TC-345-02g completion-before-stale-save stays settled',
      () async {
        const messageId = 'tc345-crossed-finalizers';
        const attachmentId = 'tc345-crossed-finalizers-attachment';
        final intent = computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: const <String>[attachmentId],
        );
        final expected = ConversationMessage(
          id: messageId,
          contactPeerId: 'peer-crossed-recipient',
          senderPeerId: 'peer-local',
          text: 'crossed caption',
          timestamp: '2026-08-07T13:00:00.000Z',
          status: 'sending',
          isIncoming: false,
          createdAt: '2026-08-07T13:00:00.000Z',
          directMediaCustodyIntentId: intent,
        );
        final pending = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 451,
          mediaType: 'image',
          localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
          downloadStatus: 'upload_pending',
          createdAt: expected.createdAt,
          ownerLane: MediaOwnerLane.direct,
        );
        MediaAttachment completed(String key) => pending.copyWith(
          downloadStatus: 'done',
          localPath: 'media/direct/$attachmentId.jpg',
          contentHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          encryptionKeyBase64: key,
          encryptionNonce: 'crossed-blob-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        String envelope(String suffix) => jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': messageId,
          'senderPeerId': 'peer-local',
          'encrypted': <String, String>{
            'kem': 'kem-$suffix',
            'ciphertext': 'cipher-$suffix',
            'nonce': 'nonce-$suffix',
          },
        });

        await fixture.messageRepo.saveMessage(expected);
        await fixture.repo.saveAttachment(
          pending,
          owner: MediaOwnerLane.direct,
        );

        // A stale generic null save cannot erase the insert-once intent.
        await fixture.messageRepo.saveMessage(
          expected.copyWith(directMediaCustodyIntentId: null),
        );
        expect(
          (await fixture.messageRepo.getMessage(
            messageId,
          ))!.directMediaCustodyIntentId,
          intent,
        );

        final winnerEnvelope = envelope('winner');
        final winner = await fixture.repo.stageOutgoingDirectMediaInboxCustody(
          expected: expected,
          staged: expected.copyWith(
            wireEnvelope: winnerEnvelope,
            directMediaCustodyIntentId: null,
          ),
          attachments: <MediaAttachment>[completed('winner-key')],
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: expected.contactPeerId,
          wireEnvelope: winnerEnvelope,
        );
        expect(winner.outcome, OutgoingOrdinaryMutationOutcome.applied);

        final exactWinnerAttachment = Map<String, Object?>.from(
          (await rawRow(attachmentId))!,
        );
        final secureWritesAfterWinner =
            fixture.secureKeyStore.writtenKeys.length;
        final stalePreUpload = pending.copyWith(
          size: 999,
          contentHash:
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          encryptionKeyBase64: 'stale-pre-upload-key',
          encryptionNonce: 'stale-pre-upload-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        await fixture.repo.saveAttachment(
          stalePreUpload,
          owner: MediaOwnerLane.direct,
        );
        expect(
          await rawRow(attachmentId),
          exactWinnerAttachment,
          reason: 'active v108 must reject a delayed generic pre-upload row',
        );
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          secureWritesAfterWinner,
          reason: 'custody refusal must happen before any secure-store write',
        );
        expect(
          (await fixture.repo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          )).single.encryptionKeyBase64,
          'winner-key',
        );

        // A stale token-bearing whole-row save can neither re-arm consumed
        // intent nor erase/drift the exact winner-owned parent projection.
        await fixture.messageRepo.saveMessage(
          expected.copyWith(
            contactPeerId: 'peer-crossed-drift',
            senderPeerId: 'peer-crossed-wrong-sender',
            isIncoming: true,
            status: 'failed',
            transport: 'direct',
            relayExpiresAt: 999,
            custodyCheckedAt: '2026-08-07T13:00:01.000Z',
          ),
        );
        final parentAfterStaleSave = (await fixture.messageRepo.getMessage(
          messageId,
        ))!;
        expect(parentAfterStaleSave.directMediaCustodyIntentId, isNull);
        expect(parentAfterStaleSave.contactPeerId, expected.contactPeerId);
        expect(parentAfterStaleSave.senderPeerId, expected.senderPeerId);
        expect(parentAfterStaleSave.isIncoming, isFalse);
        expect(parentAfterStaleSave.status, 'sending');
        expect(parentAfterStaleSave.wireEnvelope, winnerEnvelope);
        expect(parentAfterStaleSave.transport, isNull);
        expect(parentAfterStaleSave.relayExpiresAt, isNull);
        expect(parentAfterStaleSave.custodyCheckedAt, isNull);

        final loserEnvelope = envelope('loser');
        final loser = await fixture.repo.stageOutgoingDirectMediaInboxCustody(
          expected: expected,
          staged: expected.copyWith(
            wireEnvelope: loserEnvelope,
            directMediaCustodyIntentId: null,
          ),
          attachments: <MediaAttachment>[completed('loser-key')],
          kind: OutgoingOrdinaryAttemptKind.existing,
          recipientPeerId: expected.contactPeerId,
          wireEnvelope: loserEnvelope,
        );
        expect(loser.outcome, OutgoingOrdinaryMutationOutcome.idempotent);
        expect(loser.custody!.incarnationId, intent);
        expect(loser.custody!.wireEnvelope, winnerEnvelope);
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          hasLength(1),
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          'winner-key',
        );

        final parentBeforeGenericStage = await fixture.messageRepo.getMessage(
          messageId,
        );
        final attachmentBeforeGenericStage = await rawRow(attachmentId);
        final custodyBeforeGenericStage = (await fixture.db.query(
          'direct_inbox_custody_outbox',
          where: 'recipient_peer_id = ? AND message_id = ?',
          whereArgs: <Object?>[expected.contactPeerId, messageId],
        )).single;
        final genericLoser = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: parentBeforeGenericStage,
              staged: parentBeforeGenericStage!.copyWith(
                wireEnvelope: envelope('generic-loser'),
              ),
              attachments: <MediaAttachment>[completed('generic-loser-key')],
              kind: OutgoingOrdinaryAttemptKind.existing,
            );

        expect(genericLoser.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(
          (await fixture.messageRepo.getMessage(messageId))!.toMap(),
          parentBeforeGenericStage.toMap(),
        );
        expect(await rawRow(attachmentId), attachmentBeforeGenericStage);
        expect(
          (await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'recipient_peer_id = ? AND message_id = ?',
            whereArgs: <Object?>[expected.contactPeerId, messageId],
          )).single,
          custodyBeforeGenericStage,
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          'winner-key',
        );

        final completion = await dbCompleteAcceptedDirectInboxCustodyIfExact(
          fixture.db,
          recipientPeerId: expected.contactPeerId,
          messageId: messageId,
          expectedIncarnationId: intent,
          expectedWireEnvelope: winnerEnvelope,
          relayExpiresAt: 123456,
        );
        expect(completion, DirectInboxCustodyCompletionOutcome.messageAdvanced);
        final completedParent = (await fixture.messageRepo.getMessage(
          messageId,
        ))!;
        expect(completedParent.status, 'inboxed');
        expect(completedParent.wireEnvelope, winnerEnvelope);
        expect(completedParent.transport, 'inbox');
        expect(completedParent.relayExpiresAt, 123456);
        expect(completedParent.directMediaCustodyIntentId, isNull);
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[messageId],
          ),
          isEmpty,
        );

        final secureWritesBeforePostCompletionStale =
            fixture.secureKeyStore.writtenKeys.length;
        await fixture.repo.saveAttachment(
          stalePreUpload.copyWith(
            encryptionKeyBase64: 'stale-after-completion-key',
            encryptionNonce: 'stale-after-completion-nonce',
          ),
          owner: MediaOwnerLane.direct,
        );
        expect(
          await rawRow(attachmentId),
          exactWinnerAttachment,
          reason:
              'the exact complete encrypted winner must remain monotonic after v108 retirement',
        );
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          secureWritesBeforePostCompletionStale,
        );
        expect(
          (await fixture.repo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.direct,
          )).single.encryptionKeyBase64,
          'winner-key',
        );

        await fixture.messageRepo.saveMessage(
          expected.copyWith(
            status: 'failed',
            wireEnvelope: envelope('stale-after-completion'),
            transport: 'direct',
            relayExpiresAt: null,
            custodyCheckedAt: '2026-08-07T13:05:00.000Z',
          ),
        );
        final completedAfterStaleSave = (await fixture.messageRepo.getMessage(
          messageId,
        ))!;
        expect(completedAfterStaleSave.status, 'inboxed');
        expect(completedAfterStaleSave.wireEnvelope, winnerEnvelope);
        expect(completedAfterStaleSave.transport, 'inbox');
        expect(completedAfterStaleSave.relayExpiresAt, 123456);
        expect(completedAfterStaleSave.custodyCheckedAt, isNull);

        final recoveryEnvelope = envelope('post-completion-recovery');
        final recovery = await fixture.repo
            .stageOutgoingOrdinaryAttemptWithMedia(
              messageMutationRepository:
                  fixture.messageRepo as OutgoingTransportMutationRepository,
              expected: completedParent,
              staged: completedParent.copyWith(
                status: 'sending',
                wireEnvelope: recoveryEnvelope,
                transport: null,
                relayExpiresAt: null,
                custodyCheckedAt: null,
              ),
              attachments: <MediaAttachment>[completed('recovery-key')],
              kind: OutgoingOrdinaryAttemptKind.existing,
            );
        expect(recovery.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(
          (await fixture.messageRepo.getMessage(messageId))!.wireEnvelope,
          winnerEnvelope,
          reason: 'recovery cannot emit a second initial envelope',
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          'winner-key',
        );

        const legacySettledId = 'tc345-no-token-settled-control';
        const legacySettledAttachmentId =
            'tc345-no-token-settled-control-attachment';
        final legacySettledEnvelope = jsonEncode(<String, Object?>{
          'type': 'chat_message',
          'version': '2',
          'id': legacySettledId,
          'senderPeerId': 'peer-local',
          'encrypted': const <String, String>{
            'kem': 'legacy-kem',
            'ciphertext': 'legacy-ciphertext',
            'nonce': 'legacy-nonce',
          },
        });
        await fixture.messageRepo.saveMessage(
          ConversationMessage(
            id: legacySettledId,
            contactPeerId: 'peer-legacy-recipient',
            senderPeerId: 'peer-local',
            text: 'legacy settled media',
            timestamp: '2026-08-07T13:10:00.000Z',
            status: 'inboxed',
            isIncoming: false,
            createdAt: '2026-08-07T13:10:00.000Z',
            transport: 'inbox',
            wireEnvelope: legacySettledEnvelope,
          ),
        );
        final legacyIncomplete = MediaAttachment(
          id: legacySettledAttachmentId,
          messageId: legacySettledId,
          mime: 'image/jpeg',
          size: 101,
          mediaType: 'image',
          localPath:
              'pending_uploads/$legacySettledId/$legacySettledAttachmentId.jpg',
          downloadStatus: 'upload_pending',
          createdAt: '2026-08-07T13:10:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(
          legacyIncomplete,
          owner: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(
          legacyIncomplete.copyWith(
            size: 202,
            contentHash:
                '1111111111111111111111111111111111111111111111111111111111111111',
            encryptionKeyBase64: 'legacy-settled-key',
            encryptionNonce: 'legacy-settled-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.direct,
        );
        expect(
          (await rawRow(legacySettledAttachmentId))!['size'],
          202,
          reason:
              'an indistinguishable no-token settled parent cannot freeze an incomplete attachment',
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(legacySettledAttachmentId),
          ),
          'legacy-settled-key',
        );

        final writesBeforeLegacyLifecycleRepair =
            fixture.secureKeyStore.writtenKeys.length;
        await fixture.repo.saveAttachment(
          legacyIncomplete.copyWith(
            size: 303,
            clearLocalPath: true,
            downloadStatus: 'failed',
            uploadRetryCount: 4,
            contentHash:
                '2222222222222222222222222222222222222222222222222222222222222222',
            encryptionKeyBase64: 'legacy-drift-key',
            encryptionNonce: 'legacy-drift-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.direct,
        );
        final repairedLegacy = (await rawRow(legacySettledAttachmentId))!;
        expect(repairedLegacy['size'], 202);
        expect(repairedLegacy['local_path'], isNull);
        expect(repairedLegacy['download_status'], 'failed');
        expect(repairedLegacy['upload_retry_count'], 4);
        expect(
          repairedLegacy['content_hash'],
          '1111111111111111111111111111111111111111111111111111111111111111',
        );
        expect(repairedLegacy['encryption_nonce'], 'legacy-settled-nonce');
        expect(
          repairedLegacy['encryption_scheme'],
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(
          repairedLegacy['encryption_key_base64'],
          secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName(legacySettledAttachmentId),
          ),
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(legacySettledAttachmentId),
          ),
          'legacy-settled-key',
        );
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeLegacyLifecycleRepair,
          reason:
              'legacy lifecycle repair must not write a stale replacement key',
        );

        const incomingId = 'tc345-incoming-lifecycle-control';
        const incomingAttachmentId =
            'tc345-incoming-lifecycle-control-attachment';
        await fixture.seedDirectParent(incomingId);
        final incomingComplete = MediaAttachment(
          id: incomingAttachmentId,
          messageId: incomingId,
          mime: 'image/jpeg',
          size: 404,
          mediaType: 'image',
          width: 640,
          height: 480,
          localPath: 'media/contact-1/$incomingAttachmentId.jpg',
          downloadStatus: 'done',
          createdAt: '2026-08-07T13:15:00.000Z',
          contentHash:
              '3333333333333333333333333333333333333333333333333333333333333333',
          encryptionKeyBase64: 'incoming-winner-key',
          encryptionNonce: 'incoming-winner-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(
          incomingComplete,
          owner: MediaOwnerLane.direct,
        );
        final writesBeforeIncomingLifecycleRepair =
            fixture.secureKeyStore.writtenKeys.length;
        await fixture.repo.saveAttachment(
          incomingComplete.copyWith(
            size: 505,
            clearLocalPath: true,
            downloadStatus: 'failed',
            downloadRetryCount: 2,
            contentHash:
                '4444444444444444444444444444444444444444444444444444444444444444',
            encryptionKeyBase64: 'incoming-drift-key',
            encryptionNonce: 'incoming-drift-nonce',
          ),
          owner: MediaOwnerLane.direct,
        );
        final repairedIncoming = (await rawRow(incomingAttachmentId))!;
        expect(repairedIncoming['size'], 404);
        expect(repairedIncoming['local_path'], isNull);
        expect(repairedIncoming['download_status'], 'failed');
        expect(repairedIncoming['download_retry_count'], 2);
        expect(
          repairedIncoming['content_hash'],
          '3333333333333333333333333333333333333333333333333333333333333333',
        );
        expect(repairedIncoming['encryption_nonce'], 'incoming-winner-nonce');
        expect(
          repairedIncoming['encryption_key_base64'],
          secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName(incomingAttachmentId),
          ),
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(incomingAttachmentId),
          ),
          'incoming-winner-key',
        );
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeIncomingLifecycleRepair,
          reason:
              'incoming lifecycle repair must not write a stale replacement key',
        );
      },
    );

    test(
      'TC-345-02d immutable v108 winner survives settlement and physical deletion crossings; TC-345-02f physical deletion rejects generic resurrection through completion and recovery; TC-345-02h messageRemoved-before-stale-save retains deletion authority',
      () async {
        ConversationMessage preparedParent(String messageId) {
          final attachmentId = '$messageId-attachment';
          return ConversationMessage(
            id: messageId,
            contactPeerId: 'peer-late-winner',
            senderPeerId: 'peer-local',
            text: 'late winner caption',
            timestamp: '2026-08-07T13:30:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-08-07T13:30:00.000Z',
            directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
              messageId: messageId,
              attachmentIds: <String>[attachmentId],
            ),
          );
        }

        MediaAttachment pending(String messageId) {
          final attachmentId = '$messageId-attachment';
          return MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 509,
            mediaType: 'image',
            width: 320,
            height: 240,
            localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-08-07T13:30:00.000Z',
            ownerLane: MediaOwnerLane.direct,
          );
        }

        MediaAttachment completed(
          String messageId,
          String key,
        ) => pending(messageId).copyWith(
          downloadStatus: 'done',
          localPath: 'media/direct/$messageId.jpg',
          contentHash:
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          encryptionKeyBase64: key,
          encryptionNonce: 'nonce-$messageId',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        String envelope(String messageId, String suffix) =>
            jsonEncode(<String, Object?>{
              'type': 'chat_message',
              'version': '2',
              'id': messageId,
              'senderPeerId': 'peer-local',
              'encrypted': <String, String>{
                'kem': 'kem-$suffix',
                'ciphertext': 'cipher-$suffix',
                'nonce': 'nonce-$suffix',
              },
            });

        Future<String> commitWinner(String messageId) async {
          final expected = preparedParent(messageId);
          final pendingAttachment = pending(messageId);
          await fixture.messageRepo.saveMessage(expected);
          await fixture.repo.saveAttachment(
            pendingAttachment,
            owner: MediaOwnerLane.direct,
          );
          final winnerEnvelope = envelope(messageId, 'winner');
          final winner = await fixture.repo
              .stageOutgoingDirectMediaInboxCustody(
                expected: expected,
                staged: expected.copyWith(
                  wireEnvelope: winnerEnvelope,
                  directMediaCustodyIntentId: null,
                ),
                attachments: <MediaAttachment>[
                  completed(messageId, 'winner-key-$messageId'),
                ],
                kind: OutgoingOrdinaryAttemptKind.existing,
                recipientPeerId: expected.contactPeerId,
                wireEnvelope: winnerEnvelope,
              );
          expect(winner.outcome, OutgoingOrdinaryMutationOutcome.applied);
          return winnerEnvelope;
        }

        const settledId = 'tc345-winner-before-settlement';
        final settledExpected = preparedParent(settledId);
        final settledWinnerEnvelope = await commitWinner(settledId);
        final settlement =
            await (fixture.messageRepo as OutgoingTransportMutationRepository)
                .settleOutgoingOrdinaryTransport(
                  messageId: settledId,
                  expectedContactPeerId: settledExpected.contactPeerId,
                  expectedEnvelope: settledWinnerEnvelope,
                  status: 'sent',
                  transport: 'direct',
                  relayExpiresAt: null,
                  mode: OutgoingOrdinarySettlementMode.live,
                );
        expect(settlement.outcome, OutgoingOrdinaryMutationOutcome.applied);
        final settledCustodyBefore = (await fixture.db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[settledId],
        )).single;

        final settledLoserEnvelope = envelope(settledId, 'settled-loser');
        final settledLoser = await fixture.repo
            .stageOutgoingDirectMediaInboxCustody(
              expected: settledExpected,
              staged: settledExpected.copyWith(
                wireEnvelope: settledLoserEnvelope,
                directMediaCustodyIntentId: null,
              ),
              attachments: <MediaAttachment>[
                completed(settledId, 'settled-loser-key'),
              ],
              kind: OutgoingOrdinaryAttemptKind.existing,
              recipientPeerId: settledExpected.contactPeerId,
              wireEnvelope: settledLoserEnvelope,
            );

        expect(
          settledLoser.outcome,
          OutgoingOrdinaryMutationOutcome.idempotent,
        );
        expect(settledLoser.authorizesTransport, isTrue);
        expect(settledLoser.custody!.wireEnvelope, settledWinnerEnvelope);
        expect(settledLoser.message!.status, 'sent');
        expect(settledLoser.message!.transport, 'direct');
        expect(settledLoser.message!.media, isEmpty);
        expect(
          (await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[settledId],
          )).single,
          settledCustodyBefore,
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName('$settledId-attachment'),
          ),
          'winner-key-$settledId',
        );

        const deletedId = 'tc345-winner-before-deletion';
        final deletedExpected = preparedParent(deletedId);
        final deletedWinnerEnvelope = await commitWinner(deletedId);
        final deletedCustodyBefore = (await fixture.db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[deletedId],
        )).single;
        expect(
          await fixture.repo.deleteAttachmentsForMessage(
            deletedId,
            owner: MediaOwnerLane.direct,
          ),
          1,
        );
        await fixture.secureKeyStore.delete(
          mediaAttachmentEncryptionKeyStoreName('$deletedId-attachment'),
        );
        expect(await fixture.messageRepo.deleteMessage(deletedId), 1);

        final deletedStaleAttachment = pending(deletedId).copyWith(
          contentHash:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
          encryptionKeyBase64: 'deleted-stale-key',
          encryptionNonce: 'deleted-stale-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        final deletedKeyName = mediaAttachmentEncryptionKeyStoreName(
          '$deletedId-attachment',
        );
        final writesBeforeDeletedStale =
            fixture.secureKeyStore.writtenKeys.length;
        await fixture.repo.saveAttachment(
          deletedStaleAttachment,
          owner: MediaOwnerLane.direct,
        );
        expect(await rawRow('$deletedId-attachment'), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(deletedKeyName),
          isFalse,
        );
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeDeletedStale,
          reason:
              'active v108 must block row and key resurrection before any write',
        );

        final deletedLoserEnvelope = envelope(deletedId, 'deleted-loser');
        final deletedLoser = await fixture.repo
            .stageOutgoingDirectMediaInboxCustody(
              expected: deletedExpected,
              staged: deletedExpected.copyWith(
                wireEnvelope: deletedLoserEnvelope,
                directMediaCustodyIntentId: null,
              ),
              attachments: <MediaAttachment>[
                completed(deletedId, 'deleted-loser-key'),
              ],
              kind: OutgoingOrdinaryAttemptKind.existing,
              recipientPeerId: deletedExpected.contactPeerId,
              wireEnvelope: deletedLoserEnvelope,
            );

        expect(
          deletedLoser.outcome,
          OutgoingOrdinaryMutationOutcome.idempotent,
        );
        expect(deletedLoser.authorizesTransport, isTrue);
        expect(deletedLoser.custody!.wireEnvelope, deletedWinnerEnvelope);
        expect(
          deletedLoser.message,
          isNull,
          reason: 'immutable custody must not resurrect a deleted projection',
        );
        expect(await fixture.messageRepo.getMessage(deletedId), isNull);
        expect(await rawRow('$deletedId-attachment'), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('$deletedId-attachment'),
          ),
          isFalse,
        );
        expect(
          (await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[deletedId],
          )).single,
          deletedCustodyBefore,
        );

        await fixture.db.update(
          'direct_inbox_custody_outbox',
          {'incarnation_id': 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'},
          where: 'message_id = ?',
          whereArgs: <Object?>[deletedId],
        );
        final mismatched = await fixture.repo
            .stageOutgoingDirectMediaInboxCustody(
              expected: deletedExpected,
              staged: deletedExpected.copyWith(
                wireEnvelope: deletedLoserEnvelope,
                directMediaCustodyIntentId: null,
              ),
              attachments: <MediaAttachment>[
                completed(deletedId, 'mismatched-loser-key'),
              ],
              kind: OutgoingOrdinaryAttemptKind.existing,
              recipientPeerId: deletedExpected.contactPeerId,
              wireEnvelope: deletedLoserEnvelope,
            );
        expect(mismatched.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(mismatched.authorizesTransport, isFalse);
        expect(await fixture.messageRepo.getMessage(deletedId), isNull);
        expect(await rawRow('$deletedId-attachment'), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('$deletedId-attachment'),
          ),
          isFalse,
        );

        await expectLater(
          fixture.messageRepo.saveMessage(deletedExpected),
          throwsA(isA<StateError>()),
        );
        expect(await fixture.messageRepo.getMessage(deletedId), isNull);
        expect(await rawRow('$deletedId-attachment'), isNull);
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[deletedId],
          ),
          hasLength(1),
        );

        await fixture.db.update(
          'direct_inbox_custody_outbox',
          {'incarnation_id': deletedExpected.directMediaCustodyIntentId},
          where: 'message_id = ?',
          whereArgs: <Object?>[deletedId],
        );
        final deletedCompletion =
            await dbCompleteAcceptedDirectInboxCustodyIfExact(
              fixture.db,
              recipientPeerId: deletedExpected.contactPeerId,
              messageId: deletedId,
              expectedIncarnationId:
                  deletedExpected.directMediaCustodyIntentId!,
              expectedWireEnvelope: deletedWinnerEnvelope,
              relayExpiresAt: 222222,
            );
        expect(
          deletedCompletion,
          DirectInboxCustodyCompletionOutcome.messageRemoved,
        );
        final deletionTombstone = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[deletedId],
        )).single;
        expect(
          deletionTombstone,
          allOf(
            containsPair('contact_peer_id', deletedExpected.contactPeerId),
            containsPair('sender_peer_id', deletedExpected.senderPeerId),
            containsPair('text', ''),
            containsPair('status', 'inboxed'),
            containsPair('wire_envelope', null),
            containsPair('transport', 'inbox'),
            allOf(
              containsPair('relay_expires_at', 222222),
              containsPair('hidden_at', isNotNull),
            ),
          ),
        );
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: <Object?>[deletedId],
          ),
          isEmpty,
        );
        final writesBeforeTombstoneStale =
            fixture.secureKeyStore.writtenKeys.length;
        await fixture.repo.saveAttachment(
          deletedStaleAttachment.copyWith(
            encryptionKeyBase64: 'tombstone-stale-key',
          ),
          owner: MediaOwnerLane.direct,
        );
        expect(await rawRow('$deletedId-attachment'), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(deletedKeyName),
          isFalse,
        );
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeTombstoneStale,
          reason:
              'the exact completion tombstone must retain attachment deletion authority',
        );
        await fixture.messageRepo.saveMessage(
          deletedExpected.copyWith(
            status: 'failed',
            wireEnvelope: deletedLoserEnvelope,
            transport: 'direct',
            custodyCheckedAt: '2026-08-07T13:40:00.000Z',
          ),
        );
        expect(
          (await fixture.db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[deletedId],
          )).single,
          deletionTombstone,
          reason:
              'completion-before-stale-save must retain the hidden deletion authority',
        );
        expect(
          (await fixture.messageRepo.getMessagesForContact(
            deletedExpected.contactPeerId,
          )).where((message) => message.id == deletedId),
          isEmpty,
        );

        final postCompletionRecovery = await fixture.repo
            .stageOutgoingDirectMediaInboxCustody(
              expected: deletedExpected,
              staged: deletedExpected.copyWith(
                wireEnvelope: deletedLoserEnvelope,
                directMediaCustodyIntentId: null,
              ),
              attachments: <MediaAttachment>[
                completed(deletedId, 'post-completion-recovery-key'),
              ],
              kind: OutgoingOrdinaryAttemptKind.existing,
              recipientPeerId: deletedExpected.contactPeerId,
              wireEnvelope: deletedLoserEnvelope,
            );
        expect(
          postCompletionRecovery.outcome,
          OutgoingOrdinaryMutationOutcome.refused,
        );
        expect(
          (await fixture.db.query(
            'messages',
            where: 'id = ?',
            whereArgs: <Object?>[deletedId],
          )).single,
          deletionTombstone,
        );
        expect(await rawRow('$deletedId-attachment'), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('$deletedId-attachment'),
          ),
          isFalse,
        );

        const retainedDeletionId = 'tc345-retained-deletion-parent';
        final retainedDeletionExpected = preparedParent(retainedDeletionId);
        final retainedDeletionWinnerEnvelope = await commitWinner(
          retainedDeletionId,
        );
        expect(
          await fixture.repo.deleteAttachmentsForMessage(
            retainedDeletionId,
            owner: MediaOwnerLane.direct,
          ),
          1,
        );
        final retainedDeletionAttachmentId = '$retainedDeletionId-attachment';
        final retainedDeletionKeyName = mediaAttachmentEncryptionKeyStoreName(
          retainedDeletionAttachmentId,
        );
        await fixture.secureKeyStore.delete(retainedDeletionKeyName);
        final deletionEnvelope = jsonEncode(<String, Object?>{
          'type': 'message_deletion',
          'version': '2',
          'senderPeerId': retainedDeletionExpected.senderPeerId,
          'encrypted': const <String, String>{
            'kem': 'delete-kem',
            'ciphertext': 'delete-ciphertext',
            'nonce': 'delete-nonce',
          },
        });
        const retainedDeletedAt = '2026-08-07T13:45:00.000Z';
        final retainedParent = (await fixture.messageRepo.getMessage(
          retainedDeletionId,
        ))!;
        await fixture.messageRepo.saveMessage(
          retainedParent.copyWith(
            text: '',
            status: 'sending',
            deletedAt: retainedDeletedAt,
            deletedByPeerId: retainedDeletionExpected.senderPeerId,
            wireEnvelope: deletionEnvelope,
          ),
        );
        final retainedCompletion =
            await dbCompleteAcceptedDirectInboxCustodyIfExact(
              fixture.db,
              recipientPeerId: retainedDeletionExpected.contactPeerId,
              messageId: retainedDeletionId,
              expectedIncarnationId:
                  retainedDeletionExpected.directMediaCustodyIntentId!,
              expectedWireEnvelope: retainedDeletionWinnerEnvelope,
              relayExpiresAt: 333333,
            );
        expect(
          retainedCompletion,
          DirectInboxCustodyCompletionOutcome.messagePreserved,
        );
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: const <Object?>[retainedDeletionId],
          ),
          isEmpty,
        );
        final retainedDeletionRow = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[retainedDeletionId],
        )).single;
        expect(retainedDeletionRow['deleted_at'], retainedDeletedAt);
        expect(
          retainedDeletionRow['deleted_by_peer_id'],
          retainedDeletionExpected.senderPeerId,
        );
        expect(retainedDeletionRow['wire_envelope'], deletionEnvelope);
        final writesBeforeRetainedDeletionStale =
            fixture.secureKeyStore.writtenKeys.length;
        await fixture.repo.saveAttachment(
          pending(retainedDeletionId).copyWith(
            contentHash:
                'abababababababababababababababababababababababababababababababab',
            encryptionKeyBase64: 'retained-deletion-stale-key',
            encryptionNonce: 'retained-deletion-stale-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.direct,
        );
        expect(await rawRow(retainedDeletionAttachmentId), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(retainedDeletionKeyName),
          isFalse,
        );
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeRetainedDeletionStale,
          reason:
              'an exact retained delete-for-everyone tombstone must prevent attachment/key resurrection',
        );

        const legacyId = 'tc345-no-token-hidden-control';
        final legacyParent = preparedParent(legacyId).copyWith(
          directMediaCustodyIntentId: null,
          status: 'failed',
          hiddenAt: '2026-08-07T13:50:00.000Z',
        );
        await fixture.messageRepo.saveMessage(legacyParent);
        final legacyAttachment = pending(legacyId).copyWith(
          encryptionKeyBase64: 'legacy-control-key',
          encryptionNonce: 'legacy-control-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        await fixture.repo.saveAttachment(
          legacyAttachment,
          owner: MediaOwnerLane.direct,
        );
        expect(await rawRow('$legacyId-attachment'), isNotNull);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName('$legacyId-attachment'),
          ),
          'legacy-control-key',
          reason:
              'a no-token legacy hidden parent must retain generic save behavior',
        );
      },
    );

    test(
      'TC-345-02i final custody race compensates a replaced or newly written secure key',
      () async {
        await fixture.dispose();
        String? custodyIncarnationOnNextPersist;
        fixture = await MediaRepositoryRealDbFixture.create(
          dbSaveMediaAttachmentAround: (row, persist) async {
            final incarnation = custodyIncarnationOnNextPersist;
            if (incarnation != null) {
              custodyIncarnationOnNextPersist = null;
              final messageId = row['message_id']! as String;
              final envelope = jsonEncode(<String, Object?>{
                'type': 'chat_message',
                'version': '2',
                'id': messageId,
                'senderPeerId': 'peer-local',
                'encrypted': const <String, String>{
                  'kem': 'race-kem',
                  'ciphertext': 'race-ciphertext',
                  'nonce': 'race-nonce',
                },
              });
              await fixture.db
                  .insert('direct_inbox_custody_outbox', <String, Object?>{
                    'recipient_peer_id': 'peer-race-recipient',
                    'message_id': messageId,
                    'incarnation_id': incarnation,
                    'wire_envelope': envelope,
                    'retry_count': 0,
                    'last_attempt_at': null,
                    'last_error_code': null,
                    'created_at': '2026-08-07T13:55:00.000Z',
                    'updated_at': '2026-08-07T13:55:00.000Z',
                  });
            }
            await persist();
          },
        );

        ConversationMessage parent(String id) => ConversationMessage(
          id: id,
          contactPeerId: 'peer-race-recipient',
          senderPeerId: 'peer-local',
          text: 'race caption',
          timestamp: '2026-08-07T13:55:00.000Z',
          status: 'sending',
          isIncoming: false,
          createdAt: '2026-08-07T13:55:00.000Z',
        );

        const existingMessageId = 'tc345-final-race-existing';
        const existingAttachmentId = 'tc345-final-race-existing-attachment';
        await fixture.messageRepo.saveMessage(parent(existingMessageId));
        final existingAttachment = makeAttachment(
          id: existingAttachmentId,
          messageId: existingMessageId,
          encryptionKeyBase64: 'race-original-key',
          encryptionNonce: 'race-original-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        await fixture.repo.saveAttachment(
          existingAttachment,
          owner: MediaOwnerLane.direct,
        );
        final existingRow = Map<String, Object?>.from(
          (await rawRow(existingAttachmentId))!,
        );
        final writesBeforeReplacement =
            fixture.secureKeyStore.writtenKeys.length;
        custodyIncarnationOnNextPersist = '11111111111111111111111111111111';

        await fixture.repo.saveAttachment(
          existingAttachment.copyWith(
            size: 999,
            encryptionKeyBase64: 'race-loser-key',
            encryptionNonce: 'race-loser-nonce',
          ),
          owner: MediaOwnerLane.direct,
        );

        expect(await rawRow(existingAttachmentId), existingRow);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(existingAttachmentId),
          ),
          'race-original-key',
        );
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeReplacement + 2,
          reason: 'the loser write and compensating restore are both visible',
        );

        const missingMessageId = 'tc345-final-race-missing';
        const missingAttachmentId = 'tc345-final-race-missing-attachment';
        await fixture.messageRepo.saveMessage(parent(missingMessageId));
        custodyIncarnationOnNextPersist = '22222222222222222222222222222222';
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: missingAttachmentId,
            messageId: missingMessageId,
            encryptionKeyBase64: 'race-new-loser-key',
            encryptionNonce: 'race-new-loser-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.direct,
        );
        expect(await rawRow(missingAttachmentId), isNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(missingAttachmentId),
          ),
          isFalse,
          reason: 'a final-race loser must delete its newly written key',
        );
      },
    );

    test('TC-345-09 media intent has one staging authority', () async {
      expect(fixture.repo.supportsDirectMediaInboxCustody, isTrue);

      const messageId = 'tc345-exclusive-authority';
      const attachmentId = 'tc345-exclusive-authority-attachment';
      final intent = computeDirectMediaCustodyIntentId(
        messageId: messageId,
        attachmentIds: const <String>[attachmentId],
      );
      final expected = ConversationMessage(
        id: messageId,
        contactPeerId: 'peer-exclusive-recipient',
        senderPeerId: 'peer-local',
        text: '',
        timestamp: '2026-08-07T14:00:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-08-07T14:00:00.000Z',
        directMediaCustodyIntentId: intent,
      );
      final completed = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'audio/mp4',
        size: 712,
        mediaType: 'audio',
        durationMs: 900,
        localPath: 'media/direct/$attachmentId.m4a',
        downloadStatus: 'done',
        createdAt: expected.createdAt,
        contentHash:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        encryptionKeyBase64: 'exclusive-raw-key',
        encryptionNonce: 'exclusive-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ownerLane: MediaOwnerLane.direct,
      );
      await fixture.messageRepo.saveMessage(expected);
      await fixture.repo.saveAttachment(
        completed.copyWith(
          downloadStatus: 'upload_pending',
          clearContentHash: true,
          clearEncryptionKeyBase64: true,
          clearEncryptionNonce: true,
          clearEncryptionScheme: true,
        ),
        owner: MediaOwnerLane.direct,
      );
      final envelope = jsonEncode(<String, Object?>{
        'type': 'chat_message',
        'version': '2',
        'id': messageId,
        'senderPeerId': 'peer-local',
        'encrypted': const <String, String>{
          'kem': 'kem-exclusive',
          'ciphertext': 'cipher-exclusive',
          'nonce': 'nonce-exclusive',
        },
      });
      final staged = expected.copyWith(
        status: 'sending',
        wireEnvelope: envelope,
        directMediaCustodyIntentId: null,
      );

      final oldMedia = await fixture.repo.stageOutgoingOrdinaryAttemptWithMedia(
        messageMutationRepository:
            fixture.messageRepo as OutgoingTransportMutationRepository,
        expected: expected,
        staged: staged,
        attachments: <MediaAttachment>[completed],
        kind: OutgoingOrdinaryAttemptKind.existing,
      );
      expect(oldMedia.outcome, OutgoingOrdinaryMutationOutcome.refused);

      final malformedEditEnvelope = jsonEncode(<String, Object?>{
        ...jsonDecode(envelope) as Map<String, dynamic>,
        'eventId': 'edit-event',
      });
      final malformed = await fixture.repo.stageOutgoingDirectMediaInboxCustody(
        expected: expected,
        staged: staged.copyWith(wireEnvelope: malformedEditEnvelope),
        attachments: <MediaAttachment>[completed],
        kind: OutgoingOrdinaryAttemptKind.existing,
        recipientPeerId: expected.contactPeerId,
        wireEnvelope: malformedEditEnvelope,
      );
      expect(malformed.outcome, OutgoingOrdinaryMutationOutcome.refused);
      expect(
        (await fixture.messageRepo.getMessage(
          messageId,
        ))!.directMediaCustodyIntentId,
        intent,
      );
      expect(
        (await rawRow(attachmentId))!['download_status'],
        'upload_pending',
      );
      expect(
        await fixture.db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
        ),
        isEmpty,
      );
    });

    test(
      'all public row writers queue behind exact lifecycle qualification',
      () async {
        final lock = MediaAttachmentLifecycleLock();
        await fixture.dispose();
        fixture = await MediaRepositoryRealDbFixture.create(
          lifecycleLock: lock,
        );

        Future<void> expectQueued<T>({
          required String attachmentId,
          required Future<T> Function() mutate,
          required Future<void> Function() whileHeld,
          required Future<void> Function(T result) afterRelease,
        }) async {
          final entered = Completer<void>();
          final release = Completer<void>();
          final holder = lock.synchronized(attachmentId, () async {
            entered.complete();
            await release.future;
          });
          await entered.future;

          var completed = false;
          final mutation = mutate().whenComplete(() => completed = true);
          await Future<void>.delayed(Duration.zero);
          await whileHeld();
          expect(completed, isFalse);

          release.complete();
          await holder;
          final result = await mutation;
          expect(completed, isTrue);
          await afterRelease(result);
        }

        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'queued-direct',
            messageId: 'queued-direct-parent',
            size: 100,
          ),
          owner: MediaOwnerLane.direct,
        );

        await expectQueued<void>(
          attachmentId: 'queued-direct',
          mutate: () => fixture.repo.updateLocalPath(
            'queued-direct',
            'media/direct/queued-direct.jpg',
          ),
          whileHeld: () async {
            expect((await rawRow('queued-direct'))!['local_path'], isNull);
          },
          afterRelease: (_) async {
            final row = await rawRow('queued-direct');
            expect(row!['local_path'], 'media/direct/queued-direct.jpg');
            expect(row['download_status'], 'done');
          },
        );

        await expectQueued<void>(
          attachmentId: 'queued-direct',
          mutate: () =>
              fixture.repo.updateDownloadStatus('queued-direct', 'failed'),
          whileHeld: () async {
            expect((await rawRow('queued-direct'))!['download_status'], 'done');
          },
          afterRelease: (_) async {
            expect(
              (await rawRow('queued-direct'))!['download_status'],
              'failed',
            );
          },
        );

        await expectQueued<void>(
          attachmentId: 'queued-direct',
          mutate: () => fixture.repo.saveAttachment(
            makeAttachment(
              id: 'queued-direct',
              messageId: 'queued-direct-parent',
              size: 999,
              downloadStatus: 'done',
            ),
            owner: MediaOwnerLane.direct,
          ),
          whileHeld: () async {
            expect((await rawRow('queued-direct'))!['size'], 100);
          },
          afterRelease: (_) async {
            expect((await rawRow('queued-direct'))!['size'], 999);
          },
        );

        await expectQueued<int>(
          attachmentId: 'queued-direct',
          mutate: () => fixture.repo.deleteAttachmentsForMessage(
            'queued-direct-parent',
            owner: MediaOwnerLane.direct,
          ),
          whileHeld: () async {
            expect(await rawRow('queued-direct'), isNotNull);
          },
          afterRelease: (deleted) async {
            expect(deleted, 1);
            expect(await rawRow('queued-direct'), isNull);
          },
        );

        await fixture.repo.saveAttachment(
          makeAttachment(id: 'queued-group', messageId: 'queued-group-parent'),
          owner: MediaOwnerLane.group,
        );
        await expectQueued<void>(
          attachmentId: 'queued-group',
          mutate: () =>
              fixture.repo.updateDownloadStatus('queued-group', 'failed'),
          whileHeld: () async {
            expect(
              (await rawRow('queued-group'))!['download_status'],
              'pending',
            );
          },
          afterRelease: (_) async {
            expect(
              (await rawRow('queued-group'))!['download_status'],
              'failed',
            );
          },
        );
      },
    );

    test(
      'authorization stream emits exact path status eviction and delete mutations',
      () async {
        final changes = <MediaAttachmentAuthorizationChange>[];
        final subscription = fixture.repo.authorizationChanges.listen(
          changes.add,
        );
        addTearDown(subscription.cancel);
        await saveDirect(
          makeAttachment(
            id: 'pip-attachment',
            messageId: 'pip-parent',
            mediaType: 'video',
            mime: 'video/mp4',
            downloadStatus: 'done',
            localPath: 'media/direct/pip-attachment.mp4',
          ),
        );
        changes.clear();

        await fixture.repo.updateLocalPath(
          'pip-attachment',
          'media/direct/pip-attachment-v2.mp4',
        );
        await fixture.repo.updateDownloadStatus('pip-attachment', 'failed');
        await fixture.repo.updateDownloadStatus('pip-attachment', 'done');
        expect(
          await fixture.repo.claimMediaEvicted(
            'pip-attachment',
            owner: MediaOwnerLane.direct,
            expectedLocalPath: 'media/direct/pip-attachment-v2.mp4',
          ),
          1,
        );
        expect(
          await fixture.repo.deleteAttachmentsForMessage(
            'pip-parent',
            owner: MediaOwnerLane.direct,
          ),
          1,
        );

        expect(
          changes.map((change) => change.kind),
          <MediaAttachmentAuthorizationMutation>[
            MediaAttachmentAuthorizationMutation.localPathChanged,
            MediaAttachmentAuthorizationMutation.downloadStatusChanged,
            MediaAttachmentAuthorizationMutation.downloadStatusChanged,
            MediaAttachmentAuthorizationMutation.evicted,
            MediaAttachmentAuthorizationMutation.removed,
          ],
        );
        for (final change in changes) {
          expect(change.owner, MediaOwnerLane.direct);
          expect(change.messageId, 'pip-parent');
          expect(change.attachmentId, 'pip-attachment');
        }
      },
    );

    test('saveAttachment persists to store', () async {
      await saveDirect(makeAttachment());

      final row = await rawRow('blob-001');
      expect(row, isNotNull);
      expect(row!['mime'], 'image/jpeg');
      expect(row['message_id'], 'msg-001');
      expect(row['size'], 245000);
      expect(row['owner_lane'], 'direct');
    });

    test(
      'ordinary new direct upload rows bypass private pending preparation',
      () async {
        await saveDirect(
          makeAttachment(
            id: 'ordinary-source-upload',
            messageId: 'ordinary-source-parent',
            downloadStatus: 'upload_pending',
            localPath: '/tmp/ordinary-source.jpg',
          ),
        );

        final row = await rawRow('ordinary-source-upload');
        expect(row, isNotNull);
        expect(row!['download_status'], 'upload_pending');
        expect(row['local_path'], '/tmp/ordinary-source.jpg');
        expect(row['owner_lane'], MediaOwnerLane.direct.dbValue);

        await saveDirect(
          makeAttachment(
            id: 'ordinary-source-upload',
            messageId: 'ordinary-source-parent',
            downloadStatus: 'upload_failed',
            localPath: '/tmp/ordinary-source.jpg',
          ),
        );
        expect(
          (await rawRow('ordinary-source-upload'))!['download_status'],
          'upload_failed',
        );
      },
    );

    test('saveAttachment updates transport metadata in place', () async {
      await saveDirect(makeAttachment(downloadStatus: 'pending'));
      await saveDirect(makeAttachment(downloadStatus: 'done'));

      expect((await fixture.db.query('media_attachments')).length, 1);
      expect((await rawRow('blob-001'))!['download_status'], 'done');
    });

    test(
      'ordinary pending direct replay may correct media type and rotate key',
      () async {
        const id = 'ordinary-direct-correction';
        await saveDirect(
          makeAttachment(
            id: id,
            mime: 'image/jpeg',
            mediaType: 'image',
            encryptionKeyBase64: 'b2xkLWtleQ==',
            encryptionNonce: 'b2xkLW5vbmNl',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: id,
            mime: 'video/mp4',
            mediaType: 'video',
            width: null,
            height: null,
            durationMs: 900,
            encryptionKeyBase64: 'bmV3LWtleQ==',
            encryptionNonce: 'bmV3LW5vbmNl',
          ),
        );

        final row = await rawRow(id);
        expect(row!['mime'], 'video/mp4');
        expect(row['media_type'], 'video');
        expect(row['duration_ms'], 900);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(id),
          ),
          'bmV3LWtleQ==',
        );
      },
    );

    test(
      'saveAttachment preserves a completed local path from stale pending saves',
      () async {
        await saveDirect(makeAttachment(downloadStatus: 'pending'));
        await fixture.repo.updateLocalPath(
          'blob-001',
          'media/peer/blob-001.jpg',
        );

        await saveDirect(makeAttachment(downloadStatus: 'pending'));

        final row = await rawRow('blob-001');
        expect(row!['local_path'], 'media/peer/blob-001.jpg');
        expect(row['download_status'], 'done');
      },
    );

    test(
      'saveAttachment preserves completed media state over stale upload pending saves',
      () async {
        await saveDirect(
          makeAttachment(
            downloadStatus: 'done',
            localPath: 'media/peer/blob-001.jpg',
          ),
        );

        await saveDirect(
          makeAttachment(
            downloadStatus: 'upload_pending',
            localPath: 'pending_uploads/msg-001/blob-001.jpg',
          ),
        );

        final row = await rawRow('blob-001');
        expect(row!['local_path'], 'media/peer/blob-001.jpg');
        expect(row['download_status'], 'done');
      },
    );

    test(
      'saveAttachment still allows terminal failure to clear a completed path',
      () async {
        await saveDirect(
          makeAttachment(
            downloadStatus: 'done',
            localPath: 'media/peer/blob-001.jpg',
          ),
        );

        await saveDirect(makeAttachment(downloadStatus: 'failed'));

        final row = await rawRow('blob-001');
        expect(row!['local_path'], isNull);
        expect(row['download_status'], 'failed');
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING saveAttachment stores media key in secure storage and only a reference in SQL',
      () async {
        await saveDirect(
          makeAttachment(
            encryptionKeyBase64: 'plain-media-key-base64',
            encryptionNonce: 'nonce-base64',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final rawKey =
            (await rawRow('blob-001'))!['encryption_key_base64'] as String?;
        expect(rawKey, isNot('plain-media-key-base64'));
        expect(isSecureStoreReference(rawKey), isTrue);
        expect(
          rawKey,
          secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName('blob-001'),
          ),
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName('blob-001'),
          ),
          'plain-media-key-base64',
        );
      },
    );

    test(
      'failed attachment DB save compensates a new key and restores a pre-existing key',
      () async {
        await fixture.dispose();
        fixture = await MediaRepositoryRealDbFixture.create(
          dbSaveMediaAttachmentOverride: (_) async {
            throw StateError('injected DB save failure');
          },
        );

        const newId = 'blob-failed-new-key';
        await expectLater(
          fixture.repo.saveAttachment(
            makeAttachment(
              id: newId,
              encryptionKeyBase64: 'new-key-value',
              encryptionNonce: 'nonce-new',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          ),
          throwsStateError,
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(newId),
          ),
          isFalse,
        );

        const existingId = 'blob-failed-existing-key';
        final existingKeyName = mediaAttachmentEncryptionKeyStoreName(
          existingId,
        );
        await fixture.secureKeyStore.write(existingKeyName, 'original-key');
        await expectLater(
          fixture.repo.saveAttachment(
            makeAttachment(
              id: existingId,
              encryptionKeyBase64: 'replacement-key',
              encryptionNonce: 'nonce-existing',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          ),
          throwsStateError,
        );
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'original-key',
        );
      },
    );

    test(
      'secure-key snapshot failures leave the existing row and key untouched',
      () async {
        for (final failure in const ['contains', 'read']) {
          await fixture.dispose();
          final secureStore = _FailingSnapshotSecureKeyStore();
          fixture = await MediaRepositoryRealDbFixture.create(
            secureKeyStore: secureStore,
          );
          final id = 'snapshot-failure-$failure';
          final keyName = mediaAttachmentEncryptionKeyStoreName(id);
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: id,
              mime: 'image/jpeg',
              encryptionKeyBase64: 'original-key-$failure',
              encryptionNonce: 'original-nonce-$failure',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          );
          final originalRow = Map<String, Object?>.from((await rawRow(id))!);
          secureStore.failContains = failure == 'contains';
          secureStore.failRead = failure == 'read';

          await expectLater(
            fixture.repo.saveAttachment(
              makeAttachment(
                id: id,
                mime: 'image/png',
                encryptionKeyBase64: 'replacement-key-$failure',
                encryptionNonce: 'replacement-nonce-$failure',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ),
              owner: MediaOwnerLane.group,
            ),
            throwsStateError,
          );

          secureStore.failContains = false;
          secureStore.failRead = false;
          expect(await rawRow(id), originalRow);
          expect(await secureStore.read(keyName), 'original-key-$failure');
        }
      },
    );

    test(
      'guarded group save restores replaced keys on refusal and every throw',
      () async {
        await fixture.dispose();
        var guardThrows = false;
        fixture = await MediaRepositoryRealDbFixture.create(
          dbSaveGroupMediaAttachmentGuardedOverride:
              (row, {required groupId}) async {
                if (guardThrows) {
                  throw StateError('injected guarded group save failure');
                }
                return false;
              },
        );

        Future<bool> guardedSave(String id, String key) =>
            fixture.repo.saveGroupAttachmentGuarded(
              makeAttachment(
                id: id,
                messageId: 'guarded-group-parent',
                encryptionKeyBase64: key,
                encryptionNonce: 'guarded-group-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ),
              groupId: 'guarded-group',
            );

        const existingId = 'guarded-group-existing-key';
        final existingKeyName = mediaAttachmentEncryptionKeyStoreName(
          existingId,
        );
        await fixture.secureKeyStore.write(existingKeyName, 'original-key');
        expect(await guardedSave(existingId, 'replacement-on-false'), isFalse);
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'original-key',
        );
        expect(await rawRow(existingId), isNull);

        guardThrows = true;
        await expectLater(
          guardedSave(existingId, 'replacement-on-throw'),
          throwsStateError,
        );
        expect(
          await fixture.secureKeyStore.read(existingKeyName),
          'original-key',
        );
        expect(await rawRow(existingId), isNull);

        const newId = 'guarded-group-new-key';
        final newKeyName = mediaAttachmentEncryptionKeyStoreName(newId);
        await expectLater(
          guardedSave(newId, 'new-key-on-throw'),
          throwsStateError,
        );
        expect(await fixture.secureKeyStore.containsKey(newKeyName), isFalse);
        expect(await rawRow(newId), isNull);
      },
    );

    test(
      'exact group upload completion stores only a secure reference and compensates CAS refusal',
      () async {
        Future<({Map<String, Object?> parent, MediaAttachment attachment})>
        seedPending(String suffix) async {
          final messageId = 'group-upload-$suffix';
          final attachmentId = 'group-upload-attachment-$suffix';
          await fixture.seedGroupParent(messageId);
          await fixture.db.update(
            'group_messages',
            {'status': 'failed', 'is_incoming': 0},
            where: 'id = ?',
            whereArgs: [messageId],
          );
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: attachmentId,
              messageId: messageId,
              localPath: 'pending_uploads/$attachmentId.jpg',
              downloadStatus: 'upload_pending',
            ),
            owner: MediaOwnerLane.group,
          );
          final parent = (await fixture.db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: [messageId],
          )).single;
          final attachment = (await fixture.repo.getAttachmentById(
            attachmentId,
          ))!;
          return (parent: parent, attachment: attachment);
        }

        final success = await seedPending('success');
        const rawKey = 'raw-group-upload-key';
        final completed = success.attachment.copyWith(
          downloadStatus: 'done',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: rawKey,
          encryptionNonce: 'group-upload-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(
          await fixture.repo.completeGroupUploadRetrySecurely(
            expectedParent: success.parent,
            expectedAttachment: success.attachment,
            completedAttachment: completed,
          ),
          isTrue,
        );
        final keyName = mediaAttachmentEncryptionKeyStoreName(completed.id);
        expect(await fixture.secureKeyStore.read(keyName), rawKey);
        expect(
          (await rawRow(completed.id))!['encryption_key_base64'],
          secureStoreReferenceForKey(keyName),
        );
        expect(
          (await rawRow(completed.id))!['encryption_key_base64'],
          isNot(rawKey),
        );

        final refused = await seedPending('refused');
        await fixture.db.update(
          'group_messages',
          {'status': 'send_failed'},
          where: 'id = ?',
          whereArgs: [refused.parent['id']],
        );
        final refusedCompletion = refused.attachment.copyWith(
          downloadStatus: 'done',
          contentHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          encryptionKeyBase64: 'refused-raw-key',
          encryptionNonce: 'refused-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(
          await fixture.repo.completeGroupUploadRetrySecurely(
            expectedParent: refused.parent,
            expectedAttachment: refused.attachment,
            completedAttachment: refusedCompletion,
          ),
          isFalse,
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(refusedCompletion.id),
          ),
          isFalse,
        );
        expect(
          (await rawRow(refusedCompletion.id))!['download_status'],
          'upload_pending',
        );
      },
    );

    test(
      'P269 exact group upload completion accepts omitted counters without SQL null',
      () async {
        const messageId = 'p269-omitted-counter-parent';
        const attachmentId = 'p269-omitted-counter-attachment';
        await fixture.seedGroupParent(messageId);
        await fixture.db.update(
          'group_messages',
          {'status': 'failed', 'is_incoming': 0},
          where: 'id = ?',
          whereArgs: [messageId],
        );
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: attachmentId,
            messageId: messageId,
            size: 111,
            localPath: 'pending_uploads/$attachmentId.jpg',
            downloadStatus: 'upload_pending',
          ),
          owner: MediaOwnerLane.group,
        );

        final expectedParent = (await fixture.db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: [messageId],
        )).single;
        final expectedAttachment = (await fixture.repo.getAttachmentById(
          attachmentId,
        ))!;
        expect(expectedAttachment.uploadRetryCount, 0);
        expect(expectedAttachment.downloadRetryCount, 0);

        // A successful upload outcome does not own either local retry counter,
        // so its model legitimately omits both keys from toMap().
        final completedAttachment = MediaAttachment(
          id: expectedAttachment.id,
          messageId: expectedAttachment.messageId,
          mime: expectedAttachment.mime,
          size: 222,
          mediaType: expectedAttachment.mediaType,
          width: expectedAttachment.width,
          height: expectedAttachment.height,
          durationMs: expectedAttachment.durationMs,
          localPath: 'media/groups/$attachmentId.jpg',
          downloadStatus: 'done',
          createdAt: expectedAttachment.createdAt,
          waveform: expectedAttachment.waveform,
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          thumbnailHash: expectedAttachment.thumbnailHash,
          encryptionKeyBase64: 'p269-omitted-counter-raw-key',
          encryptionNonce: 'p269-omitted-counter-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        );
        final completedRow = completedAttachment.toMap();
        for (final column in _retryCounterColumns) {
          expect(completedRow, isNot(contains(column)));
        }

        expect(
          await fixture.repo.completeGroupUploadRetrySecurely(
            expectedParent: expectedParent,
            expectedAttachment: expectedAttachment,
            completedAttachment: completedAttachment,
          ),
          isTrue,
        );

        final row = (await rawRow(attachmentId))!;
        expect(row['download_status'], 'done');
        expect(row['upload_retry_count'], 0);
        expect(row['download_retry_count'], 0);
        expect(
          row['encryption_key_base64'],
          secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
        );
        expect(
          row['encryption_key_base64'],
          isNot('p269-omitted-counter-raw-key'),
        );
      },
    );

    test(
      'P269 exact group upload completion preserves local authority and accepts upload owned fields',
      () async {
        const messageId = 'p269-field-owner-parent';
        const attachmentId = 'p269-field-owner-attachment';
        const localCreatedAt = '2026-07-22T08:00:00.000Z';
        const uploadCreatedAt = '2036-01-02T03:04:05.000Z';
        const localThumbnailHash =
            '1111111111111111111111111111111111111111111111111111111111111111';
        const uploadThumbnailHash =
            '2222222222222222222222222222222222222222222222222222222222222222';
        const uploadContentHash =
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
        const rawKey = 'p269-field-owner-raw-key';
        const uploadNonce = 'p269-field-owner-nonce';

        await fixture.seedGroupParent(messageId);
        await fixture.db.update(
          'group_messages',
          {'status': 'failed', 'is_incoming': 0},
          where: 'id = ?',
          whereArgs: [messageId],
        );
        await fixture.repo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 111,
            mediaType: 'image',
            width: 320,
            height: 240,
            durationMs: 1000,
            localPath: 'pending_uploads/$attachmentId.jpg',
            downloadStatus: 'upload_pending',
            createdAt: localCreatedAt,
            waveform: const [0.1, 0.2],
            uploadRetryCount: 2,
            downloadRetryCount: 3,
            thumbnailHash: localThumbnailHash,
          ),
          owner: MediaOwnerLane.group,
        );

        final expectedParent = (await fixture.db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: [messageId],
        )).single;
        final expectedAttachment = (await fixture.repo.getAttachmentById(
          attachmentId,
        ))!;
        final completedAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/heic',
          size: 987654,
          mediaType: 'image',
          width: 1440,
          height: 1080,
          durationMs: 6543,
          localPath: 'media/groups/$attachmentId.heic',
          downloadStatus: 'done',
          createdAt: uploadCreatedAt,
          waveform: const [0.9, 0.4],
          uploadRetryCount: 91,
          downloadRetryCount: 92,
          contentHash: uploadContentHash,
          thumbnailHash: uploadThumbnailHash,
          encryptionKeyBase64: rawKey,
          encryptionNonce: uploadNonce,
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        );

        expect(
          await fixture.repo.completeGroupUploadRetrySecurely(
            expectedParent: expectedParent,
            expectedAttachment: expectedAttachment,
            completedAttachment: completedAttachment,
          ),
          isTrue,
        );

        final row = (await rawRow(attachmentId))!;
        // Local authority comes from the exact pending row.
        expect(row['created_at'], localCreatedAt);
        expect(row['thumbnail_hash'], localThumbnailHash);
        expect(row['upload_retry_count'], 2);
        expect(row['download_retry_count'], 3);

        // Upload-owned normalization remains accepted rather than freezing the
        // entire pre-upload row.
        expect(row['mime'], 'image/heic');
        expect(row['size'], 987654);
        expect(row['media_type'], 'image');
        expect(row['width'], 1440);
        expect(row['height'], 1080);
        expect(row['duration_ms'], 6543);
        expect(row['local_path'], 'media/groups/$attachmentId.heic');
        expect(row['download_status'], 'done');
        expect(row['content_hash'], uploadContentHash);
        expect(row['encryption_nonce'], uploadNonce);
        expect(
          row['encryption_scheme'],
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        expect(await fixture.secureKeyStore.read(keyName), rawKey);
        expect(
          row['encryption_key_base64'],
          secureStoreReferenceForKey(keyName),
        );
        expect(row['encryption_key_base64'], isNot(rawKey));
        expect(
          (await fixture.repo.getAttachmentById(attachmentId))!.waveform,
          const [0.9, 0.4],
        );
      },
    );

    test(
      'P269 SQL default wrapper matches production schema for omitted and explicit null counters',
      () async {
        Map<String, Object?> row(String id) => makeAttachment(
          id: id,
          messageId: 'p269-wrapper-parent',
          localPath: 'pending_uploads/$id.jpg',
          downloadStatus: 'upload_pending',
        ).copyWith(ownerLane: MediaOwnerLane.group).toMap();

        final omitted = row('p269-wrapper-omitted');
        for (final column in _retryCounterColumns) {
          expect(omitted, isNot(contains(column)));
        }
        final wrappedOmitted = _applyProductionRetryCounterDefaults(omitted);
        await fixture.db.insert('media_attachments', omitted);
        final productionOmitted = (await rawRow('p269-wrapper-omitted'))!;
        for (final column in _retryCounterColumns) {
          expect(wrappedOmitted[column], 0);
          expect(productionOmitted[column], wrappedOmitted[column]);
        }

        for (final column in _retryCounterColumns) {
          final id = 'p269-wrapper-explicit-null-$column';
          final explicitNull = <String, Object?>{...row(id), column: null};
          expect(
            () => _applyProductionRetryCounterDefaults(explicitNull),
            throwsArgumentError,
          );
          await expectLater(
            fixture.db.insert('media_attachments', explicitNull),
            throwsA(
              isA<DatabaseException>().having(
                (error) => error.toString(),
                'message',
                contains('media_attachments.$column'),
              ),
            ),
          );
          expect(await rawRow(id), isNull);
        }
      },
    );

    test(
      'new-message rollback removes exact group rows and secure keys only',
      () async {
        for (final id in const ['rollback-a', 'rollback-b']) {
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: id,
              messageId: 'new-group-message',
              encryptionKeyBase64: 'key-$id',
              encryptionNonce: 'nonce-$id',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          );
        }
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'preserved-sibling',
            messageId: 'other-group-message',
            encryptionKeyBase64: 'key-preserved',
            encryptionNonce: 'nonce-preserved',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.group,
        );

        final deleted = await fixture.repo.rollbackNewMessageAttachments(
          messageId: 'new-group-message',
          attachmentIds: const {
            'rollback-a',
            'rollback-b',
            'preserved-sibling',
          },
          owner: MediaOwnerLane.group,
        );

        expect(deleted, 2);
        expect(await rawRow('rollback-a'), isNull);
        expect(await rawRow('rollback-b'), isNull);
        expect(await rawRow('preserved-sibling'), isNotNull);
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('rollback-a'),
          ),
          isFalse,
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName('rollback-b'),
          ),
          isFalse,
        );
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName('preserved-sibling'),
          ),
          'key-preserved',
        );
      },
    );

    test(
      'new-message rollback retries a transient secure-key delete failure',
      () async {
        await fixture.dispose();
        final secureStore = _FailFirstDeleteSecureKeyStore();
        fixture = await MediaRepositoryRealDbFixture.create(
          secureKeyStore: secureStore,
        );
        const attachmentId = 'rollback-delete-retry';
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: attachmentId,
            messageId: 'rollback-delete-message',
            encryptionKeyBase64: 'rollback-delete-key',
            encryptionNonce: 'rollback-delete-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.group,
        );
        secureStore.failOnceFor = keyName;

        final deleted = await fixture.repo.rollbackNewMessageAttachments(
          messageId: 'rollback-delete-message',
          attachmentIds: const {attachmentId},
          owner: MediaOwnerLane.group,
        );

        expect(deleted, 1);
        expect(await rawRow(attachmentId), isNull);
        expect(await secureStore.containsKey(keyName), isFalse);
      },
    );

    test(
      'empty new-message rollback excludes a concurrent attachment insertion',
      () async {
        await fixture.dispose();
        final loadEntered = Completer<void>();
        final releaseLoad = Completer<void>();
        fixture = await MediaRepositoryRealDbFixture.create(
          dbLoadMediaForMessageAround: (messageId, ownerLane, load) async {
            if (messageId == 'rollback-insertion-race') {
              loadEntered.complete();
              await releaseLoad.future;
            }
            return load();
          },
        );

        final rollback = fixture.repo.rollbackNewMessageAttachments(
          messageId: 'rollback-insertion-race',
          attachmentIds: const <String>{},
          owner: MediaOwnerLane.group,
        );
        await loadEntered.future;

        var insertionCompleted = false;
        final insertion = fixture.repo
            .saveAttachment(
              makeAttachment(
                id: 'concurrent-insertion',
                messageId: 'rollback-insertion-race',
                encryptionKeyBase64: 'concurrent-key',
                encryptionNonce: 'concurrent-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              ),
              owner: MediaOwnerLane.group,
            )
            .whenComplete(() => insertionCompleted = true);
        await Future<void>.delayed(Duration.zero);
        expect(
          insertionCompleted,
          isFalse,
          reason:
              'the insertion must queue behind rollback exclusive authority',
        );
        expect(await rawRow('concurrent-insertion'), isNull);

        releaseLoad.complete();
        expect(await rollback, 0);
        await insertion;
        expect(insertionCompleted, isTrue);
        expect(await rawRow('concurrent-insertion'), isNotNull);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName('concurrent-insertion'),
          ),
          'concurrent-key',
        );
      },
    );

    test(
      'same-id failed and succeeding saves serialize key compensation',
      () async {
        await fixture.dispose();
        final firstReplacementEnteredDb = Completer<void>();
        final releaseFirstReplacement = Completer<void>();
        var dbSaveCount = 0;
        fixture = await MediaRepositoryRealDbFixture.create(
          dbSaveMediaAttachmentAround: (row, persist) async {
            dbSaveCount++;
            if (dbSaveCount == 2) {
              firstReplacementEnteredDb.complete();
              await releaseFirstReplacement.future;
              throw StateError('injected late first-save DB failure');
            }
            await persist();
          },
        );
        const attachmentId = 'serialized-key-compensation';
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        await saveDirect(
          makeAttachment(
            id: attachmentId,
            encryptionKeyBase64: 'base-key',
            encryptionNonce: 'base-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final failedSave = saveDirect(
          makeAttachment(
            id: attachmentId,
            encryptionKeyBase64: 'first-replacement-key',
            encryptionNonce: 'first-replacement-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );
        await firstReplacementEnteredDb.future;
        final succeedingSave = saveDirect(
          makeAttachment(
            id: attachmentId,
            encryptionKeyBase64: 'second-replacement-key',
            encryptionNonce: 'second-replacement-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          dbSaveCount,
          2,
          reason: 'the second save must wait on the ID lock',
        );

        releaseFirstReplacement.complete();
        await expectLater(failedSave, throwsStateError);
        await succeedingSave;

        expect(
          await fixture.secureKeyStore.read(keyName),
          'second-replacement-key',
        );
        final hydrated = await fixture.repo.getAttachmentById(attachmentId);
        expect(hydrated?.encryptionKeyBase64, 'second-replacement-key');
        expect(hydrated?.encryptionNonce, 'second-replacement-nonce');
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessage hydrates media key from secure storage',
      () async {
        await saveDirect(
          makeAttachment(
            encryptionKeyBase64: 'message-media-key-base64',
            encryptionNonce: 'nonce-base64',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final result = await fixture.repo.getAttachmentsForMessage(
          'msg-001',
          owner: MediaOwnerLane.direct,
        );

        expect(result.single.encryptionKeyBase64, 'message-media-key-base64');
        expect(
          (await rawRow('blob-001'))!['encryption_key_base64'],
          isNot('message-media-key-base64'),
        );
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessages hydrates secure media keys',
      () async {
        await saveDirect(
          makeAttachment(
            id: 'blob-A',
            messageId: 'msg-A',
            encryptionKeyBase64: 'media-key-A',
            encryptionNonce: 'nonce-A',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-B',
            messageId: 'msg-B',
            encryptionKeyBase64: 'media-key-B',
            encryptionNonce: 'nonce-B',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );

        final result = await fixture.repo.getAttachmentsForMessages([
          'msg-A',
          'msg-B',
        ], owner: MediaOwnerLane.direct);

        expect(result['msg-A']!.single.encryptionKeyBase64, 'media-key-A');
        expect(result['msg-B']!.single.encryptionKeyBase64, 'media-key-B');
        expect(
          isSecureStoreReference(
            (await rawRow('blob-A'))!['encryption_key_base64'] as String?,
          ),
          isTrue,
        );
        expect(
          isSecureStoreReference(
            (await rawRow('blob-B'))!['encryption_key_base64'] as String?,
          ),
          isTrue,
        );
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessage clears missing secure media key reference',
      () async {
        final secureStoreKey = mediaAttachmentEncryptionKeyStoreName(
          'blob-missing',
        );
        final row = makeAttachment(
          id: 'blob-missing',
          encryptionKeyBase64: secureStoreReferenceForKey(secureStoreKey),
          encryptionNonce: 'nonce-missing',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ).toMap();
        row['owner_lane'] = 'direct';
        await fixture.db.insert('media_attachments', row);

        final result = await fixture.repo.getAttachmentsForMessage(
          'msg-001',
          owner: MediaOwnerLane.direct,
        );

        expect(result.single.encryptionKeyBase64, isNull);
        expect(
          isSecureStoreReference(result.single.encryptionKeyBase64),
          false,
        );
        expect(result.single.hasEncryptionMetadata, isFalse);
      },
    );

    test(
      'PREREQ-SECRET-STORAGE-WRAPPING getAttachmentsForMessages clears missing secure media key references',
      () async {
        final keyA = mediaAttachmentEncryptionKeyStoreName('blob-missing-A');
        final keyB = mediaAttachmentEncryptionKeyStoreName('blob-missing-B');
        final rowA = makeAttachment(
          id: 'blob-missing-A',
          messageId: 'msg-A',
          encryptionKeyBase64: secureStoreReferenceForKey(keyA),
          encryptionNonce: 'nonce-A',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ).toMap();
        rowA['owner_lane'] = 'direct';
        await fixture.db.insert('media_attachments', rowA);
        final rowB = makeAttachment(
          id: 'blob-missing-B',
          messageId: 'msg-B',
          encryptionKeyBase64: secureStoreReferenceForKey(keyB),
          encryptionNonce: 'nonce-B',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ).toMap();
        rowB['owner_lane'] = 'direct';
        await fixture.db.insert('media_attachments', rowB);

        final result = await fixture.repo.getAttachmentsForMessages([
          'msg-A',
          'msg-B',
        ], owner: MediaOwnerLane.direct);

        expect(result['msg-A']!.single.encryptionKeyBase64, isNull);
        expect(result['msg-B']!.single.encryptionKeyBase64, isNull);
        expect(result['msg-A']!.single.hasEncryptionMetadata, isFalse);
        expect(result['msg-B']!.single.hasEncryptionMetadata, isFalse);
      },
    );

    test('getAttachmentsForMessage returns empty list when none', () async {
      final result = await fixture.repo.getAttachmentsForMessage(
        'nonexistent',
        owner: MediaOwnerLane.direct,
      );
      expect(result, isEmpty);
    });

    test('getAttachmentById returns failed attachment by blob id', () async {
      await saveDirect(
        makeAttachment(id: 'blob-failed', downloadStatus: 'failed'),
      );

      final result = await fixture.repo.getAttachmentById('blob-failed');

      expect(result, isNotNull);
      expect(result!.id, 'blob-failed');
      expect(result.downloadStatus, 'failed');
    });

    test('getAttachmentsForMessage returns matching attachments', () async {
      await saveDirect(
        makeAttachment(
          id: 'blob-1',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await saveDirect(
        makeAttachment(
          id: 'blob-2',
          messageId: 'msg-A',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await saveDirect(makeAttachment(id: 'blob-3', messageId: 'msg-B'));

      final result = await fixture.repo.getAttachmentsForMessage(
        'msg-A',
        owner: MediaOwnerLane.direct,
      );
      expect(result.length, 2);
      expect(result[0].id, 'blob-1');
      expect(result[1].id, 'blob-2');
    });

    test('getAttachmentsForMessage returns MediaAttachment objects', () async {
      await saveDirect(
        makeAttachment(
          id: 'blob-typed',
          mime: 'video/mp4',
          size: 5000000,
          mediaType: 'video',
          width: 1280,
          height: 720,
        ),
      );

      final result = await fixture.repo.getAttachmentsForMessage(
        'msg-001',
        owner: MediaOwnerLane.direct,
      );
      expect(result.length, 1);
      expect(result[0], isA<MediaAttachment>());
      expect(result[0].mime, 'video/mp4');
      expect(result[0].size, 5000000);
      expect(result[0].width, 1280);
    });

    group('getAttachmentsForMessages', () {
      test('returns empty map for empty messageIds', () async {
        final result = await fixture.repo.getAttachmentsForMessages(
          [],
          owner: MediaOwnerLane.direct,
        );
        expect(result, isEmpty);
      });

      test('groups attachments by messageId', () async {
        await saveDirect(
          makeAttachment(
            id: 'blob-1',
            messageId: 'msg-A',
            createdAt: '2026-02-20T10:00:00.000Z',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-2',
            messageId: 'msg-A',
            createdAt: '2026-02-20T10:01:00.000Z',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-3',
            messageId: 'msg-B',
            createdAt: '2026-02-20T10:02:00.000Z',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-4',
            messageId: 'msg-C',
            createdAt: '2026-02-20T10:03:00.000Z',
          ),
        );

        final result = await fixture.repo.getAttachmentsForMessages([
          'msg-A',
          'msg-B',
        ], owner: MediaOwnerLane.direct);

        expect(result.length, 2);
        expect(result['msg-A']!.length, 2);
        expect(result['msg-A']![0].id, 'blob-1');
        expect(result['msg-A']![1].id, 'blob-2');
        expect(result['msg-B']!.length, 1);
        expect(result['msg-B']![0].id, 'blob-3');
        // msg-C not requested, should not appear
        expect(result.containsKey('msg-C'), isFalse);
      });

      test('returns empty map when no matches', () async {
        await saveDirect(makeAttachment(id: 'blob-1', messageId: 'msg-X'));

        final result = await fixture.repo.getAttachmentsForMessages([
          'msg-A',
          'msg-B',
        ], owner: MediaOwnerLane.direct);
        expect(result, isEmpty);
      });
    });

    test('updateLocalPath updates path and sets status to done', () async {
      await saveDirect(makeAttachment(downloadStatus: 'downloading'));

      await fixture.repo.updateLocalPath('blob-001', '/path/to/file.jpg');

      final row = await rawRow('blob-001');
      expect(row!['local_path'], '/path/to/file.jpg');
      expect(row['download_status'], 'done');
    });

    test('updateDownloadStatus changes status', () async {
      await saveDirect(makeAttachment(downloadStatus: 'pending'));

      await fixture.repo.updateDownloadStatus('blob-001', 'downloading');
      expect((await rawRow('blob-001'))!['download_status'], 'downloading');

      await fixture.repo.updateDownloadStatus('blob-001', 'failed');
      expect((await rawRow('blob-001'))!['download_status'], 'failed');
    });

    test('deleteAttachmentsForMessage removes matching rows', () async {
      await saveDirect(makeAttachment(id: 'blob-1', messageId: 'msg-A'));
      await saveDirect(makeAttachment(id: 'blob-2', messageId: 'msg-A'));
      await saveDirect(makeAttachment(id: 'blob-3', messageId: 'msg-B'));

      final count = await fixture.repo.deleteAttachmentsForMessage(
        'msg-A',
        owner: MediaOwnerLane.direct,
      );
      expect(count, 2);
      final remaining = await fixture.db.query('media_attachments');
      expect(remaining.length, 1);
      expect(remaining.single['id'], 'blob-3');
    });

    test('deleteAttachmentsForMessage returns 0 when no matches', () async {
      final count = await fixture.repo.deleteAttachmentsForMessage(
        'nonexistent',
        owner: MediaOwnerLane.direct,
      );
      expect(count, 0);
    });

    test(
      'markUploadPendingAttachmentsFailedForMessage only terminalizes pending rows for the target message',
      () async {
        await saveDirect(
          makeAttachment(
            id: 'blob-target-pending',
            messageId: 'msg-target',
            downloadStatus: 'upload_pending',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-target-done',
            messageId: 'msg-target',
            downloadStatus: 'done',
          ),
        );
        await saveDirect(
          makeAttachment(
            id: 'blob-other-pending',
            messageId: 'msg-other',
            downloadStatus: 'upload_pending',
          ),
        );

        final count = await fixture.repo
            .markUploadPendingAttachmentsFailedForMessage(
              'msg-target',
              owner: MediaOwnerLane.direct,
            );

        expect(count, 1);
        expect(
          (await rawRow('blob-target-pending'))!['download_status'],
          'upload_failed',
        );
        expect((await rawRow('blob-target-done'))!['download_status'], 'done');
        expect(
          (await rawRow('blob-other-pending'))!['download_status'],
          'upload_pending',
        );
      },
    );

    test('getPendingDownloads returns only pending attachments', () async {
      await saveDirect(
        makeAttachment(
          id: 'blob-1',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      );
      await saveDirect(
        makeAttachment(
          id: 'blob-2',
          downloadStatus: 'done',
          createdAt: '2026-02-20T10:01:00.000Z',
        ),
      );
      await saveDirect(
        makeAttachment(
          id: 'blob-3',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:02:00.000Z',
        ),
      );

      final pending = await fixture.repo.getPendingDownloads();
      expect(pending.length, 2);
      expect(pending[0].id, 'blob-1');
      expect(pending[1].id, 'blob-3');
    });

    test('getPendingDownloads returns empty list when none pending', () async {
      await saveDirect(makeAttachment(id: 'blob-1', downloadStatus: 'done'));

      final pending = await fixture.repo.getPendingDownloads();
      expect(pending, isEmpty);
    });

    // --- 228 TC-228-05B (repository slice) ---

    test(
      'owner scoped terminalization and pending limits isolate collision lanes',
      () async {
        await fixture.seedDirectParent('msg-shared');
        await fixture.seedGroupParent('msg-shared');

        // Same message id, one upload-pending attachment per lane.
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-d',
            messageId: 'msg-shared',
            downloadStatus: 'upload_pending',
            createdAt: '2026-02-20T10:00:00.000Z',
          ),
          owner: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-g',
            messageId: 'msg-shared',
            downloadStatus: 'upload_pending',
            createdAt: '2026-02-20T09:00:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        // Per-lane pending loads see only their own row.
        final directPending = await fixture.repo.getUploadPendingAttachments(
          owner: MediaOwnerLane.direct,
        );
        expect(directPending.map((a) => a.id), ['att-d']);
        final groupPending = await fixture.repo.getUploadPendingAttachments(
          owner: MediaOwnerLane.group,
        );
        expect(groupPending.map((a) => a.id), ['att-g']);

        // Direct terminalization leaves the group sibling untouched.
        final flipped = await fixture.repo
            .markUploadPendingAttachmentsFailedForMessage(
              'msg-shared',
              owner: MediaOwnerLane.direct,
            );
        expect(flipped, 1);
        expect((await rawRow('att-d'))!['download_status'], 'upload_failed');
        expect((await rawRow('att-g'))!['download_status'], 'upload_pending');
      },
    );

    // --- 228 TC-228-08 ---

    test('ordinary replay preserves local viewer state and path while explicit '
        'clears win', () async {
      await fixture.seedDirectParent('msg-shared');
      await fixture.seedGroupParent('msg-shared');

      Future<void> runLaneScenario({
        required MediaOwnerLane owner,
        required String id,
      }) async {
        // Completed video with viewer state.
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-shared',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 10000,
            downloadStatus: 'done',
            localPath: 'media/peer/$id.mp4',
          ),
          owner: owner,
        );
        await fixture.repo.setBookmarked(id, bookmarked: true);
        await fixture.repo.updatePlaybackPosition(id, 4000);

        // Ordinary transport replay: non-terminal status, no local path,
        // updated metadata (width).
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-shared',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 10000,
            width: 640,
            downloadStatus: 'pending',
          ),
          owner: owner,
        );

        final row = await rawRow(id);
        // Transport metadata updated...
        expect(row!['width'], 640);
        // ...but local viewer state and the completed path survive.
        expect(row['is_bookmarked'], 1);
        expect(row['last_playback_position_ms'], 4000);
        expect(row['local_path'], 'media/peer/$id.mp4');
        expect(row['download_status'], 'done');
        expect(row['owner_lane'], owner.dbValue);

        // Explicit clears win and do NOT get merged back by a replay.
        await fixture.repo.setBookmarked(id, bookmarked: false);
        await fixture.repo.updatePlaybackPosition(id, 0);
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-shared',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 10000,
            downloadStatus: 'pending',
          ),
          owner: owner,
        );
        final cleared = await rawRow(id);
        expect(cleared!['is_bookmarked'], 0);
        expect(cleared['last_playback_position_ms'], 0);
      }

      await runLaneScenario(owner: MediaOwnerLane.direct, id: 'att-d');
      await runLaneScenario(owner: MediaOwnerLane.group, id: 'att-g');
    });

    // --- 229 TC-229-12 ---

    test('ordinary replay preserves evicted and viewer state until explicit '
        'owner-aware retry', () async {
      await fixture.seedDirectParent('msg-evict');
      await fixture.seedGroupParent('msg-evict');

      // Collision fixture: both lanes carry attachments under the SAME
      // parent message id, plus a fail-closed unresolved legacy row.
      Future<void> seedEvictedLane(MediaOwnerLane owner, String id) async {
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-evict',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 9000,
            downloadStatus: 'done',
            localPath: 'media/peer/$id.mp4',
          ),
          owner: owner,
        );
        await fixture.repo.setBookmarked(id, bookmarked: true);
        await fixture.repo.updatePlaybackPosition(id, 3000);
        // The owner-aware eviction claim retains the path for deletion...
        expect(
          await fixture.repo.claimMediaEvicted(
            id,
            owner: owner,
            expectedLocalPath: 'media/peer/$id.mp4',
          ),
          1,
        );
        // ...and the post-delete finalize nulls it.
        expect(
          await fixture.repo.finalizeMediaEvictedPathCleared(id, owner: owner),
          1,
        );
      }

      await seedEvictedLane(MediaOwnerLane.direct, 'att-evict-d');
      await seedEvictedLane(MediaOwnerLane.group, 'att-evict-g');
      await fixture.db.insert('media_attachments', {
        'id': 'att-evict-u',
        'message_id': 'msg-evict',
        'mime': 'video/mp4',
        'size': 10,
        'media_type': 'video',
        'download_status': 'done',
        'local_path': 'media/peer/att-evict-u.mp4',
        'created_at': '2026-02-20T10:00:00.000Z',
        'owner_lane': 'unresolved',
      });

      // Ordinary wire replay (pending, no path, default local fields) in
      // BOTH lanes: transport metadata updates, but evicted status, null
      // path, owner, bookmark and playback all survive.
      for (final (owner, id) in [
        (MediaOwnerLane.direct, 'att-evict-d'),
        (MediaOwnerLane.group, 'att-evict-g'),
      ]) {
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: id,
            messageId: 'msg-evict',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 9000,
            width: 640,
            downloadStatus: 'pending',
          ),
          owner: owner,
        );
        final row = await rawRow(id);
        expect(
          row!['download_status'],
          'evicted',
          reason: '$owner replay must not re-arm an evicted row',
        );
        expect(row['local_path'], isNull);
        expect(row['is_bookmarked'], 1);
        expect(row['last_playback_position_ms'], 3000);
        expect(row['owner_lane'], owner.dbValue);
        expect(row['width'], 640);
      }

      // A blind `done` replay through the ordinary save path cannot
      // resurrect the local copy either.
      await fixture.repo.saveAttachment(
        makeAttachment(
          id: 'att-evict-d',
          messageId: 'msg-evict',
          mime: 'video/mp4',
          mediaType: 'video',
          durationMs: 9000,
          downloadStatus: 'done',
          localPath: 'media/peer/att-evict-d.mp4',
        ),
        owner: MediaOwnerLane.direct,
      );
      final blind = await rawRow('att-evict-d');
      expect(blind!['download_status'], 'evicted');
      expect(blind['local_path'], isNull);

      // The unresolved legacy row is untouched by every lane-scoped
      // operation above.
      final unresolved = await rawRow('att-evict-u');
      expect(unresolved!['download_status'], 'done');
      expect(unresolved['owner_lane'], 'unresolved');
      expect(unresolved['local_path'], 'media/peer/att-evict-u.mp4');

      // A cross-lane retry claim is a lost claim (0 rows), never a
      // mutation of the sibling.
      expect(
        await fixture.repo.beginMediaDownload(
          'att-evict-g',
          owner: MediaOwnerLane.direct,
        ),
        isFalse,
      );
      expect((await rawRow('att-evict-g'))!['download_status'], 'evicted');

      // The explicit matching-owner retry transitions ONLY its row, and
      // the CAS commit from that claim settles done with the fresh path.
      expect(
        await fixture.repo.beginMediaDownload(
          'att-evict-d',
          owner: MediaOwnerLane.direct,
        ),
        isTrue,
      );
      expect((await rawRow('att-evict-d'))!['download_status'], 'downloading');
      expect((await rawRow('att-evict-g'))!['download_status'], 'evicted');
      expect(
        await fixture.repo.commitMediaDownloadLocalPath(
          'att-evict-d',
          owner: MediaOwnerLane.direct,
          localPath: 'media/peer/att-evict-d-new.mp4',
        ),
        isTrue,
      );
      final settled = await rawRow('att-evict-d');
      expect(settled!['download_status'], 'done');
      expect(settled['local_path'], 'media/peer/att-evict-d-new.mp4');
      expect(
        settled['is_bookmarked'],
        1,
        reason: 'viewer state survives the full evict/retry journey',
      );

      // A late commit whose claim was lost (row no longer downloading)
      // affects zero rows.
      expect(
        await fixture.repo.commitMediaDownloadLocalPath(
          'att-evict-d',
          owner: MediaOwnerLane.direct,
          localPath: 'media/peer/att-evict-d-stale.mp4',
        ),
        isFalse,
      );
      expect(
        (await rawRow('att-evict-d'))!['local_path'],
        'media/peer/att-evict-d-new.mp4',
      );
    });

    test(
      'P269 group download failure CAS is atomic and deletion journal cannot resurrect media',
      () async {
        const groupId = 'group-p269-failure';
        const parentId = 'msg-p269-failure';
        await fixture.seedGroupParent(parentId, groupId: groupId);

        final siblingDirectory = await Directory.systemTemp.createTemp(
          'p269_group_download_failure_',
        );
        addTearDown(() async {
          if (await siblingDirectory.exists()) {
            await siblingDirectory.delete(recursive: true);
          }
        });
        final directSiblingFile = File(
          '${siblingDirectory.path}/direct-sibling.bin',
        )..writeAsBytesSync(const [1, 2, 3, 4]);
        final privateSiblingFile = File(
          '${siblingDirectory.path}/group-private-sibling.bin',
        )..writeAsBytesSync(const [5, 6, 7, 8]);

        await fixture.seedDirectParent('msg-p269-direct-sibling');
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-p269-direct-sibling',
            messageId: 'msg-p269-direct-sibling',
            downloadStatus: kMediaDownloadStatusDone,
            localPath: directSiblingFile.path,
          ),
          owner: MediaOwnerLane.direct,
        );
        await fixture.seedGroupParent(
          'msg-p269-private-sibling',
          groupId: groupId,
        );
        await fixture.db.update(
          'group_messages',
          {
            'media_policy_version': 1,
            'media_lifecycle': 'view_once',
            'media_protected': 1,
          },
          where: 'id = ?',
          whereArgs: ['msg-p269-private-sibling'],
        );
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-p269-private-sibling',
            messageId: 'msg-p269-private-sibling',
            downloadStatus: kMediaDownloadStatusDone,
            localPath: privateSiblingFile.path,
          ),
          owner: MediaOwnerLane.group,
        );
        final directSiblingBefore = Map<String, Object?>.from(
          (await rawRow('att-p269-direct-sibling'))!,
        );
        final privateSiblingBefore = Map<String, Object?>.from(
          (await rawRow('att-p269-private-sibling'))!,
        );

        Future<bool> recordFailure({
          required String id,
          String messageId = parentId,
          String targetGroupId = groupId,
          required bool incrementRetryCount,
          required String failureStatus,
          required String expectedDownloadStatus,
          required String? expectedLocalPath,
          required bool clearLocalPath,
        }) => fixture.repo.recordOrdinaryGroupMediaDownloadFailure(
          id,
          groupId: targetGroupId,
          messageId: messageId,
          incrementRetryCount: incrementRetryCount,
          failureStatus: failureStatus,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
          clearLocalPath: clearLocalPath,
        );

        const targetId = 'att-p269-failure';
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: targetId,
            messageId: parentId,
            downloadRetryCount: 0,
          ),
          owner: MediaOwnerLane.group,
        );
        expect(
          await fixture.repo.beginMediaDownload(
            targetId,
            owner: MediaOwnerLane.group,
          ),
          isTrue,
        );
        expect(
          await recordFailure(
            id: targetId,
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: kMediaDownloadStatusDownloading,
            expectedLocalPath: null,
            clearLocalPath: false,
          ),
          isTrue,
        );
        var target = (await rawRow(targetId))!;
        expect(target['download_status'], kMediaDownloadStatusFailed);
        expect(target['download_retry_count'], 1);
        expect(target['local_path'], isNull);

        await fixture.db.update(
          'media_attachments',
          {
            'download_status': kMediaDownloadStatusPending,
            'download_retry_count': kMaxDownloadRetries - 1,
          },
          where: 'id = ?',
          whereArgs: [targetId],
        );
        expect(
          await fixture.repo.beginMediaDownload(
            targetId,
            owner: MediaOwnerLane.group,
          ),
          isTrue,
        );
        expect(
          await recordFailure(
            id: targetId,
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: kMediaDownloadStatusDownloading,
            expectedLocalPath: null,
            clearLocalPath: false,
          ),
          isTrue,
        );
        target = (await rawRow(targetId))!;
        expect(target['download_status'], kMediaDownloadStatusDownloadFailed);
        expect(target['download_retry_count'], kMaxDownloadRetries);

        const authoritativePath =
            'media/group-p269-failure/att-p269-failure.jpg';
        await fixture.db.update(
          'media_attachments',
          {
            'download_status': kMediaDownloadStatusDone,
            'download_retry_count': 2,
            'local_path': authoritativePath,
          },
          where: 'id = ?',
          whereArgs: [targetId],
        );
        final exactBefore = Map<String, Object?>.from(
          (await rawRow(targetId))!,
        );
        expect(
          await recordFailure(
            id: targetId,
            incrementRetryCount: false,
            failureStatus: kMediaDownloadStatusIntegrityFailed,
            expectedDownloadStatus: kMediaDownloadStatusDone,
            expectedLocalPath: '$authoritativePath.changed',
            clearLocalPath: true,
          ),
          isFalse,
          reason: 'a changed path is lost authority, never a wildcard',
        );
        expect(await rawRow(targetId), exactBefore);
        expect(
          await recordFailure(
            id: targetId,
            incrementRetryCount: false,
            failureStatus: kMediaDownloadStatusIntegrityFailed,
            expectedDownloadStatus: kMediaDownloadStatusDone,
            expectedLocalPath: authoritativePath,
            clearLocalPath: true,
          ),
          isTrue,
        );
        target = (await rawRow(targetId))!;
        expect(target['download_status'], kMediaDownloadStatusIntegrityFailed);
        expect(target['download_retry_count'], 2);
        expect(target['local_path'], isNull);

        const journalParentId = 'msg-p269-journal';
        const journalAttachmentId = 'att-p269-journal';
        await fixture.seedGroupParent(journalParentId, groupId: groupId);
        await fixture.repo.saveAttachment(
          makeAttachment(id: journalAttachmentId, messageId: journalParentId),
          owner: MediaOwnerLane.group,
        );
        expect(
          await fixture.repo.beginMediaDownload(
            journalAttachmentId,
            owner: MediaOwnerLane.group,
          ),
          isTrue,
        );
        await fixture.db.insert('group_media_deletion_journal', {
          'attachment_id': journalAttachmentId,
          'operation_id': 'op-p269-active-journal',
          'message_id': journalParentId,
          'group_id': groupId,
          'operation_intent': 'delete_for_me',
          'normalized_mime': 'image/jpeg',
          'canonical_relative_path': null,
          'created_at': '2026-07-22T12:10:00.000Z',
        });
        final journalBefore = Map<String, Object?>.from(
          (await rawRow(journalAttachmentId))!,
        );
        expect(
          await recordFailure(
            id: journalAttachmentId,
            messageId: journalParentId,
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: kMediaDownloadStatusDownloading,
            expectedLocalPath: null,
            clearLocalPath: false,
          ),
          isFalse,
        );
        expect(await rawRow(journalAttachmentId), journalBefore);

        const deletedParentId = 'msg-p269-deleted';
        const deletedAttachmentId = 'att-p269-deleted';
        await fixture.seedGroupParent(deletedParentId, groupId: groupId);
        await fixture.repo.saveAttachment(
          makeAttachment(id: deletedAttachmentId, messageId: deletedParentId),
          owner: MediaOwnerLane.group,
        );
        expect(
          await fixture.repo.beginMediaDownload(
            deletedAttachmentId,
            owner: MediaOwnerLane.group,
          ),
          isTrue,
        );
        final prepared = await dbPrepareGroupMediaDeleteForMe(
          fixture.db,
          groupId: groupId,
          messageId: deletedParentId,
          operationId: 'op-p269-delete-for-me',
        );
        expect(prepared.outcome, GroupMediaDeletePrepareOutcome.prepared);
        final deletedBefore = Map<String, Object?>.from(
          (await rawRow(deletedAttachmentId))!,
        );
        expect(
          await recordFailure(
            id: deletedAttachmentId,
            messageId: deletedParentId,
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: kMediaDownloadStatusDownloading,
            expectedLocalPath: null,
            clearLocalPath: false,
          ),
          isFalse,
        );
        expect(await rawRow(deletedAttachmentId), deletedBefore);
        expect(
          await dbFinalizeGroupMediaDeletionJournalEntry(
            fixture.db,
            attachmentId: deletedAttachmentId,
            messageId: deletedParentId,
          ),
          isTrue,
        );
        expect(await rawRow(deletedAttachmentId), isNull);
        expect(
          await recordFailure(
            id: deletedAttachmentId,
            messageId: deletedParentId,
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: kMediaDownloadStatusDownloading,
            expectedLocalPath: null,
            clearLocalPath: false,
          ),
          isFalse,
          reason: 'UPDATE-only failure persistence cannot resurrect a row',
        );
        expect(await rawRow(deletedAttachmentId), isNull);

        Future<void> expectInactiveGroupRefusesFailure({
          required String suffix,
          required Map<String, Object?> groupMutation,
        }) async {
          final inactiveGroupId = 'group-p269-$suffix';
          final inactiveParentId = 'msg-p269-$suffix';
          final inactiveAttachmentId = 'att-p269-$suffix';
          await fixture.seedGroupParent(
            inactiveParentId,
            groupId: inactiveGroupId,
          );
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: inactiveAttachmentId,
              messageId: inactiveParentId,
              downloadRetryCount: 1,
            ),
            owner: MediaOwnerLane.group,
          );
          expect(
            await fixture.repo.beginMediaDownload(
              inactiveAttachmentId,
              owner: MediaOwnerLane.group,
            ),
            isTrue,
          );
          await fixture.db.update(
            'groups',
            groupMutation,
            where: 'id = ?',
            whereArgs: [inactiveGroupId],
          );
          final before = Map<String, Object?>.from(
            (await rawRow(inactiveAttachmentId))!,
          );

          expect(
            await recordFailure(
              id: inactiveAttachmentId,
              messageId: inactiveParentId,
              targetGroupId: inactiveGroupId,
              incrementRetryCount: true,
              failureStatus: kMediaDownloadStatusFailed,
              expectedDownloadStatus: kMediaDownloadStatusDownloading,
              expectedLocalPath: null,
              clearLocalPath: false,
            ),
            isFalse,
            reason: '$suffix group authority is no longer active',
          );
          expect(await rawRow(inactiveAttachmentId), before);
        }

        await expectInactiveGroupRefusesFailure(
          suffix: 'dissolved',
          groupMutation: const <String, Object?>{
            'is_dissolved': 1,
            'dissolved_at': '2026-07-22T12:20:00.000Z',
            'dissolved_by': 'peer-g',
          },
        );
        await expectInactiveGroupRefusesFailure(
          suffix: 'self-removed',
          groupMutation: const <String, Object?>{
            'self_removed_at': '2026-07-22T12:21:00.000Z',
          },
        );

        const faultParentId = 'msg-p269-fault';
        const faultAttachmentId = 'att-p269-fault';
        await fixture.seedGroupParent(faultParentId, groupId: groupId);
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: faultAttachmentId,
            messageId: faultParentId,
            downloadRetryCount: 1,
          ),
          owner: MediaOwnerLane.group,
        );
        expect(
          await fixture.repo.beginMediaDownload(
            faultAttachmentId,
            owner: MediaOwnerLane.group,
          ),
          isTrue,
        );
        final faultBefore = Map<String, Object?>.from(
          (await rawRow(faultAttachmentId))!,
        );
        await fixture.db.execute('''
CREATE TRIGGER p269_reject_group_download_failure
BEFORE UPDATE OF download_status, download_retry_count, local_path
ON media_attachments
WHEN OLD.id = '$faultAttachmentId'
BEGIN
  SELECT RAISE(ABORT, 'injected p269 failure');
END
''');
        await expectLater(
          () => recordFailure(
            id: faultAttachmentId,
            messageId: faultParentId,
            incrementRetryCount: true,
            failureStatus: kMediaDownloadStatusFailed,
            expectedDownloadStatus: kMediaDownloadStatusDownloading,
            expectedLocalPath: null,
            clearLocalPath: false,
          ),
          throwsA(anything),
        );
        expect(
          await rawRow(faultAttachmentId),
          faultBefore,
          reason: 'one failed statement cannot split the status/count tuple',
        );
        await fixture.db.execute(
          'DROP TRIGGER p269_reject_group_download_failure',
        );

        expect(await rawRow('att-p269-direct-sibling'), directSiblingBefore);
        expect(await rawRow('att-p269-private-sibling'), privateSiblingBefore);
        expect(directSiblingFile.readAsBytesSync(), const [1, 2, 3, 4]);
        expect(privateSiblingFile.readAsBytesSync(), const [5, 6, 7, 8]);
      },
    );

    test(
      'P269 automatic ordinary group claim and commit requalify terminal evicted parent group and deletion authority',
      () async {
        const groupId = 'group-p269-auto-cas';
        final repository =
            fixture.repo as OrdinaryGroupAutomaticMediaDownloadStateRepository;

        Future<void> seed(
          String suffix, {
          String status = kMediaDownloadStatusPending,
        }) async {
          final messageId = 'message-$suffix';
          await fixture.seedGroupParent(messageId, groupId: groupId);
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: 'attachment-$suffix',
              messageId: messageId,
              downloadStatus: status,
              downloadRetryCount: status == kMediaDownloadStatusDownloadFailed
                  ? kMaxDownloadRetries
                  : 0,
            ),
            owner: MediaOwnerLane.group,
          );
        }

        Future<bool> begin(
          String suffix, {
          String expectedStatus = kMediaDownloadStatusPending,
        }) => repository.beginOrdinaryGroupAutomaticMediaDownload(
          'attachment-$suffix',
          groupId: groupId,
          messageId: 'message-$suffix',
          expectedDownloadStatus: expectedStatus,
          expectedLocalPath: null,
        );

        Future<bool> commit(String suffix) =>
            repository.commitOrdinaryGroupAutomaticMediaDownloadLocalPath(
              'attachment-$suffix',
              groupId: groupId,
              messageId: 'message-$suffix',
              expectedLocalPath: null,
              localPath: 'group_media/attachment-$suffix.jpg',
            );

        for (final terminal in const <(String, String)>[
          ('terminal', kMediaDownloadStatusDownloadFailed),
          ('evicted', kMediaDownloadStatusEvicted),
        ]) {
          await seed(terminal.$1, status: terminal.$2);
          final before = Map<String, Object?>.from(
            (await rawRow('attachment-${terminal.$1}'))!,
          );
          expect(
            await begin(terminal.$1, expectedStatus: terminal.$2),
            isFalse,
          );
          expect(await rawRow('attachment-${terminal.$1}'), before);
        }

        await seed('dissolved');
        expect(await begin('dissolved'), isTrue);
        await fixture.db.update(
          'groups',
          {
            'is_dissolved': 1,
            'dissolved_at': '2026-07-22T14:00:00.000Z',
            'dissolved_by': 'peer-g',
          },
          where: 'id = ?',
          whereArgs: [groupId],
        );
        expect(await commit('dissolved'), isFalse);
        expect(
          (await rawRow('attachment-dissolved'))!['download_status'],
          kMediaDownloadStatusDownloading,
        );
        await fixture.db.update(
          'groups',
          {'is_dissolved': 0, 'dissolved_at': null, 'dissolved_by': null},
          where: 'id = ?',
          whereArgs: [groupId],
        );

        await seed('self-removed');
        expect(await begin('self-removed'), isTrue);
        await fixture.db.update(
          'groups',
          {'self_removed_at': '2026-07-22T14:00:30.000Z'},
          where: 'id = ?',
          whereArgs: [groupId],
        );
        expect(await commit('self-removed'), isFalse);
        await fixture.db.update(
          'groups',
          {'self_removed_at': null},
          where: 'id = ?',
          whereArgs: [groupId],
        );

        await seed('protected');
        expect(await begin('protected'), isTrue);
        await fixture.db.update(
          'group_messages',
          {
            'media_policy_version': 1,
            'media_lifecycle': 'view_once',
            'media_protected': 1,
          },
          where: 'id = ?',
          whereArgs: ['message-protected'],
        );
        expect(await commit('protected'), isFalse);

        await seed('deleted');
        expect(await begin('deleted'), isTrue);
        await fixture.db.insert('group_message_local_deletions', {
          'message_id': 'message-deleted',
          'group_id': groupId,
          'deleted_at': '2026-07-22T14:01:00.000Z',
          'created_at': '2026-07-22T14:01:00.000Z',
        });
        expect(await commit('deleted'), isFalse);

        await seed('journal');
        expect(await begin('journal'), isTrue);
        await fixture.db.insert('group_media_deletion_journal', {
          'attachment_id': 'attachment-journal',
          'operation_id': 'operation-journal',
          'message_id': 'message-journal',
          'group_id': groupId,
          'operation_intent': 'delete_for_me',
          'normalized_mime': 'image/jpeg',
          'canonical_relative_path': null,
          'created_at': '2026-07-22T14:02:00.000Z',
        });
        expect(await commit('journal'), isFalse);

        await seed('valid');
        expect(await begin('valid'), isTrue);
        expect(await commit('valid'), isTrue);
        final valid = (await rawRow('attachment-valid'))!;
        expect(valid['download_status'], kMediaDownloadStatusDone);
        expect(valid['local_path'], 'group_media/attachment-valid.jpg');
      },
    );

    test(
      'P269 recoverable group download query is authority scoped cursor paged and cannot starve later rows',
      () async {
        const sharedCreatedAt = '2026-07-22T13:00:00.000Z';

        Future<void> seedGroupCandidate({
          required String id,
          String status = kMediaDownloadStatusPending,
          int retryCount = 0,
          bool incoming = true,
          Map<String, Object?> parentOverrides = const <String, Object?>{},
          bool selfRemoved = false,
          bool dissolved = false,
          bool deleteParent = false,
          bool locallyDeleted = false,
          bool deletionJournal = false,
        }) async {
          final groupId = 'group-$id';
          final messageId = 'message-$id';
          await fixture.seedGroupParent(
            messageId,
            groupId: groupId,
            timestamp: sharedCreatedAt,
          );
          if (!incoming || parentOverrides.isNotEmpty) {
            await fixture.db.update(
              'group_messages',
              <String, Object?>{
                if (!incoming) 'is_incoming': 0,
                ...parentOverrides,
              },
              where: 'id = ?',
              whereArgs: <Object?>[messageId],
            );
          }
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: id,
              messageId: messageId,
              downloadStatus: status,
              downloadRetryCount: retryCount,
              createdAt: sharedCreatedAt,
            ),
            owner: MediaOwnerLane.group,
          );
          if (selfRemoved || dissolved) {
            await fixture.db.update(
              'groups',
              <String, Object?>{
                if (selfRemoved) 'self_removed_at': sharedCreatedAt,
                if (dissolved) ...<String, Object?>{
                  'is_dissolved': 1,
                  'dissolved_at': sharedCreatedAt,
                  'dissolved_by': 'peer-g',
                },
              },
              where: 'id = ?',
              whereArgs: <Object?>[groupId],
            );
          }
          if (locallyDeleted) {
            await fixture.db.insert('group_message_local_deletions', {
              'message_id': messageId,
              'group_id': groupId,
              'deleted_at': sharedCreatedAt,
              'created_at': sharedCreatedAt,
            });
          }
          if (deletionJournal) {
            await fixture.db.insert('group_media_deletion_journal', {
              'attachment_id': id,
              'operation_id': 'operation-$id',
              'message_id': messageId,
              'group_id': groupId,
              'operation_intent': 'delete_for_me',
              'normalized_mime': 'image/jpeg',
              'canonical_relative_path': null,
              'created_at': sharedCreatedAt,
            });
          }
          if (deleteParent) {
            await fixture.db.delete(
              'group_messages',
              where: 'id = ?',
              whereArgs: <Object?>[messageId],
            );
          }
        }

        const expectedIds = <String>[
          '10-pending-0',
          '20-pending-2',
          '30-downloading-0',
          '40-downloading-2',
          '50-failed-0',
          '60-failed-2',
        ];
        await seedGroupCandidate(id: expectedIds[0]);
        await seedGroupCandidate(id: expectedIds[1], retryCount: 2);
        await seedGroupCandidate(
          id: expectedIds[2],
          status: kMediaDownloadStatusDownloading,
        );
        await seedGroupCandidate(
          id: expectedIds[3],
          status: kMediaDownloadStatusDownloading,
          retryCount: 2,
        );
        await seedGroupCandidate(
          id: expectedIds[4],
          status: kMediaDownloadStatusFailed,
        );
        await seedGroupCandidate(
          id: expectedIds[5],
          status: kMediaDownloadStatusFailed,
          retryCount: 2,
        );

        const excludedIds = <String>[
          '01-direct',
          '02-outgoing-group',
          '03-self-removed',
          '04-dissolved',
          '05-missing-parent',
          '06-local-deletion',
          '07-deletion-journal',
          '08-protected',
          '09-view-once',
          '11-disappearing',
          '12-pending-budget-3',
          '13-downloading-budget-3',
          '14-failed-budget-3',
          '15-download-failed',
          '16-integrity-failed',
          '17-upload-pending',
          '18-upload-failed',
          '19-done',
          '21-evicted',
        ];
        await fixture.seedDirectParent('message-${excludedIds[0]}');
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: excludedIds[0],
            messageId: 'message-${excludedIds[0]}',
            createdAt: sharedCreatedAt,
          ),
          owner: MediaOwnerLane.direct,
        );
        await seedGroupCandidate(id: excludedIds[1], incoming: false);
        await seedGroupCandidate(id: excludedIds[2], selfRemoved: true);
        await seedGroupCandidate(id: excludedIds[3], dissolved: true);
        await seedGroupCandidate(id: excludedIds[4], deleteParent: true);
        await seedGroupCandidate(id: excludedIds[5], locallyDeleted: true);
        await seedGroupCandidate(id: excludedIds[6], deletionJournal: true);
        await seedGroupCandidate(
          id: excludedIds[7],
          parentOverrides: const <String, Object?>{
            'media_policy_version': 1,
            'media_lifecycle': 'standard',
            'media_protected': 1,
          },
        );
        await seedGroupCandidate(
          id: excludedIds[8],
          parentOverrides: const <String, Object?>{
            'media_policy_version': 1,
            'media_lifecycle': 'view_once',
            'media_protected': 1,
          },
        );
        await seedGroupCandidate(
          id: excludedIds[9],
          parentOverrides: const <String, Object?>{
            'media_policy_version': 1,
            'media_lifecycle': 'disappearing',
            'media_duration_seconds': 3600,
            'media_protected': 1,
          },
        );
        await seedGroupCandidate(id: excludedIds[10], retryCount: 3);
        await seedGroupCandidate(
          id: excludedIds[11],
          status: kMediaDownloadStatusDownloading,
          retryCount: 3,
        );
        await seedGroupCandidate(
          id: excludedIds[12],
          status: kMediaDownloadStatusFailed,
          retryCount: 3,
        );
        await seedGroupCandidate(
          id: excludedIds[13],
          status: kMediaDownloadStatusDownloadFailed,
        );
        await seedGroupCandidate(
          id: excludedIds[14],
          status: kMediaDownloadStatusIntegrityFailed,
        );
        await seedGroupCandidate(
          id: excludedIds[15],
          status: kMediaDownloadStatusUploadPending,
        );
        await seedGroupCandidate(
          id: excludedIds[16],
          status: kMediaDownloadStatusUploadFailed,
        );
        await seedGroupCandidate(
          id: excludedIds[17],
          status: kMediaDownloadStatusDone,
        );
        await seedGroupCandidate(
          id: excludedIds[18],
          status: kMediaDownloadStatusEvicted,
        );

        final excludedBefore = <String, Map<String, Object?>>{
          for (final id in excludedIds)
            id: Map<String, Object?>.from((await rawRow(id))!),
        };

        final repository =
            fixture.repo as RecoverableGroupMediaDownloadRepository;
        DurableGroupMediaDownloadCursor? cursor;
        final scannedIds = <String>[];
        String? laterPolicyEligibleId;
        for (var pageNumber = 0; pageNumber < 10; pageNumber++) {
          final page = await repository.loadRecoverableGroupDownloadPage(
            after: cursor,
            limit: 2,
          );
          if (page.isEmpty) break;
          scannedIds.addAll(page.map((candidate) => candidate.attachment.id));
          cursor = page.last.cursor;
          for (final candidate in page) {
            if (!expectedIds.take(5).contains(candidate.attachment.id)) {
              laterPolicyEligibleId = candidate.attachment.id;
            }
            expect(candidate.groupId, 'group-${candidate.attachment.id}');
            expect(candidate.attachment.ownerLane, MediaOwnerLane.group);
          }
        }

        expect(scannedIds, expectedIds);
        expect(scannedIds.toSet(), hasLength(scannedIds.length));
        expect(
          laterPolicyEligibleId,
          expectedIds.last,
          reason:
              'advancing the durable cursor must reach a row after more than one externally denied page',
        );
        expect(
          await repository.loadRecoverableGroupDownloadPage(
            after: cursor,
            limit: 2,
          ),
          isEmpty,
        );

        for (final entry in excludedBefore.entries) {
          expect(
            await rawRow(entry.key),
            entry.value,
            reason: '${entry.key} must stay byte-for-byte unchanged',
          );
        }
      },
    );

    // --- 228 TC-228-10 ---

    test(
      'video resume handles unknown duration revalidation and completion',
      () async {
        // Unknown-duration video.
        await saveDirect(
          makeAttachment(
            id: 'vid-unknown',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: null,
            downloadStatus: 'done',
          ),
        );

        // Negative clamps to zero.
        await fixture.repo.updatePlaybackPosition('vid-unknown', -50);
        expect((await rawRow('vid-unknown'))!['last_playback_position_ms'], 0);

        // Unknown duration stores any non-negative position.
        await fixture.repo.updatePlaybackPosition('vid-unknown', 123456);
        expect(
          (await rawRow('vid-unknown'))!['last_playback_position_ms'],
          123456,
        );

        // A later replay that supplies the duration re-clamps the stored
        // overshoot to the new known duration.
        await saveDirect(
          makeAttachment(
            id: 'vid-unknown',
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 9000,
            downloadStatus: 'done',
          ),
        );
        expect(
          (await rawRow('vid-unknown'))!['last_playback_position_ms'],
          9000,
        );

        // Known duration: in-range stores, end-or-past resets to 0
        // (completion).
        await fixture.repo.updatePlaybackPosition('vid-unknown', 4500);
        expect(
          (await rawRow('vid-unknown'))!['last_playback_position_ms'],
          4500,
        );
        await fixture.repo.updatePlaybackPosition('vid-unknown', 12000);
        expect((await rawRow('vid-unknown'))!['last_playback_position_ms'], 0);
        await fixture.repo.updatePlaybackPosition('vid-unknown', 4500);
        await fixture.repo.updatePlaybackPosition('vid-unknown', 9000);
        expect((await rawRow('vid-unknown'))!['last_playback_position_ms'], 0);

        // Non-video rejection: playback state never applies to images.
        await saveDirect(
          makeAttachment(id: 'img-1', mediaType: 'image', mime: 'image/jpeg'),
        );
        await expectLater(
          () => fixture.repo.updatePlaybackPosition('img-1', 1000),
          throwsA(isA<ArgumentError>()),
        );
        expect((await rawRow('img-1'))!['last_playback_position_ms'], 0);

        // Bookmarks apply to image and video, never audio/file.
        await fixture.repo.setBookmarked('img-1', bookmarked: true);
        expect((await rawRow('img-1'))!['is_bookmarked'], 1);
        await saveDirect(
          makeAttachment(id: 'aud-1', mediaType: 'audio', mime: 'audio/mp4'),
        );
        await expectLater(
          () => fixture.repo.setBookmarked('aud-1', bookmarked: true),
          throwsA(isA<ArgumentError>()),
        );
        expect((await rawRow('aud-1'))!['is_bookmarked'], 0);
      },
    );

    // --- 228 TC-228-11 ---

    test('parent helpers retain but hide orphan media and preserve collision '
        'siblings', () async {
      // Collision: the same parent id exists in both lanes, each with an
      // attachment carrying local viewer state.
      await fixture.seedDirectParent(
        'msg-shared',
        timestamp: '2026-07-01T10:00:00.000Z',
      );
      await fixture.seedGroupParent(
        'msg-shared',
        timestamp: '2026-07-01T10:00:00.000Z',
      );
      await fixture.repo.saveAttachment(
        makeAttachment(
          id: 'att-d',
          messageId: 'msg-shared',
          downloadStatus: 'done',
          localPath: '/media/att-d.jpg',
        ),
        owner: MediaOwnerLane.direct,
      );
      await fixture.repo.saveAttachment(
        makeAttachment(
          id: 'att-g-sib',
          messageId: 'msg-shared',
          mime: 'video/mp4',
          mediaType: 'video',
          durationMs: 10000,
          downloadStatus: 'done',
          localPath: '/media/att-g-sib.mp4',
        ),
        owner: MediaOwnerLane.group,
      );
      await fixture.repo.setBookmarked('att-g-sib', bookmarked: true);
      await fixture.repo.updatePlaybackPosition('att-g-sib', 3000);

      const directScope = MediaLibraryScope.direct('contact-1');
      const groupScope = MediaLibraryScope.group('group-1');
      expect(
        (await fixture.repo.getMediaLibraryPage(
          scope: directScope,
        )).entries.map((e) => e.attachment.id),
        ['att-d'],
      );
      expect(
        (await fixture.repo.getMediaLibraryPage(
          scope: groupScope,
        )).entries.map((e) => e.attachment.id),
        ['att-g-sib'],
      );

      // Generic DIRECT parent-only deletion: no attachment cascade — the
      // raw row is retained but becomes library-invisible (no live
      // parent). The same-ID group sibling and its viewer state survive.
      await dbDeleteMessage(fixture.db, 'msg-shared');
      expect(await rawRow('att-d'), isNotNull);
      expect(
        (await fixture.repo.getMediaLibraryPage(scope: directScope)).entries,
        isEmpty,
      );
      final sib = await rawRow('att-g-sib');
      expect(sib!['is_bookmarked'], 1);
      expect(sib['last_playback_position_ms'], 3000);
      expect(
        (await fixture.repo.getMediaLibraryPage(
          scope: groupScope,
        )).entries.map((e) => e.attachment.id),
        ['att-g-sib'],
      );

      // Real GROUP tombstone helper: records the durable tombstone and
      // deletes the parent; the attachment row is retained but hidden, and
      // an attempted parent reinsertion cannot resurface it.
      await dbDeleteGroupMessage(fixture.db, 'msg-shared');
      expect(await rawRow('att-g-sib'), isNotNull);
      expect(
        (await fixture.repo.getMediaLibraryPage(scope: groupScope)).entries,
        isEmpty,
      );
      await fixture.seedGroupParent(
        'msg-shared',
        timestamp: '2026-07-01T10:00:00.000Z',
      );
      expect(
        (await fixture.repo.getMediaLibraryPage(scope: groupScope)).entries,
        isEmpty,
      );

      // Both retained orphans still hold their bytes/state (fail-safe
      // retention, invisible through predicates — not a product-visible
      // resurrection).
      expect((await rawRow('att-d'))!['local_path'], '/media/att-d.jpg');
      expect((await rawRow('att-g-sib'))!['last_playback_position_ms'], 3000);
    });

    test(
      'exact direct bookmark loses a parent privacy race with zero write',
      () async {
        await fixture.seedDirectParent('msg-bookmark-race');
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-bookmark-race',
            messageId: 'msg-bookmark-race',
            mediaType: 'image',
            mime: 'image/jpeg',
          ),
          owner: MediaOwnerLane.direct,
        );
        final directState = fixture.repo as DirectMediaLibraryStateRepository;

        expect(
          await directState.setDirectBookmarkedIfOrdinary(
            messageId: 'msg-bookmark-race',
            attachmentId: 'att-bookmark-race',
            bookmarked: true,
          ),
          isTrue,
        );
        expect((await rawRow('att-bookmark-race'))!['is_bookmarked'], 1);

        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'protected',
            'private_media_state': 'available',
          },
          where: 'id = ?',
          whereArgs: ['msg-bookmark-race'],
        );
        expect(
          await directState.setDirectBookmarkedIfOrdinary(
            messageId: 'msg-bookmark-race',
            attachmentId: 'att-bookmark-race',
            bookmarked: false,
          ),
          isFalse,
        );
        expect(
          (await rawRow('att-bookmark-race'))!['is_bookmarked'],
          1,
          reason: 'privacy race must not mutate the stale loaded row',
        );
      },
    );

    test(
      'exact direct bookmark rejects identity owner terminal visibility and corrupt races',
      () async {
        final directState = fixture.repo as DirectMediaLibraryStateRepository;

        Future<void> seedDirect(
          String messageId,
          String attachmentId, {
          String? hiddenAt,
          String? deletedAt,
        }) async {
          await fixture.seedDirectParent(
            messageId,
            hiddenAt: hiddenAt,
            deletedAt: deletedAt,
          );
          await fixture.repo.saveAttachment(
            makeAttachment(
              id: attachmentId,
              messageId: messageId,
              mediaType: 'image',
              mime: 'image/jpeg',
            ),
            owner: MediaOwnerLane.direct,
          );
        }

        await seedDirect('msg-exact-a', 'att-exact-a');
        await seedDirect('msg-exact-b', 'att-exact-b');
        await seedDirect('msg-terminal', 'att-terminal');
        await seedDirect(
          'msg-hidden',
          'att-hidden',
          hiddenAt: '2026-07-11T10:00:00.000Z',
        );
        await seedDirect(
          'msg-deleted',
          'att-deleted',
          deletedAt: '2026-07-11T10:00:00.000Z',
        );
        await seedDirect('msg-corrupt', 'att-corrupt');
        await seedDirect('msg-corrupt-lifecycle', 'att-corrupt-lifecycle');
        await seedDirect('msg-unresolved', 'att-unresolved');
        await fixture.db.update(
          'media_attachments',
          {'owner_lane': 'unresolved'},
          where: 'id = ?',
          whereArgs: ['att-unresolved'],
        );

        await fixture.seedGroupParent('msg-group-bookmark');
        await fixture.repo.saveAttachment(
          makeAttachment(
            id: 'att-group-bookmark',
            messageId: 'msg-group-bookmark',
            mediaType: 'image',
            mime: 'image/jpeg',
          ),
          owner: MediaOwnerLane.group,
        );
        await fixture.repo.setBookmarked(
          'att-group-bookmark',
          bookmarked: true,
        );

        await fixture.db.update(
          'messages',
          {
            'private_media_policy_version': 1,
            'private_media_mode': 'view_once',
            'private_media_state': 'expired',
            'private_media_terminal_at_ms': 1_800_000_000_000,
          },
          where: 'id = ?',
          whereArgs: ['msg-terminal'],
        );
        await fixture.db.update(
          'messages',
          {'private_media_policy_version': 1},
          where: 'id = ?',
          whereArgs: ['msg-corrupt'],
        );
        await fixture.db.update(
          'messages',
          {'private_media_expires_at_ms': 1_800_000_000_000},
          where: 'id = ?',
          whereArgs: ['msg-corrupt-lifecycle'],
        );

        final denied = <({String messageId, String attachmentId})>[
          (messageId: 'msg-exact-b', attachmentId: 'att-exact-a'),
          (messageId: 'msg-exact-a', attachmentId: 'missing-attachment'),
          (messageId: 'msg-terminal', attachmentId: 'att-terminal'),
          (messageId: 'msg-hidden', attachmentId: 'att-hidden'),
          (messageId: 'msg-deleted', attachmentId: 'att-deleted'),
          (messageId: 'msg-corrupt', attachmentId: 'att-corrupt'),
          (
            messageId: 'msg-corrupt-lifecycle',
            attachmentId: 'att-corrupt-lifecycle',
          ),
          (messageId: 'msg-unresolved', attachmentId: 'att-unresolved'),
          (messageId: 'msg-group-bookmark', attachmentId: 'att-group-bookmark'),
        ];
        for (final identity in denied) {
          expect(
            await directState.setDirectBookmarkedIfOrdinary(
              messageId: identity.messageId,
              attachmentId: identity.attachmentId,
              bookmarked: true,
            ),
            isFalse,
            reason: identity.toString(),
          );
        }

        for (final attachmentId in const [
          'att-exact-a',
          'att-exact-b',
          'att-terminal',
          'att-hidden',
          'att-deleted',
          'att-corrupt',
          'att-corrupt-lifecycle',
          'att-unresolved',
        ]) {
          expect((await rawRow(attachmentId))!['is_bookmarked'], 0);
        }
        expect((await rawRow('att-group-bookmark'))!['is_bookmarked'], 1);
      },
    );
  });

  group('Plan 353 media caption-only edit repository authority', () {
    const messageId = 'tc353-repo-parent';
    const recipient = 'tc353-repo-recipient';
    const sender = 'peer-local';
    const t0 = '2026-08-09T09:00:00.000Z';
    const t1 = '2026-08-09T09:00:01.000Z';
    const fingerprintA =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const fingerprintB =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    /// Seeds one fully drained but still provable strict generation whose raw
    /// keys live ONLY in the secure store.
    Future<void> seedStrictParent({
      bool isIncoming = false,
      List<String> fingerprints = const <String>[fingerprintA, fingerprintB],
    }) async {
      await fixture.db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': isIncoming ? sender : recipient,
        'sender_peer_id': sender,
        'text': 'original caption',
        'timestamp': t0,
        'status': 'delivered',
        'is_incoming': isIncoming ? 1 : 0,
        'created_at': t0,
        'transport': isIncoming ? 'inbox' : 'direct',
      });
      // Deliberately inserted newest-id-first so the canonical projection has
      // to impose `created_at ASC, id ASC` itself.
      for (final index in const <int>[1, 0]) {
        final attachmentId = '$messageId-${String.fromCharCode(97 + index)}';
        await fixture.db.insert('media_attachments', <String, Object?>{
          'id': attachmentId,
          'message_id': messageId,
          'owner_lane': 'direct',
          'mime': 'image/jpeg',
          'size': 800 + index,
          'media_type': 'image',
          'created_at': t0,
          'download_status': 'done',
          'local_path': 'media/direct/$attachmentId.jpg',
          'content_hash': '${index + 1}' * 64,
          'encryption_key_base64': secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName(attachmentId),
          ),
          'encryption_nonce': 'nonce-$attachmentId',
          'encryption_scheme': 'blob_aes_256_gcm_v1',
          'direct_media_blob_custody_fingerprint': fingerprints[index],
        });
        await fixture.secureKeyStore.write(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
          'raw-key-$attachmentId',
        );
      }
    }

    test('TC-353-02 qualification hydrates canonical keys and never sends raw '
        'key material into SQLite', () async {
      await seedStrictParent();

      final authority = await fixture.repo
          .qualifyOutgoingDirectMediaCaptionEdit(messageId);
      expect(authority.lane, OutgoingDirectMediaCaptionEditLane.strictMedia);
      expect(authority.parent!.id, messageId);
      expect(authority.parent!.contactPeerId, recipient);
      expect(
        authority.attachments.map((a) => a.id).toList(),
        <String>['$messageId-a', '$messageId-b'],
        reason: 'canonical order is created_at ASC then id ASC',
      );
      expect(
        authority.attachments.map((a) => a.encryptionKeyBase64).toList(),
        <String>['raw-key-$messageId-a', 'raw-key-$messageId-b'],
        reason: 'raw keys are hydrated OUTSIDE the SQL transaction',
      );
      for (final row in await fixture.db.query('media_attachments')) {
        expect(
          isSecureStoreReference(row['encryption_key_base64']! as String),
          isTrue,
          reason: 'SQLite only ever holds the storage reference',
        );
      }

      // A hydration failure is fail-closed, never a weaker fallback.
      await fixture.secureKeyStore.delete(
        mediaAttachmentEncryptionKeyStoreName('$messageId-a'),
      );
      expect(
        (await fixture.repo.qualifyOutgoingDirectMediaCaptionEdit(
          messageId,
        )).lane,
        OutgoingDirectMediaCaptionEditLane.contradiction,
      );
    });

    test('TC-353-04 incoming apply proves hydrated keys and preserves every '
        'attachment descriptor', () async {
      await seedStrictParent(isIncoming: true);
      final attachmentsBefore = await fixture.db.query(
        'media_attachments',
        orderBy: 'id ASC',
      );
      final descriptors = <MediaAttachment>[
        for (final index in const <int>[0, 1])
          MediaAttachment(
            id: '$messageId-${String.fromCharCode(97 + index)}',
            messageId: messageId,
            mime: 'image/jpeg',
            size: 800 + index,
            mediaType: 'image',
            downloadStatus: 'done',
            createdAt: t0,
            contentHash: '${index + 1}' * 64,
            encryptionKeyBase64:
                'raw-key-$messageId-${String.fromCharCode(97 + index)}',
            encryptionNonce:
                'nonce-$messageId-${String.fromCharCode(97 + index)}',
            encryptionScheme: 'blob_aes_256_gcm_v1',
            ownerLane: MediaOwnerLane.direct,
          ),
      ];
      final incoming = ConversationMessage(
        id: messageId,
        contactPeerId: sender,
        senderPeerId: sender,
        text: 'edited caption',
        timestamp: t0,
        status: 'delivered',
        isIncoming: true,
        createdAt: t0,
        editedAt: t1,
      );

      final applied = await fixture.repo.applyIncomingDirectMediaCaptionEdit(
        incoming: incoming,
        attachments: descriptors,
      );
      expect(applied.outcome, IncomingDirectMediaCaptionEditOutcome.applied);
      expect(applied.message!.text, 'edited caption');
      expect(applied.message!.editedAt, t1);
      expect(
        await fixture.db.query('media_attachments', orderBy: 'id ASC'),
        attachmentsBefore,
        reason: 'the immutable generation survives the caption apply',
      );

      // A drifted raw key refuses; SQLite still performs no secure-store I/O.
      final drifted = await fixture.repo.applyIncomingDirectMediaCaptionEdit(
        incoming: incoming.copyWith(
          text: 'forged caption',
          editedAt: '2026-08-09T09:00:09.000Z',
        ),
        attachments: <MediaAttachment>[
          descriptors.first.copyWith(encryptionKeyBase64: 'forged-key'),
          descriptors.last,
        ],
      );
      expect(drifted.outcome, IncomingDirectMediaCaptionEditOutcome.refused);
      expect(
        (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single['text'],
        'edited caption',
      );
    });
  });

  group('Plan 354 private direct-media blob repository authority', () {
    const createdAt = '2026-08-10T15:30:00.000Z';

    ({
      ConversationMessage parent,
      MediaAttachment pending,
      MediaAttachment prepared,
      DirectMediaBlobCustodyRow custody,
    })
    privateCandidate({
      required String suffix,
      String hashDigit = 'a',
      String mode = 'protected',
      String mime = 'image/jpeg',
      String mediaType = 'image',
      String? contactPeerId,
    }) {
      final messageId = 'tc354-repo-$suffix';
      final attachmentId = 'tc354-repo-$suffix-attachment';
      final extension = mime == 'video/mp4' ? 'mp4' : 'jpg';
      final parent = ConversationMessage(
        id: messageId,
        contactPeerId: contactPeerId ?? 'tc354-repo-recipient-$suffix',
        senderPeerId: 'tc354-repo-local',
        text: '',
        timestamp: createdAt,
        status: 'sending',
        isIncoming: false,
        createdAt: createdAt,
        dedupKey: messageId,
        privateMediaPolicy: mode == 'protected'
            ? const PrivateMediaPolicy.protected()
            : const PrivateMediaPolicy.viewOnce(),
        privateMediaState: PrivateMediaLifecycleState.available,
      );
      final pending = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: mime,
        size: 31,
        mediaType: mediaType,
        localPath: 'pending_uploads/$messageId/$attachmentId.$extension',
        downloadStatus: 'upload_pending',
        createdAt: createdAt,
        ownerLane: MediaOwnerLane.direct,
      );
      final hash = hashDigit * 64;
      return (
        parent: parent,
        pending: pending,
        prepared: pending.copyWith(
          contentHash: hash,
          encryptionKeyBase64: 'tc354-key-$suffix-$hashDigit',
          encryptionNonce: 'tc354-nonce-$suffix-$hashDigit',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ),
        custody: DirectMediaBlobCustodyRow(
          attachmentId: attachmentId,
          messageId: messageId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          state: DirectMediaBlobCustodyState.outgoingPrepared,
          inboxCustodyIncarnationId: null,
          recipientPeerId: parent.contactPeerId,
          ciphertextRelativePath:
              'direct_media_blob_custody_v1/${'3' * 64}/$attachmentId.blob',
          contentHash: hash,
          ciphertextSize: 47,
          expiresAtMs: null,
          custodyRelayPeerId: null,
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
    }

    Future<void> seedPrivatePending(
      ({
        ConversationMessage parent,
        MediaAttachment pending,
        MediaAttachment prepared,
        DirectMediaBlobCustodyRow custody,
      })
      candidate,
    ) async {
      await fixture.db.insert('messages', candidate.parent.toMap());
      await fixture.db.insert('media_attachments', candidate.pending.toMap());
    }

    test(
      'TC-354-01b private blob winner and key compensation are exact',
      () async {
        final winner = privateCandidate(suffix: 'winner');
        await seedPrivatePending(winner);
        final repo =
            fixture.repo as OutgoingDirectPrivateMediaBlobGenerationRepository;
        expect(repo.supportsOutgoingDirectPrivateMediaBlobGeneration, isTrue);

        final applied = await repo
            .stageOutgoingDirectPrivateMediaBlobGeneration(
              expectedParent: winner.parent,
              expectedAttachment: winner.pending,
              preparedAttachment: winner.prepared,
              custodyRow: winner.custody,
            );
        expect(applied.outcome, DirectMediaBlobGenerationStageOutcome.applied);
        expect(applied.attachments, hasLength(1));
        expect(applied.custodyRows, hasLength(1));
        // The raw key is published only under the canonical secure-store name;
        // SQLite receives a reference, never the key bytes.
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(winner.pending.id),
          ),
          winner.prepared.encryptionKeyBase64,
        );
        final persisted = (await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: <Object?>[winner.pending.id],
        )).single;
        expect(
          persisted['encryption_key_base64'],
          secureStoreReferenceForKey(
            mediaAttachmentEncryptionKeyStoreName(winner.pending.id),
          ),
        );
        // The convention-owned pending identity survives publication intact.
        expect(persisted['download_status'], 'upload_pending');
        expect(persisted['local_path'], winner.pending.localPath);

        // A losing candidate with different ciphertext adopts the exact winner
        // and never overwrites the stable per-attachment key.
        final writesAfterWinner = fixture.secureKeyStore.writtenKeys.length;
        final loser = privateCandidate(suffix: 'winner', hashDigit: 'b');
        final adopted = await repo
            .stageOutgoingDirectPrivateMediaBlobGeneration(
              expectedParent: loser.parent,
              expectedAttachment: loser.pending,
              preparedAttachment: loser.prepared,
              custodyRow: loser.custody,
            );
        expect(
          adopted.outcome,
          DirectMediaBlobGenerationStageOutcome.idempotent,
        );
        expect(adopted.attachments.single.contentHash, 'a' * 64);
        expect(
          adopted.attachments.single.encryptionKeyBase64,
          winner.prepared.encryptionKeyBase64,
        );
        expect(
          fixture.secureKeyStore.writtenKeys,
          hasLength(writesAfterWinner),
          reason: 'a losing private candidate must not publish its key',
        );

        // A refused candidate restores the previous secure-store state: a
        // View-Once video is outside the producer matrix.
        final refusedCandidate = privateCandidate(
          suffix: 'viewonce-video',
          mode: 'view_once',
          mime: 'video/mp4',
          mediaType: 'video',
        );
        await seedPrivatePending(refusedCandidate);
        final refused = await repo
            .stageOutgoingDirectPrivateMediaBlobGeneration(
              expectedParent: refusedCandidate.parent,
              expectedAttachment: refusedCandidate.pending,
              preparedAttachment: refusedCandidate.prepared,
              custodyRow: refusedCandidate.custody,
            );
        expect(refused.outcome, DirectMediaBlobGenerationStageOutcome.refused);
        expect(
          await fixture.secureKeyStore.read(
            mediaAttachmentEncryptionKeyStoreName(refusedCandidate.pending.id),
          ),
          isNull,
          reason: 'a refused private stage compensates its raw key write',
        );
        expect(
          (await fixture.db.query(
            'media_attachments',
            where: 'id = ?',
            whereArgs: <Object?>[refusedCandidate.pending.id],
          )).single['content_hash'],
          isNull,
        );
      },
    );

    test(
      'TC-366-01b private fanout atomically publishes N v114 rows without a v110 token',
      () async {
        const contactAccountPeerId = 'tc366-private-contact-account';
        const contactSigningKey = 'tc366-private-contact-signing-key';
        await fixture.db.insert('contacts', <String, Object?>{
          'peer_id': contactAccountPeerId,
          'public_key': contactSigningKey,
          'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
          'username': 'TC366 Private Contact',
          'signature': 'sig-base64',
          'scanned_at': createdAt,
          'ml_kem_public_key': 'mlkem-tc366-legacy-account',
        });
        await fixture.db
            .insert('direct_contact_device_roster_metadata', <String, Object?>{
              'contact_account_peer_id': contactAccountPeerId,
              'roster_initialized': 1,
              'legacy_target_state': 'active',
              'initialized_at': createdAt,
              'legacy_revoked_at': null,
              'updated_at': createdAt,
            });
        await fixture.db
            .insert('direct_contact_device_bindings', <String, Object?>{
              'contact_account_peer_id': contactAccountPeerId,
              'device_id': 'tc366-device-b',
              'verified_account_signing_public_key': contactSigningKey,
              'transport_peer_id': 'tc366-transport-b',
              'transport_public_key': 'tc366-transport-key-b',
              'device_ml_kem_public_key': 'mlkem-tc366-device-b',
              'binding_fingerprint': '366b' * 16,
              'state': 'active',
              'staged_at': createdAt,
              'decided_at': createdAt,
            });
        final snapshot =
            await (fixture.repo
                    as OutgoingDirectLinkedMediaBlobFanoutRepository)
                .readDirectContactFanoutSnapshotForMedia(contactAccountPeerId);
        expect(snapshot, isNotNull);
        expect(
          snapshot!.targets
              .map((target) => target.peerId)
              .toList(growable: false),
          const <String>[contactAccountPeerId, 'tc366-transport-b'],
          reason: 'the proof requires two independently addressed v114 rows',
        );

        List<DirectMediaBlobCustodyRow> rowsFor({
          required ConversationMessage parent,
          required MediaAttachment prepared,
        }) => <DirectMediaBlobCustodyRow>[
          for (final target in snapshot.targets)
            DirectMediaBlobCustodyRow(
              attachmentId: prepared.id,
              messageId: parent.id,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: target.peerId,
              contactAccountPeerId: contactAccountPeerId,
              recipientMlKemPublicKey: target.mlKemPublicKey,
              ciphertextRelativePath:
                  'direct_media_blob_custody_v1/'
                  '${prepared.contentHash}/${prepared.id}.blob',
              contentHash: prepared.contentHash!,
              ciphertextSize: 47,
              expiresAtMs: null,
              custodyRelayPeerId: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: createdAt,
              updatedAt: createdAt,
            ),
        ];

        final candidate = privateCandidate(
          suffix: 'tc366-private-fanout',
          contactPeerId: contactAccountPeerId,
        );
        await seedPrivatePending(candidate);
        final custodyRows = rowsFor(
          parent: candidate.parent,
          prepared: candidate.prepared,
        );
        final repository =
            fixture.repo
                as OutgoingDirectPrivateMediaBlobFanoutGenerationRepository;
        expect(
          repository.supportsOutgoingDirectPrivateMediaBlobFanoutGeneration,
          isTrue,
        );

        final staged = await repository
            .stageOutgoingDirectPrivateMediaBlobFanoutGeneration(
              expectedParent: candidate.parent,
              expectedAttachment: candidate.pending,
              preparedAttachment: candidate.prepared,
              custodyRows: custodyRows,
              contactAccountPeerId: contactAccountPeerId,
              expectedSnapshot: snapshot,
            );
        expect(staged.outcome, DirectMediaBlobGenerationStageOutcome.applied);
        expect(staged.attachments, hasLength(1));
        expect(staged.custodyRows, hasLength(2));
        expect(
          staged.custodyRows.map((row) => row.recipientPeerId).toSet(),
          snapshot.targets.map((target) => target.peerId).toSet(),
        );

        final durableRows = await fixture.db.query(
          kDirectMediaBlobCustodyTable,
          where: 'owner_lane = ? AND message_id = ?',
          whereArgs: <Object?>[
            MediaBlobCustodyOwnerLane.direct.dbValue,
            candidate.parent.id,
          ],
          orderBy: 'recipient_peer_id ASC',
        );
        expect(durableRows, hasLength(2));
        for (final target in snapshot.targets) {
          final durable = durableRows.singleWhere(
            (row) => row['recipient_peer_id'] == target.peerId,
          );
          expect(durable['attachment_id'], candidate.pending.id);
          expect(durable['contact_account_peer_id'], contactAccountPeerId);
          expect(durable['recipient_ml_kem_public_key'], target.mlKemPublicKey);
          expect(durable['content_hash'], candidate.prepared.contentHash);
          expect(durable['state'], 'outgoing_prepared');
        }
        final durableParent = (await fixture.db.query(
          'messages',
          columns: const <String>[
            'direct_media_custody_intent_id',
            'direct_event_fanout_generation_id',
          ],
          where: 'id = ?',
          whereArgs: <Object?>[candidate.parent.id],
        )).single;
        expect(
          durableParent['direct_media_custody_intent_id'],
          isNull,
          reason: 'private pending/completion authority must not mint v110',
        );
        expect(
          durableParent['direct_event_fanout_generation_id'],
          candidate.parent.id,
          reason: 'the v114 no-remint marker commits with the complete batch',
        );
        final keyName = mediaAttachmentEncryptionKeyStoreName(
          candidate.pending.id,
        );
        expect(
          await fixture.secureKeyStore.read(keyName),
          candidate.prepared.encryptionKeyBase64,
        );
        expect(
          (await fixture.rawAttachmentRow(
            candidate.pending.id,
          ))!['encryption_key_base64'],
          secureStoreReferenceForKey(keyName),
        );

        final writesBeforeReplay = fixture.secureKeyStore.writtenKeys.length;
        final replay = await repository
            .stageOutgoingDirectPrivateMediaBlobFanoutGeneration(
              expectedParent: candidate.parent,
              expectedAttachment: candidate.pending,
              preparedAttachment: candidate.prepared,
              custodyRows: custodyRows,
              contactAccountPeerId: contactAccountPeerId,
              expectedSnapshot: snapshot,
            );
        expect(
          replay.outcome,
          DirectMediaBlobGenerationStageOutcome.idempotent,
        );
        expect(replay.custodyRows, hasLength(2));
        expect(
          fixture.secureKeyStore.writtenKeys,
          hasLength(writesBeforeReplay),
          reason: 'exact winner adoption must not rewrite the stable key slot',
        );

        final incomplete = privateCandidate(
          suffix: 'tc366-private-incomplete',
          hashDigit: 'b',
          contactPeerId: contactAccountPeerId,
        );
        await seedPrivatePending(incomplete);
        final incompleteRows = rowsFor(
          parent: incomplete.parent,
          prepared: incomplete.prepared,
        );
        final refusedIncomplete = await repository
            .stageOutgoingDirectPrivateMediaBlobFanoutGeneration(
              expectedParent: incomplete.parent,
              expectedAttachment: incomplete.pending,
              preparedAttachment: incomplete.prepared,
              custodyRows: incompleteRows.take(1).toList(growable: false),
              contactAccountPeerId: contactAccountPeerId,
              expectedSnapshot: snapshot,
            );
        expect(
          refusedIncomplete.outcome,
          DirectMediaBlobGenerationStageOutcome.refused,
        );
        expect(
          await fixture.db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[incomplete.parent.id],
          ),
          isEmpty,
          reason: 'an incomplete A/B batch must publish neither sibling',
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(incomplete.pending.id),
          ),
          isFalse,
          reason: 'batch-shape refusal happens before the stable key write',
        );

        final tokenCandidate = privateCandidate(
          suffix: 'tc366-private-v110-cross',
          hashDigit: 'c',
          contactPeerId: contactAccountPeerId,
        );
        final tokenParent = tokenCandidate.parent.copyWith(
          directMediaCustodyIntentId: 'f' * 32,
        );
        await fixture.db.insert('messages', tokenParent.toMap());
        await fixture.db.insert(
          'media_attachments',
          tokenCandidate.pending.toMap(),
        );
        final refusedToken = await repository
            .stageOutgoingDirectPrivateMediaBlobFanoutGeneration(
              expectedParent: tokenParent,
              expectedAttachment: tokenCandidate.pending,
              preparedAttachment: tokenCandidate.prepared,
              custodyRows: rowsFor(
                parent: tokenParent,
                prepared: tokenCandidate.prepared,
              ),
              contactAccountPeerId: contactAccountPeerId,
              expectedSnapshot: snapshot,
            );
        expect(
          refusedToken.outcome,
          DirectMediaBlobGenerationStageOutcome.refused,
          reason: 'token-bearing authority is mutually exclusive with private',
        );
        expect(
          await fixture.db.query(
            kDirectMediaBlobCustodyTable,
            where: 'message_id = ?',
            whereArgs: <Object?>[tokenParent.id],
          ),
          isEmpty,
        );
        expect(
          await fixture.secureKeyStore.containsKey(
            mediaAttachmentEncryptionKeyStoreName(tokenCandidate.pending.id),
          ),
          isFalse,
        );
      },
    );

    test('TC-354-01c protected and view-once publish blob custody before first '
        'network', () async {
      // Coordinator tier over real SQLite: this is the exact production
      // seam the composer calls, so the ordering it proves — complete v111
      // durable BEFORE the LAN callback and BEFORE the sole strict relay
      // upload — is the same Barrier A the composer depends on.
      final tempDir = Directory.systemTemp.createTempSync('tc354_barrier_a_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      for (final shape
          in <({String suffix, String mode, String mime, String mediaType})>[
            (
              suffix: 'protected-image',
              mode: 'protected',
              mime: 'image/jpeg',
              mediaType: 'image',
            ),
            (
              suffix: 'protected-video',
              mode: 'protected',
              mime: 'video/mp4',
              mediaType: 'video',
            ),
            (
              suffix: 'viewonce-image',
              mode: 'view_once',
              mime: 'image/jpeg',
              mediaType: 'image',
            ),
          ]) {
        final candidate = privateCandidate(
          suffix: 'barrier-a-${shape.suffix}',
          mode: shape.mode,
          mime: shape.mime,
          mediaType: shape.mediaType,
        );
        await seedPrivatePending(candidate);
        final plaintext = File('${tempDir.path}/${shape.suffix}.bin')
          ..writeAsBytesSync(<int>[1, 2, 3, 4, 5]);

        final networkOrder = <String>[];
        var lanSawCompleteGeneration = false;
        var uploadSawCompleteGeneration = false;
        final blobRepository = fixture.repo as DirectMediaBlobCustodyRepository;

        Future<bool> generationIsDurablyComplete(String attachmentId) async {
          final rows = await blobRepository
              .loadDirectMediaBlobCustodyForMessage(candidate.parent.id);
          final durable = await fixture.repo.getAttachmentsForMessage(
            candidate.parent.id,
            owner: MediaOwnerLane.direct,
          );
          return rows.length == 1 &&
              rows.single.attachmentId == attachmentId &&
              rows.single.direction ==
                  DirectMediaBlobCustodyDirection.outgoing &&
              durable.length == 1 &&
              // The convention-owned pending row survives publication.
              durable.single.downloadStatus == 'upload_pending' &&
              durable.single.localPath == candidate.pending.localPath &&
              durable.single.contentHash != null &&
              durable.single.encryptionKeyBase64 != null &&
              durable.single.encryptionNonce != null;
        }

        final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
          repository: blobRepository,
          artifactStore: DirectMediaBlobArtifactStore(
            documentsDirectoryProvider: () async => tempDir,
          ),
          prepareArtifact:
              ({required Bridge bridge, required String localFilePath}) async {
                final ciphertextPath = '$localFilePath.enc';
                final bytes = File(localFilePath).readAsBytesSync();
                File(ciphertextPath).writeAsBytesSync(bytes, flush: true);
                return EncryptedMediaArtifact(
                  encryptedPath: ciphertextPath,
                  keyBase64: 'tc354-barrier-a-key-${shape.suffix}',
                  nonce: 'tc354-barrier-a-nonce-${shape.suffix}',
                  scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  contentHash: sha256.convert(bytes).toString(),
                  plaintextSize: bytes.length,
                );
              },
          strictUpload:
              ({
                required bridge,
                required attachmentId,
                required recipientPeerId,
                required ciphertextPath,
                required contentHash,
                required ciphertextSize,
              }) async {
                uploadSawCompleteGeneration = await generationIsDurablyComplete(
                  attachmentId,
                );
                networkOrder.add('strict-upload');
                expect(
                  sha256
                      .convert(File(ciphertextPath).readAsBytesSync())
                      .toString(),
                  contentHash,
                );
                return <String, dynamic>{
                  'ok': true,
                  'id': attachmentId,
                  'storeStatus': 'stored',
                  'custodyKind': 'direct_media_blob_v1',
                  'custodyContract': 'ack_or_expiry_v1',
                  'contentHash': contentHash,
                  'size': ciphertextSize,
                  'mime': 'application/octet-stream',
                  'expiresAtMs': 2000000000000,
                  'custodyRelayPeerId': 'relay-354-barrier-a',
                };
              },
        );

        final result = await coordinator.prepareAndUploadPrivate(
          bridge: RecordingFakeBridge(),
          identityPeerId: candidate.parent.senderPeerId,
          recipientPeerId: candidate.parent.contactPeerId,
          expectedParent: candidate.parent,
          source: PreparedDirectMediaBlobSource(
            attachment: candidate.pending,
            plaintextPath: plaintext.path,
          ),
          onGenerationReady: (artifacts) async {
            lanSawCompleteGeneration = await generationIsDurablyComplete(
              artifacts.single.attachment.id,
            );
            networkOrder.add('lan');
          },
        );

        expect(result.isComplete, isTrue, reason: shape.suffix);
        expect(result.attachments, hasLength(1));
        expect(result.attachments.single.blobCustody?.isValid, isTrue);
        expect(
          lanSawCompleteGeneration,
          isTrue,
          reason: 'the LAN acceleration callback must see complete v111',
        );
        expect(
          uploadSawCompleteGeneration,
          isTrue,
          reason: 'the strict relay upload must see complete v111',
        );
        expect(
          networkOrder,
          <String>['lan', 'strict-upload'],
          reason: 'LAN is acceleration only and never cancels strict custody',
        );
        final rows = await blobRepository.loadDirectMediaBlobCustodyForMessage(
          candidate.parent.id,
        );
        expect(rows.single.state, DirectMediaBlobCustodyState.outgoingStored);
      }

      // View-Once video is outside the producer matrix: it refuses before
      // encryption, before any durable publication, and before any network.
      final refusedCandidate = privateCandidate(
        suffix: 'barrier-a-viewonce-video',
        mode: 'view_once',
        mime: 'video/mp4',
        mediaType: 'video',
      );
      await seedPrivatePending(refusedCandidate);
      var prepareCalls = 0;
      var uploadCalls = 0;
      final refusingCoordinator = PreparedDirectMediaBlobCustodyCoordinator(
        repository: fixture.repo as DirectMediaBlobCustodyRepository,
        artifactStore: DirectMediaBlobArtifactStore(
          documentsDirectoryProvider: () async => tempDir,
        ),
        prepareArtifact:
            ({required Bridge bridge, required String localFilePath}) async {
              prepareCalls++;
              throw StateError('encryption must not run');
            },
        strictUpload:
            ({
              required bridge,
              required attachmentId,
              required recipientPeerId,
              required ciphertextPath,
              required contentHash,
              required ciphertextSize,
            }) async {
              uploadCalls++;
              return <String, dynamic>{'ok': false};
            },
      );
      final refused = await refusingCoordinator.prepareAndUploadPrivate(
        bridge: RecordingFakeBridge(),
        identityPeerId: refusedCandidate.parent.senderPeerId,
        recipientPeerId: refusedCandidate.parent.contactPeerId,
        expectedParent: refusedCandidate.parent,
        source: PreparedDirectMediaBlobSource(
          attachment: refusedCandidate.pending,
          plaintextPath: '${tempDir.path}/never.bin',
        ),
      );
      expect(refused.isComplete, isFalse);
      expect(prepareCalls, 0, reason: 'no encryption before the matrix gate');
      expect(uploadCalls, 0, reason: 'no network before the matrix gate');
      expect(
        await (fixture.repo as DirectMediaBlobCustodyRepository)
            .loadDirectMediaBlobCustodyForMessage(refusedCandidate.parent.id),
        isEmpty,
      );
    });

    test('TC-354-04b private strict receive key CAS is exact', () async {
      const senderPeerId = 'tc354-repo-incoming-peer';
      const messageId = 'tc354-repo-incoming';
      const attachmentId = 'tc354-repo-incoming-attachment';
      const nowMs = 1900000000000;
      final repo =
          fixture.repo as IncomingDirectPrivateMediaBlobCustodyRepository;
      expect(repo.supportsIncomingDirectPrivateMediaBlobCustody, isTrue);

      final parent = ConversationMessage(
        id: messageId,
        contactPeerId: senderPeerId,
        senderPeerId: senderPeerId,
        text: '',
        timestamp: createdAt,
        status: 'delivered',
        isIncoming: true,
        createdAt: createdAt,
        dedupKey: messageId,
        privateMediaPolicy: const PrivateMediaPolicy.viewOnce(),
        privateMediaState: PrivateMediaLifecycleState.available,
        privateMediaReceivedAtMs: nowMs,
        privateMediaClockHighWaterMs: nowMs,
      );
      const commitment = DirectMediaBlobCustodyCommitment(
        contentHash:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        ciphertextSize: 4096,
        expiresAtMs: nowMs + 600000,
      );
      final attachment = MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 3000,
        mediaType: 'image',
        downloadStatus: 'pending',
        createdAt: createdAt,
        ownerLane: MediaOwnerLane.direct,
        contentHash: commitment.contentHash,
        encryptionKeyBase64: 'tc354-incoming-raw-key',
        encryptionNonce: 'tc354-incoming-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        blobCustody: commitment,
      );
      final custody = DirectMediaBlobCustodyRow(
        attachmentId: attachmentId,
        messageId: messageId,
        direction: DirectMediaBlobCustodyDirection.incoming,
        state: DirectMediaBlobCustodyState.incomingCommitted,
        inboxCustodyIncarnationId: null,
        recipientPeerId: null,
        ciphertextRelativePath: null,
        contentHash: commitment.contentHash,
        ciphertextSize: commitment.ciphertextSize,
        expiresAtMs: commitment.expiresAtMs,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final applied = await repo.stageIncomingDirectPrivateMediaBlobCustody(
        message: parent,
        attachment: attachment,
        custodyRow: custody,
      );
      expect(
        applied.outcome,
        IncomingDirectMediaBlobCustodyStageOutcome.applied,
      );
      expect(applied.outcome.authorizesPublication, isTrue);
      expect(
        await fixture.secureKeyStore.read(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
        'tc354-incoming-raw-key',
      );
      expect(
        (await fixture.db.query(
          'media_attachments',
          where: 'id = ?',
          whereArgs: <Object?>[attachmentId],
        )).single['encryption_key_base64'],
        secureStoreReferenceForKey(
          mediaAttachmentEncryptionKeyStoreName(attachmentId),
        ),
      );

      // A refused crossed replay compensates its raw key write and leaves the
      // durable projection untouched.
      const otherId = 'tc354-repo-incoming-crossed';
      final writesBefore = fixture.secureKeyStore.writtenKeys.length;
      final crossed = await repo.stageIncomingDirectPrivateMediaBlobCustody(
        message: parent.copyWith(id: otherId),
        attachment: attachment.copyWith(id: otherId, messageId: otherId),
        custodyRow: DirectMediaBlobCustodyRow(
          attachmentId: otherId,
          messageId: otherId,
          direction: DirectMediaBlobCustodyDirection.incoming,
          state: DirectMediaBlobCustodyState.incomingCommitted,
          inboxCustodyIncarnationId: null,
          recipientPeerId: null,
          ciphertextRelativePath: null,
          contentHash: commitment.contentHash,
          ciphertextSize: commitment.ciphertextSize,
          // Drifted expiry: the persisted fingerprint can no longer match its
          // commitment, so the stage must refuse all-or-zero.
          expiresAtMs: commitment.expiresAtMs + 1,
          custodyRelayPeerId: null,
          lastAttemptAt: null,
          nextAttemptAt: null,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );
      expect(
        crossed.outcome,
        IncomingDirectMediaBlobCustodyStageOutcome.refused,
        reason: 'a fingerprint that does not match its commitment refuses',
      );
      expect(
        await fixture.secureKeyStore.read(
          mediaAttachmentEncryptionKeyStoreName(otherId),
        ),
        isNull,
      );
      expect(fixture.secureKeyStore.writtenKeys, hasLength(writesBefore + 1));
    });

    test('TC-355-04d production blob drain predicate retains private committed '
        'rows without download', () {
      // GREEN-only preservation sentinel: this invokes the SAME callable
      // predicate the production drain callback uses. It never copies its
      // body, so unhooking production from it cannot leave this green.
      const senderPeerId = 'tc355-drain-peer';
      ConversationMessage incoming({
        required String id,
        required PrivateMediaPolicy policy,
        PrivateMediaLifecycleState state = PrivateMediaLifecycleState.none,
        String? deletedAt,
        String? hiddenAt,
        bool isIncoming = true,
      }) => ConversationMessage(
        id: id,
        contactPeerId: senderPeerId,
        senderPeerId: senderPeerId,
        text: '',
        timestamp: createdAt,
        status: 'delivered',
        isIncoming: isIncoming,
        createdAt: createdAt,
        dedupKey: id,
        deletedAt: deletedAt,
        deletedByPeerId: deletedAt == null ? null : senderPeerId,
        hiddenAt: hiddenAt,
        privateMediaPolicy: policy,
        privateMediaState: state,
      );

      // Every redacted policy is retained WITHOUT network.
      for (final policy in <PrivateMediaPolicy>[
        const PrivateMediaPolicy.protected(),
        const PrivateMediaPolicy.viewOnce(),
        PrivateMediaPolicy.disappearing(3600),
      ]) {
        expect(
          directMediaBlobDrainMayDownloadIncomingParent(
            incoming(
              id: 'tc355-drain-${policy.mode.wireValue}',
              policy: policy,
              state: PrivateMediaLifecycleState.available,
            ),
          ),
          isFalse,
          reason: '${policy.mode.wireValue} stays explicit-intent only',
        );
      }
      // Unchanged ordinary behavior: strict ordinary media still converges.
      expect(
        directMediaBlobDrainMayDownloadIncomingParent(
          incoming(
            id: 'tc355-drain-ordinary',
            policy: const PrivateMediaPolicy.ordinary(),
          ),
        ),
        isTrue,
      );
      // A missing, outgoing, tombstoned or hidden parent never downloads.
      expect(directMediaBlobDrainMayDownloadIncomingParent(null), isFalse);
      expect(
        directMediaBlobDrainMayDownloadIncomingParent(
          incoming(
            id: 'tc355-drain-outgoing',
            policy: const PrivateMediaPolicy.ordinary(),
            isIncoming: false,
          ),
        ),
        isFalse,
      );
      expect(
        directMediaBlobDrainMayDownloadIncomingParent(
          incoming(
            id: 'tc355-drain-deleted',
            policy: const PrivateMediaPolicy.ordinary(),
            deletedAt: createdAt,
          ),
        ),
        isFalse,
      );
      expect(
        directMediaBlobDrainMayDownloadIncomingParent(
          incoming(
            id: 'tc355-drain-hidden',
            policy: const PrivateMediaPolicy.ordinary(),
            hiddenAt: createdAt,
          ),
        ),
        isFalse,
      );
    });
  });

  group('Plan 362 direct linked-media blob fanout repository authority', () {
    const contactAccount = 'tc362-contact-account';
    const contactSigningKey = 'tc362-contact-signing-key';
    const seededAt = '2026-08-10T09:00:00.000Z';

    /// Seeds a persisted nonblocked fanout contact exactly like production
    /// linking does: contact row + initialized roster metadata + one active
    /// v112 binding row per linked device, then reads the REAL snapshot back
    /// through the repository's own fanout reader.
    Future<DirectContactFanoutSnapshot> seedFanoutContact({
      int linkedDeviceCount = 1,
      bool legacyRevoked = false,
    }) async {
      await fixture.db.insert('contacts', <String, Object?>{
        'peer_id': contactAccount,
        'public_key': contactSigningKey,
        'rendezvous': '/dns4/relay.example.com/tcp/443/wss/p2p/relay-id',
        'username': 'TC362 Contact',
        'signature': 'sig-base64',
        'scanned_at': seededAt,
        'ml_kem_public_key': 'mlkem-legacy-account',
      });
      await fixture.db
          .insert('direct_contact_device_roster_metadata', <String, Object?>{
            'contact_account_peer_id': contactAccount,
            'roster_initialized': 1,
            'legacy_target_state': legacyRevoked ? 'revoked' : 'active',
            'initialized_at': seededAt,
            'legacy_revoked_at': legacyRevoked ? seededAt : null,
            'updated_at': seededAt,
          });
      for (var index = 0; index < linkedDeviceCount; index++) {
        final deviceId = 'device-${index.toString().padLeft(2, '0')}';
        await fixture.db.insert(
          'direct_contact_device_bindings',
          <String, Object?>{
            'contact_account_peer_id': contactAccount,
            'device_id': deviceId,
            'verified_account_signing_public_key': contactSigningKey,
            'transport_peer_id': 'peer-transport-$deviceId',
            'transport_public_key': 'transport-key-$deviceId',
            'device_ml_kem_public_key': 'mlkem-$deviceId',
            'binding_fingerprint': index.toRadixString(16).padLeft(4, '0') * 16,
            'state': 'active',
            'staged_at': seededAt,
            'decided_at': seededAt,
          },
        );
      }
      final snapshot =
          await (fixture.repo as OutgoingDirectLinkedMediaBlobFanoutRepository)
              .readDirectContactFanoutSnapshotForMedia(contactAccount);
      expect(snapshot, isNotNull);
      expect(
        snapshot!.targets,
        hasLength(linkedDeviceCount + (legacyRevoked ? 0 : 1)),
      );
      return snapshot;
    }

    /// Builds the v110-token parent plus its complete prepared linked-fanout
    /// candidate set: one prepared attachment per id and one LINKED custody
    /// row per (attachment, snapshot target) carrying that target's exact
    /// persisted ML-KEM key (copying the file's single-target
    /// stageOutgoingDirectMediaBlobGeneration fixtures).
    Future<
      ({
        ConversationMessage parent,
        List<MediaAttachment> pending,
        List<MediaAttachment> prepared,
        List<DirectMediaBlobCustodyRow> custodyRows,
      })
    >
    prepareLinkedGeneration({
      required String messageId,
      required DirectContactFanoutSnapshot snapshot,
      required int attachmentCount,
    }) async {
      final attachmentIds = List<String>.generate(
        attachmentCount,
        (index) => '$messageId-att-${index.toString().padLeft(2, '0')}',
      );
      final parent = ConversationMessage(
        id: messageId,
        contactPeerId: contactAccount,
        senderPeerId: 'tc362-local',
        text: 'linked media caption',
        timestamp: seededAt,
        status: 'sending',
        isIncoming: false,
        createdAt: seededAt,
        directMediaCustodyIntentId: computeDirectMediaCustodyIntentId(
          messageId: messageId,
          attachmentIds: attachmentIds,
        ),
      );
      await fixture.messageRepo.saveMessage(parent);
      final pending = <MediaAttachment>[];
      final prepared = <MediaAttachment>[];
      final custodyRows = <DirectMediaBlobCustodyRow>[];
      for (var index = 0; index < attachmentIds.length; index++) {
        final attachmentId = attachmentIds[index];
        final attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 40 + index,
          mediaType: 'image',
          localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
          downloadStatus: 'upload_pending',
          createdAt: seededAt,
          ownerLane: MediaOwnerLane.direct,
        );
        await fixture.repo.saveAttachment(
          attachment,
          owner: MediaOwnerLane.direct,
        );
        final contentHash = ((index % 9) + 1).toString() * 64;
        pending.add(attachment);
        prepared.add(
          attachment.copyWith(
            contentHash: contentHash,
            encryptionKeyBase64: 'tc362-raw-key-$attachmentId',
            encryptionNonce: 'tc362-nonce-$attachmentId',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        );
        // Every target shares the ONE canonical ciphertext; only the
        // addressing columns are per-target.
        for (final target in snapshot.targets) {
          custodyRows.add(
            DirectMediaBlobCustodyRow(
              attachmentId: attachmentId,
              messageId: messageId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: target.peerId,
              contactAccountPeerId: contactAccount,
              recipientMlKemPublicKey: target.mlKemPublicKey,
              ciphertextRelativePath:
                  'direct_media_blob_custody_v1/$contentHash/$attachmentId.blob',
              contentHash: contentHash,
              ciphertextSize: 64 + index,
              expiresAtMs: null,
              custodyRelayPeerId: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: seededAt,
              updatedAt: seededAt,
            ),
          );
        }
      }
      return (
        parent: parent,
        pending: pending,
        prepared: prepared,
        custodyRows: custodyRows,
      );
    }

    Future<List<Map<String, Object?>>> durableFanoutRows(String messageId) =>
        fixture.db.query(
          kDirectMediaBlobCustodyTable,
          where: 'message_id = ?',
          whereArgs: <Object?>[messageId],
          orderBy: 'attachment_id ASC, recipient_peer_id ASC',
        );

    Future<Object?> durableMarker(String messageId) async =>
        ((await fixture.db.query(
          'messages',
          columns: const <String>['direct_event_fanout_generation_id'],
          where: 'id = ?',
          whereArgs: <Object?>[messageId],
        )).single)['direct_event_fanout_generation_id'];

    test(
      'TC-362-02a linked fanout generation stages N×M rows once with secure-key discipline',
      () async {
        final snapshot = await seedFanoutContact();
        expect(
          snapshot.targets.map((target) => target.peerId).toList(),
          const <String>[contactAccount, 'peer-transport-device-00'],
          reason: 'legacy-primary target first, then stable device order',
        );
        final fanoutRepository =
            fixture.repo as OutgoingDirectLinkedMediaBlobFanoutRepository;
        expect(fanoutRepository.supportsDirectLinkedMediaBlobFanout, isTrue);

        const messageId = 'tc362-02a-linked-generation';
        final generation = await prepareLinkedGeneration(
          messageId: messageId,
          snapshot: snapshot,
          attachmentCount: 2,
        );
        final staged = await fanoutRepository
            .stageOutgoingDirectLinkedMediaBlobFanoutGeneration(
              expectedParent: generation.parent,
              expectedAttachments: generation.pending,
              preparedAttachments: generation.prepared,
              custodyRows: generation.custodyRows,
              contactAccountPeerId: contactAccount,
              expectedSnapshot: snapshot,
            );
        expect(staged.outcome, DirectMediaBlobGenerationStageOutcome.applied);
        expect(staged.custodyRows, hasLength(4));
        expect(staged.attachments, hasLength(2));

        final durableRows = await durableFanoutRows(messageId);
        expect(durableRows, hasLength(4), reason: '2 attachments x 2 targets');
        for (final expected in generation.custodyRows) {
          final durable = durableRows.singleWhere(
            (row) =>
                row['attachment_id'] == expected.attachmentId &&
                row['recipient_peer_id'] == expected.recipientPeerId,
          );
          expect(durable['contact_account_peer_id'], contactAccount);
          expect(
            durable['recipient_ml_kem_public_key'],
            expected.recipientMlKemPublicKey,
            reason: 'each row persists its snapshot target key exactly',
          );
          expect(durable['state'], 'outgoing_prepared');
          expect(durable['content_hash'], expected.contentHash);
        }
        expect(
          await durableMarker(messageId),
          messageId,
          reason: 'the no-remint marker commits WITH the rows',
        );
        for (final attachment in generation.prepared) {
          final keyName = mediaAttachmentEncryptionKeyStoreName(attachment.id);
          expect(
            await fixture.secureKeyStore.read(keyName),
            attachment.encryptionKeyBase64,
          );
          expect(
            (await rawRow(attachment.id))!['encryption_key_base64'],
            secureStoreReferenceForKey(keyName),
            reason: 'only the stable reference reaches SQLite',
          );
        }

        // Byte-exact replay adopts the durable winner without re-staging or
        // rewriting the stable secure slots.
        final writesBeforeReplay = fixture.secureKeyStore.writtenKeys.length;
        final replay = await fanoutRepository
            .stageOutgoingDirectLinkedMediaBlobFanoutGeneration(
              expectedParent: generation.parent,
              expectedAttachments: generation.pending,
              preparedAttachments: generation.prepared,
              custodyRows: generation.custodyRows,
              contactAccountPeerId: contactAccount,
              expectedSnapshot: snapshot,
            );
        expect(
          replay.outcome,
          DirectMediaBlobGenerationStageOutcome.idempotent,
        );
        expect(replay.custodyRows, hasLength(4));
        expect(await durableFanoutRows(messageId), hasLength(4));
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeReplay,
          reason: 'winner adoption stages reference-only candidate rows',
        );

        // Refused shape 1: dropping one custody row breaks the complete
        // targets x attachments batch and leaves zero rows and zero
        // secure-store mutation.
        const droppedId = 'tc362-02a-dropped-row';
        final dropped = await prepareLinkedGeneration(
          messageId: droppedId,
          snapshot: snapshot,
          attachmentCount: 2,
        );
        final writesBeforeDropped = fixture.secureKeyStore.writtenKeys.length;
        final refusedDrop = await fanoutRepository
            .stageOutgoingDirectLinkedMediaBlobFanoutGeneration(
              expectedParent: dropped.parent,
              expectedAttachments: dropped.pending,
              preparedAttachments: dropped.prepared,
              custodyRows: dropped.custodyRows.sublist(
                0,
                dropped.custodyRows.length - 1,
              ),
              contactAccountPeerId: contactAccount,
              expectedSnapshot: snapshot,
            );
        expect(
          refusedDrop.outcome,
          DirectMediaBlobGenerationStageOutcome.refused,
        );
        expect(await durableFanoutRows(droppedId), isEmpty);
        expect(await durableMarker(droppedId), isNull);
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeDropped,
          reason: 'an incomplete batch is refused before any key write',
        );
        for (final attachment in dropped.prepared) {
          expect(
            await fixture.secureKeyStore.containsKey(
              mediaAttachmentEncryptionKeyStoreName(attachment.id),
            ),
            isFalse,
          );
        }

        // Refused shape 2: one row whose persisted recipient key drifts from
        // the snapshot target key refuses INSIDE the CAS, after the raw keys
        // were staged — compensation must restore the secure store exactly
        // (mirrors TC-347-02c's stable-slot discipline).
        const crossedId = 'tc362-02a-crossed-key';
        final crossed = await prepareLinkedGeneration(
          messageId: crossedId,
          snapshot: snapshot,
          attachmentCount: 2,
        );
        final crossedRows = crossed.custodyRows.toList();
        final crossedTail = crossedRows.last;
        crossedRows[crossedRows.length - 1] = DirectMediaBlobCustodyRow(
          attachmentId: crossedTail.attachmentId,
          messageId: crossedTail.messageId,
          direction: crossedTail.direction,
          state: crossedTail.state,
          inboxCustodyIncarnationId: crossedTail.inboxCustodyIncarnationId,
          recipientPeerId: crossedTail.recipientPeerId,
          contactAccountPeerId: crossedTail.contactAccountPeerId,
          recipientMlKemPublicKey: 'mlkem-attacker-selected',
          ciphertextRelativePath: crossedTail.ciphertextRelativePath,
          contentHash: crossedTail.contentHash,
          ciphertextSize: crossedTail.ciphertextSize,
          expiresAtMs: crossedTail.expiresAtMs,
          custodyRelayPeerId: crossedTail.custodyRelayPeerId,
          lastAttemptAt: crossedTail.lastAttemptAt,
          nextAttemptAt: crossedTail.nextAttemptAt,
          createdAt: crossedTail.createdAt,
          updatedAt: crossedTail.updatedAt,
        );
        final writesBeforeCrossed = fixture.secureKeyStore.writtenKeys.length;
        final refusedCrossed = await fanoutRepository
            .stageOutgoingDirectLinkedMediaBlobFanoutGeneration(
              expectedParent: crossed.parent,
              expectedAttachments: crossed.pending,
              preparedAttachments: crossed.prepared,
              custodyRows: crossedRows,
              contactAccountPeerId: contactAccount,
              expectedSnapshot: snapshot,
            );
        expect(
          refusedCrossed.outcome,
          DirectMediaBlobGenerationStageOutcome.refused,
        );
        expect(await durableFanoutRows(crossedId), isEmpty);
        expect(await durableMarker(crossedId), isNull);
        expect(
          fixture.secureKeyStore.writtenKeys.length,
          writesBeforeCrossed + 2,
          reason: 'the losing raw keys were staged before the CAS refused',
        );
        for (final attachment in crossed.prepared) {
          expect(
            await fixture.secureKeyStore.containsKey(
              mediaAttachmentEncryptionKeyStoreName(attachment.id),
            ),
            isFalse,
            reason: 'compensation restores the empty stable slot',
          );
        }
      },
    );

    test(
      'TC-362-02a the 170-row generation proves no hidden page cap',
      () async {
        final snapshot = await seedFanoutContact(
          linkedDeviceCount: 17,
          legacyRevoked: true,
        );
        expect(snapshot.targets, hasLength(17));
        final fanoutRepository =
            fixture.repo as OutgoingDirectLinkedMediaBlobFanoutRepository;

        const messageId = 'tc362-02a-170-rows';
        final generation = await prepareLinkedGeneration(
          messageId: messageId,
          snapshot: snapshot,
          attachmentCount: 10,
        );
        expect(generation.custodyRows, hasLength(170));
        final staged = await fanoutRepository
            .stageOutgoingDirectLinkedMediaBlobFanoutGeneration(
              expectedParent: generation.parent,
              expectedAttachments: generation.pending,
              preparedAttachments: generation.prepared,
              custodyRows: generation.custodyRows,
              contactAccountPeerId: contactAccount,
              expectedSnapshot: snapshot,
            );
        expect(staged.outcome, DirectMediaBlobGenerationStageOutcome.applied);
        expect(staged.custodyRows, hasLength(170));

        final reloaded =
            await (fixture.repo as DirectMediaBlobCustodyRepository)
                .loadDirectMediaBlobCustodyForMessage(messageId);
        expect(
          reloaded,
          hasLength(170),
          reason:
              'the message-scoped loader must return the COMPLETE '
              'generation — a hidden 50-row page cap would strand targets',
        );
        expect(
          reloaded
              .map((row) => '${row.attachmentId}\\u0000${row.recipientPeerId}')
              .toSet(),
          hasLength(170),
          reason: 'every (attachment, target) pair loads back exactly once',
        );
      },
    );

    test(
      'TC-362-02b crash after upload reopens the complete persisted generation and binds the full v108 batch atomically',
      () async {
        final snapshot = await seedFanoutContact();
        final fanoutRepository =
            fixture.repo as OutgoingDirectLinkedMediaBlobFanoutRepository;
        final custodyRepository =
            fixture.repo as DirectMediaBlobCustodyRepository;
        final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        const senderTransportPeerId = 'tc362-linked-sender-transport';

        String initialEnvelope(String messageId, String suffix) =>
            jsonEncode(<String, Object?>{
              'type': 'chat_message',
              'version': '2',
              'id': messageId,
              'senderPeerId': senderTransportPeerId,
              'encrypted': <String, String>{
                'kem': 'kem-$suffix',
                'ciphertext': 'cipher-$suffix',
                'nonce': 'nonce-$suffix',
              },
            });

        /// Stages a complete linked generation, then fabricates the
        /// crash-after-upload state: every (attachment, target) row
        /// transitions to `outgoing_stored` with a PER-TARGET relay receipt,
        /// so each target owns a distinct manifest hash / earliest expiry.
        Future<
          ({
            ConversationMessage parent,
            List<MediaAttachment> completed,
            Map<String, List<DirectMediaBlobCustodyRow>> storedByTarget,
            List<DirectMediaFanoutTargetBinding> bindings,
          })
        >
        publishStoredGeneration(String messageId) async {
          final generation = await prepareLinkedGeneration(
            messageId: messageId,
            snapshot: snapshot,
            attachmentCount: 2,
          );
          final staged = await fanoutRepository
              .stageOutgoingDirectLinkedMediaBlobFanoutGeneration(
                expectedParent: generation.parent,
                expectedAttachments: generation.pending,
                preparedAttachments: generation.prepared,
                custodyRows: generation.custodyRows,
                contactAccountPeerId: contactAccount,
                expectedSnapshot: snapshot,
              );
          expect(staged.outcome, DirectMediaBlobGenerationStageOutcome.applied);
          final expiryByTarget = <String, int>{
            for (var index = 0; index < snapshot.targets.length; index++)
              snapshot.targets[index].peerId:
                  nowMs +
                  const Duration(days: 7).inMilliseconds +
                  index * 60000,
          };
          final storedByTarget = <String, List<DirectMediaBlobCustodyRow>>{};
          for (final row in staged.custodyRows) {
            final next = row.copyWith(
              state: DirectMediaBlobCustodyState.outgoingStored,
              expiresAtMs: expiryByTarget[row.recipientPeerId],
              custodyRelayPeerId: 'peer-relay',
              updatedAt: '2026-08-10T09:05:00.000Z',
            );
            expect(
              await custodyRepository.transitionDirectMediaBlobCustodyIfExact(
                expected: row,
                next: next,
              ),
              isTrue,
            );
            storedByTarget
                .putIfAbsent(next.recipientPeerId!, () => [])
                .add(next);
          }
          final bindings = <DirectMediaFanoutTargetBinding>[
            for (final target in snapshot.targets)
              () {
                final rows = storedByTarget[target.peerId]!.toList()
                  ..sort(
                    (left, right) =>
                        left.attachmentId.compareTo(right.attachmentId),
                  );
                final manifest = rows
                    .map(
                      (row) => DirectMediaBlobManifestProjection(
                        attachmentId: row.attachmentId,
                        commitment: DirectMediaBlobCustodyCommitment(
                          contentHash: row.contentHash,
                          ciphertextSize: row.ciphertextSize,
                          expiresAtMs: row.expiresAtMs!,
                        ),
                      ),
                    )
                    .toList(growable: false);
                return DirectMediaFanoutTargetBinding(
                  recipientPeerId: target.peerId,
                  recipientMlKemPublicKey: target.mlKemPublicKey,
                  wireEnvelope: initialEnvelope(messageId, target.peerId),
                  wireMediaBlobManifestHash: computeDirectMediaBlobManifestHash(
                    manifest,
                  ),
                  wireMediaBlobExpiresAtMs: earliestDirectMediaBlobExpiryMs(
                    manifest,
                  ),
                );
              }(),
          ];
          // The strict fanout coordinator completes the stage's COMMITTED
          // projection in place: status flips to done while the published
          // convention-pending path is retained, and the projection carries
          // the LEGACY-PRIMARY (first) target's blob commitment as its
          // canonical wire binding.
          final primaryRows = <String, DirectMediaBlobCustodyRow>{
            for (final row in storedByTarget[snapshot.targets.first.peerId]!)
              row.attachmentId: row,
          };
          final completed = staged.attachments
              .map(
                (attachment) => attachment.copyWith(
                  downloadStatus: 'done',
                  blobCustody: DirectMediaBlobCustodyCommitment(
                    contentHash: primaryRows[attachment.id]!.contentHash,
                    ciphertextSize: primaryRows[attachment.id]!.ciphertextSize,
                    expiresAtMs: primaryRows[attachment.id]!.expiresAtMs!,
                  ),
                ),
              )
              .toList(growable: false);
          return (
            parent: generation.parent,
            completed: completed,
            storedByTarget: storedByTarget,
            bindings: bindings,
          );
        }

        const messageId = 'tc362-02b-bind';
        final published = await publishStoredGeneration(messageId);
        expect(
          published.bindings[0].wireMediaBlobManifestHash,
          isNot(published.bindings[1].wireMediaBlobManifestHash),
          reason: 'per-target receipts must produce per-target manifests',
        );

        final expectedParent = published.parent.copyWith(
          directEventFanoutGenerationId: messageId,
        );
        expect(
          senderTransportPeerId,
          isNot(expectedParent.senderPeerId),
          reason:
              'a linked secondary authenticates the outer envelope with its '
              'physical transport while the durable parent remains logical',
        );
        final stagedAttempt = expectedParent.copyWith(
          wireEnvelope: published.bindings.first.wireEnvelope,
          directMediaCustodyIntentId: null,
          media: published.completed,
        );
        final bound = await fanoutRepository
            .stageOutgoingDirectMediaFanoutInboxCustody(
              expected: expectedParent,
              staged: stagedAttempt,
              attachments: published.completed,
              senderTransportPeerId: senderTransportPeerId,
              contactAccountPeerId: contactAccount,
              authority: DirectMediaFanoutStageAuthority.currentRosterSnapshot,
              expectedSnapshot: snapshot,
              targetBindings: published.bindings,
            );
        expect(bound.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(bound.authorizesTransport, isTrue);
        expect(bound.custodyRows, hasLength(2));

        final v108Rows = await fixture.db.query(
          'direct_inbox_custody_outbox',
          where: 'message_id = ?',
          whereArgs: const <Object?>[messageId],
          orderBy: 'recipient_peer_id ASC',
        );
        expect(v108Rows, hasLength(2), reason: 'one v108 sibling per target');
        for (final binding in published.bindings) {
          final sibling = v108Rows.singleWhere(
            (row) => row['recipient_peer_id'] == binding.recipientPeerId,
          );
          expect(sibling['contact_account_peer_id'], contactAccount);
          expect(
            sibling['incarnation_id'],
            computeDirectEventFanoutIncarnation(
              messageId: messageId,
              recipientPeerId: binding.recipientPeerId,
            ),
            reason: 'deterministic per-(message,target) incarnation',
          );
          expect(sibling['wire_envelope'], binding.wireEnvelope);
          expect(
            sibling['media_blob_manifest_hash'],
            binding.wireMediaBlobManifestHash,
            reason: 'each sibling binds ONLY its own target manifest',
          );
          expect(
            sibling['media_blob_expires_at_ms'],
            binding.wireMediaBlobExpiresAtMs,
          );
        }
        final boundV111 = await custodyRepository
            .loadDirectMediaBlobCustodyForMessage(messageId);
        expect(boundV111, hasLength(4));
        for (final row in boundV111) {
          expect(
            row.inboxCustodyIncarnationId,
            computeDirectEventFanoutIncarnation(
              messageId: messageId,
              recipientPeerId: row.recipientPeerId!,
            ),
            reason: 'every v111 row binds to its OWN target incarnation',
          );
        }
        final durableParent = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[messageId],
        )).single;
        expect(
          durableParent['direct_media_custody_intent_id'],
          isNull,
          reason: 'the v110 token is consumed with the batch',
        );
        expect(
          durableParent['wire_envelope'],
          published.bindings.first.wireEnvelope,
          reason: 'the canonical witness is the FIRST target envelope',
        );
        expect(durableParent['direct_event_fanout_generation_id'], messageId);

        // CROSSED manifests: swapping the two targets' manifest hashes must
        // refuse ALL-ZERO — no sibling, no token consumption, no v111 bind.
        const crossedId = 'tc362-02b-crossed';
        final crossed = await publishStoredGeneration(crossedId);
        final crossedBindings = <DirectMediaFanoutTargetBinding>[
          DirectMediaFanoutTargetBinding(
            recipientPeerId: crossed.bindings[0].recipientPeerId,
            recipientMlKemPublicKey:
                crossed.bindings[0].recipientMlKemPublicKey,
            wireEnvelope: crossed.bindings[0].wireEnvelope,
            wireMediaBlobManifestHash:
                crossed.bindings[1].wireMediaBlobManifestHash,
            wireMediaBlobExpiresAtMs:
                crossed.bindings[0].wireMediaBlobExpiresAtMs,
          ),
          DirectMediaFanoutTargetBinding(
            recipientPeerId: crossed.bindings[1].recipientPeerId,
            recipientMlKemPublicKey:
                crossed.bindings[1].recipientMlKemPublicKey,
            wireEnvelope: crossed.bindings[1].wireEnvelope,
            wireMediaBlobManifestHash:
                crossed.bindings[0].wireMediaBlobManifestHash,
            wireMediaBlobExpiresAtMs:
                crossed.bindings[1].wireMediaBlobExpiresAtMs,
          ),
        ];
        final crossedExpected = crossed.parent.copyWith(
          directEventFanoutGenerationId: crossedId,
        );
        final messagesBefore = (await fixture.db.query(
          'messages',
          where: 'id = ?',
          whereArgs: const <Object?>[crossedId],
        )).single;
        final v111Before = await durableFanoutRows(crossedId);
        final refused = await fanoutRepository
            .stageOutgoingDirectMediaFanoutInboxCustody(
              expected: crossedExpected,
              staged: crossedExpected.copyWith(
                wireEnvelope: crossedBindings.first.wireEnvelope,
                directMediaCustodyIntentId: null,
                media: crossed.completed,
              ),
              attachments: crossed.completed,
              senderTransportPeerId: senderTransportPeerId,
              contactAccountPeerId: contactAccount,
              authority: DirectMediaFanoutStageAuthority.currentRosterSnapshot,
              expectedSnapshot: snapshot,
              targetBindings: crossedBindings,
            );
        expect(refused.outcome, OutgoingOrdinaryMutationOutcome.refused);
        expect(refused.authorizesTransport, isFalse);
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: const <Object?>[crossedId],
          ),
          isEmpty,
          reason: 'a crossed manifest stages NO sibling at all',
        );
        expect(
          (await fixture.db.query(
            'messages',
            where: 'id = ?',
            whereArgs: const <Object?>[crossedId],
          )).single,
          messagesBefore,
          reason: 'the parent (and its live v110 token) is byte-identical',
        );
        expect(
          await durableFanoutRows(crossedId),
          v111Before,
          reason: 'every v111 row is byte-identical after the refusal',
        );

        // PRE-v108 restart: roster facts drift after every v114 target has a
        // committed STORE receipt. The persisted recipient/key/manifests are
        // now the obligation, so v108 binds without re-resolving or comparing
        // the live roster.
        const survivorId = 'tc362-02b-persisted-survivor-authority';
        final survivor = await publishStoredGeneration(survivorId);
        await fixture.db.update(
          'contacts',
          <String, Object?>{'ml_kem_public_key': 'mlkem-roster-drifted'},
          where: 'peer_id = ?',
          whereArgs: const <Object?>[contactAccount],
        );
        await fixture.db.update(
          'direct_contact_device_bindings',
          <String, Object?>{'state': 'revoked'},
          where: 'contact_account_peer_id = ?',
          whereArgs: const <Object?>[contactAccount],
        );
        final driftedSnapshot = await fanoutRepository
            .readDirectContactFanoutSnapshotForMedia(contactAccount);
        expect(driftedSnapshot, isNotNull);
        expect(driftedSnapshot!.sameSnapshotAs(snapshot), isFalse);

        final survivorExpected = survivor.parent.copyWith(
          directEventFanoutGenerationId: survivorId,
        );
        final survivorBound = await fanoutRepository
            .stageOutgoingDirectMediaFanoutInboxCustody(
              expected: survivorExpected,
              staged: survivorExpected.copyWith(
                wireEnvelope: survivor.bindings.first.wireEnvelope,
                directMediaCustodyIntentId: null,
                media: survivor.completed,
              ),
              attachments: survivor.completed,
              senderTransportPeerId: senderTransportPeerId,
              contactAccountPeerId: contactAccount,
              authority: DirectMediaFanoutStageAuthority.persistedV114Survivors,
              expectedSnapshot: null,
              targetBindings: survivor.bindings,
            );
        expect(survivorBound.outcome, OutgoingOrdinaryMutationOutcome.applied);
        expect(survivorBound.authorizesTransport, isTrue);
        expect(survivorBound.custodyRows, hasLength(2));
        expect(
          await fixture.db.query(
            'direct_inbox_custody_outbox',
            where: 'message_id = ?',
            whereArgs: const <Object?>[survivorId],
          ),
          hasLength(2),
          reason:
              'v108 binds from exact v114 survivors despite live roster drift',
        );
      },
    );

    test('TC-362-02b production-composed drain preserves the shared artifact '
        'until the last sibling retires', () async {
      const identityPeerId = 'tc362-drain-identity';
      const messageId = 'tc362-drain-shared';
      const attachmentId = '$messageId-a1';
      final tempDir = await Directory.systemTemp.createTemp(
        'tc362_drain_shared_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final store = DirectMediaBlobArtifactStore(
        documentsDirectoryProvider: () async => tempDir,
      );
      final bytes = <int>[7, 14, 21, 28];
      final source = File('${tempDir.path}/shared-source.enc');
      await source.writeAsBytes(bytes, flush: true);
      final contentHash = sha256.convert(bytes).toString();
      final artifact = await store.persistCandidate(
        identityPeerId: identityPeerId,
        attachmentId: attachmentId,
        encryptedSourcePath: source.path,
        expectedContentHash: contentHash,
      );

      await fixture.db.insert('messages', <String, Object?>{
        'id': messageId,
        'contact_peer_id': contactAccount,
        'sender_peer_id': 'peer-self',
        'text': '',
        'timestamp': seededAt,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': seededAt,
      });
      Map<String, Object?> siblingRow({
        required String recipientPeerId,
        required String state,
      }) => <String, Object?>{
        'attachment_id': attachmentId,
        'message_id': messageId,
        // Plan 365 lane-generalizes the physical custody table. This
        // Plan-362 preservation fixture remains an exact direct-lane row.
        'owner_lane': 'direct',
        'group_id': null,
        'custody_blob_id': attachmentId,
        'direction': 'outgoing',
        'state': state,
        'inbox_custody_incarnation_id': null,
        'recipient_peer_id': recipientPeerId,
        'contact_account_peer_id': contactAccount,
        'recipient_ml_kem_public_key': 'mlkem-$recipientPeerId',
        'ciphertext_relative_path': artifact.relativePath,
        'custody_kind': 'direct_media_blob_v1',
        'custody_contract': 'ack_or_expiry_v1',
        'content_hash': contentHash,
        'ciphertext_size': bytes.length,
        'transport_mime': 'application/octet-stream',
        'expires_at_ms': null,
        'custody_relay_peer_id': null,
        'retry_count': 0,
        'last_attempt_at': null,
        'next_attempt_at': null,
        'created_at': seededAt,
        'updated_at': seededAt,
      };
      await fixture.db.insert(
        'direct_media_blob_custody',
        siblingRow(
          recipientPeerId: contactAccount,
          state: 'outgoing_cleanup_pending',
        ),
      );
      await fixture.db.insert(
        'direct_media_blob_custody',
        siblingRow(
          recipientPeerId: 'peer-transport-device-00',
          state: 'outgoing_prepared',
        ),
      );

      // Composed EXACTLY like production: the last-reference counter is the
      // real DB helper over the same database.
      final drain = DirectMediaBlobCustodyDrain(
        repository: fixture.repo as DirectMediaBlobCustodyRepository,
        incomingRepository:
            fixture.repo as IncomingDirectMediaBlobCustodyRepository,
        artifactStore: store,
        identityPeerId: () async => identityPeerId,
        strictDownloadAckOwner: StrictDirectMediaBlobDownloadAckOwner(
          bridge: RecordingFakeBridge(),
          mediaAttachmentRepository: fixture.repo,
          mediaFileManager: MediaFileManager(),
        ),
        countOtherArtifactReferences:
            ({
              required ciphertextRelativePath,
              required contentHash,
              required ciphertextSize,
              required excluding,
            }) => dbCountOtherDirectMediaBlobCustodyRowsReferencingArtifact(
              fixture.db,
              ciphertextRelativePath: ciphertextRelativePath,
              contentHash: contentHash,
              ciphertextSize: ciphertextSize,
              excluding: excluding,
            ),
      );

      // Pass 1: the FIRST retired target deletes only its exact row — the
      // surviving sibling still retries from the shared ciphertext.
      final firstPass = await drain.runLocalCleanupBounded();
      expect(firstPass.failed, 0);
      final afterFirst = await fixture.db.query(
        'direct_media_blob_custody',
        where: 'message_id = ?',
        whereArgs: const <Object?>[messageId],
      );
      expect(afterFirst, hasLength(1));
      expect(
        afterFirst.single['recipient_peer_id'],
        'peer-transport-device-00',
      );
      expect(
        File(artifact.absolutePath).existsSync(),
        isTrue,
        reason:
            'the first completed target must never unlink ciphertext a '
            'surviving sibling still needs',
      );

      // Pass 2: the LAST sibling retires and alone authorizes the unlink.
      await fixture.db.rawUpdate(
        "UPDATE direct_media_blob_custody SET state = 'outgoing_cleanup_pending' "
        'WHERE message_id = ? AND recipient_peer_id = ?',
        const <Object?>[messageId, 'peer-transport-device-00'],
      );
      final secondPass = await drain.runLocalCleanupBounded();
      expect(secondPass.failed, 0);
      expect(
        await fixture.db.query(
          'direct_media_blob_custody',
          where: 'message_id = ?',
          whereArgs: const <Object?>[messageId],
        ),
        isEmpty,
      );
      expect(
        File(artifact.absolutePath).existsSync(),
        isFalse,
        reason: 'the last reference unlinks the shared artifact',
      );
    });
  });
}

void _registerStrictGroupMediaKeyBoundaryTests(
  MediaRepositoryRealDbFixture Function() loadFixture,
) {
  Map<String, Object?> expectedRow(GroupMessage message) => <String, Object?>{
    ...message.toMap(),
    'retry_attempt_count': message.retryAttemptCount,
    'next_eligible_at': message.nextEligibleAt?.millisecondsSinceEpoch,
  };
  GroupMediaKeyAccess access(MediaRepositoryRealDbFixture fixture) =>
      GroupMediaKeyAccess(
        secureKeyStore: fixture.secureKeyStore,
        lifecycleLock: fixture.repo.lifecycleLock,
      );
  Future<bool> stage(
    MediaRepositoryRealDbFixture fixture,
    ({
      GroupMessage expected,
      Map<String, Object?> eventPayload,
      Map<String, Object?> preparedEventPayload,
    })
    seeded, {
    GroupMediaKeySnapshot? snapshot,
  }) => dbStagePreparedLocalGroupContentMessage(
    fixture.db,
    expected: expectedRow(seeded.expected),
    sourcePeerId: 'account-local',
    sourceEventId: localPreparedProtectedGroupMessageSourceEventId(
      seeded.expected.id,
    ),
    sourceTimestamp: '2026-08-14T12:00:00.000000Z',
    preparedEventPayload: seeded.preparedEventPayload,
    mediaKeyAccess: snapshot == null ? access(fixture) : null,
    mediaKeySnapshot: snapshot,
  );

  for (final keyMode in <String>[
    'legacy',
    'secure',
    'wrong-reference',
    'missing-key',
    'wrong-key',
  ]) {
    for (final waveform in <List<double>?>[
      null,
      const <double>[],
      const <double>[0.1, 0.5],
    ]) {
      test(
        'strict DB key boundary $keyMode ${waveform == null
            ? "null"
            : waveform.isEmpty
            ? "empty"
            : "nonempty"}',
        () async {
          final fixture = loadFixture();
          final seeded = await _seedStrictGroupMediaKeyBoundary(
            fixture,
            keyMode: keyMode,
            waveform: waveform,
          );
          final accepted =
              (keyMode == 'legacy' || keyMode == 'secure') &&
              (waveform == null || waveform.isEmpty);
          expect(await stage(fixture, seeded), accepted);
          if (!accepted) return;
          expect(
            await dbHasExactPreparedLocalGroupContentMessage(
              fixture.db,
              expected: expectedRow(seeded.expected),
              eventPayload: seeded.eventPayload,
              mediaKeyAccess: access(fixture),
            ),
            isTrue,
          );
          final replacement = GroupContentRetryPayload.decode(
            seeded.expected.inboxRetryPayload!,
          ).encodeWithPending(const <String>['transport-z']);
          expect(
            await dbReplaceGroupInboxRetryPayloadIfExact(
              fixture.db,
              expectedRow(seeded.expected),
              replacement,
              mediaKeyAccess: access(fixture),
            ),
            isTrue,
          );
          final surviving = seeded.expected.copyWith(
            inboxRetryPayload: replacement,
          );
          expect(
            await dbCompleteGroupContentInboxStoreRetryIfExact(
              fixture.db,
              expected: expectedRow(surviving),
              sourcePeerId: 'account-local',
              sourceEventId: localProtectedGroupMessageSourceEventId(
                surviving.id,
              ),
              sourceTimestamp: '2026-08-14T12:00:00.000000Z',
              eventPayload: seeded.eventPayload,
              mediaKeyAccess: access(fixture),
            ),
            isTrue,
          );
          final terminal = (await fixture.db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: <Object?>[surviving.id],
          )).single;
          expect(terminal['status'], 'sent');
          expect(terminal['inbox_stored'], 1);
          expect(terminal['inbox_retry_payload'], isNull);
          final rows = await (fixture.repo as GroupMediaBlobCustodyRepository)
              .loadGroupMediaBlobCustodyForMessage(
                groupId: surviving.groupId,
                messageId: surviving.id,
              );
          expect(rows, hasLength(2));
          expect(
            rows.every(
              (row) =>
                  row.state ==
                  DirectMediaBlobCustodyState.outgoingCleanupPending,
            ),
            isTrue,
          );
          final key = (await fixture.rawAttachmentRow(
            'key-boundary-image',
          ))!['encryption_key_base64'];
          expect(
            key,
            keyMode == 'legacy'
                ? 'test-encryption-key'
                : secureStoreReferenceForKey(
                    mediaAttachmentEncryptionKeyStoreName('key-boundary-image'),
                  ),
          );
        },
      );
    }
  }

  test(
    'strict DB key scope rejects stale proof and releases after callback failure',
    () async {
      final fixture = loadFixture();
      final seeded = await _seedStrictGroupMediaKeyBoundary(
        fixture,
        keyMode: 'secure',
      );
      late GroupMediaKeySnapshot expired;
      await expectLater(
        access(fixture).run<void>(
          db: fixture.db,
          messageIds: <String>[seeded.expected.id],
          action: (snapshot) async {
            expired = snapshot;
            expect(
              snapshot.matches(
                db: fixture.db,
                attachmentId: 'key-boundary-image',
                messageId: seeded.expected.id,
                storedKey: secureStoreReferenceForKey(
                  mediaAttachmentEncryptionKeyStoreName('key-boundary-image'),
                ),
                committedKey: 'test-encryption-key',
              ),
              isTrue,
            );
            throw StateError('injected callback failure');
          },
        ),
        throwsStateError,
      );
      expect(await stage(fixture, seeded, snapshot: expired), isFalse);
      expect(await stage(fixture, seeded), isTrue);
    },
  );

  test('strict DB key scope holds key mutation through SQL commit', () async {
    final fixture = loadFixture();
    final seeded = await _seedStrictGroupMediaKeyBoundary(
      fixture,
      keyMode: 'secure',
    );
    final attachment = (await fixture.repo.getAttachmentById(
      'key-boundary-image',
    ))!;
    final keyName = mediaAttachmentEncryptionKeyStoreName(attachment.id);
    final order = <String>[];
    var contenderEntered = false;
    Future<void>? mutation;
    try {
      await access(fixture).run<void>(
        db: fixture.db,
        messageIds: <String>[seeded.expected.id],
        action: (snapshot) async {
          // A separate owner must not inherit the scope's reentrant Zone lease.
          mutation = Zone.root.run<Future<void>>(
            () => fixture.repo.lifecycleLock.synchronized(
              attachment.id,
              () async {
                contenderEntered = true;
                await fixture.repo.saveAttachment(
                  attachment.copyWith(encryptionKeyBase64: 'rotated-key'),
                  owner: MediaOwnerLane.group,
                );
                order.add('mutation');
              },
            ),
          );
          // Give the independent contender an event turn to acquire ownership.
          await Future<void>(() {});
          await fixture.db.transaction((txn) async {
            expect(
              await fixture.secureKeyStore.read(keyName),
              'test-encryption-key',
              reason: 'the actual key must remain committed during SQL',
            );
            expect(contenderEntered, isFalse);
            expect(
              snapshot.matches(
                db: txn,
                attachmentId: attachment.id,
                messageId: attachment.messageId,
                storedKey: (await txn.query(
                  'media_attachments',
                  where: 'id = ?',
                  whereArgs: <Object?>[attachment.id],
                )).single['encryption_key_base64'],
                committedKey: 'test-encryption-key',
              ),
              isTrue,
            );
            expect(order, isEmpty);
          });
          expect(
            await fixture.secureKeyStore.read(keyName),
            'test-encryption-key',
          );
          order.add('commit');
        },
      );
    } finally {
      await mutation;
    }
    expect(order, <String>['commit', 'mutation']);
    expect(await fixture.secureKeyStore.read(keyName), 'rotated-key');
    expect(
      (await fixture.repo.getAttachmentById(
        attachment.id,
      ))!.encryptionKeyBase64,
      'rotated-key',
    );
  });

  test(
    'strict DB key scope propagates secure read failure and releases ownership',
    () async {
      final fixture = loadFixture();
      final seeded = await _seedStrictGroupMediaKeyBoundary(
        fixture,
        keyMode: 'secure',
      );
      final unavailableStore = _FailingSnapshotSecureKeyStore()
        ..failRead = true;
      var actionEntered = false;
      await expectLater(
        GroupMediaKeyAccess(
          secureKeyStore: unavailableStore,
          lifecycleLock: fixture.repo.lifecycleLock,
        ).run<void>(
          db: fixture.db,
          messageIds: <String>[seeded.expected.id],
          action: (_) async {
            actionEntered = true;
          },
        ),
        throwsStateError,
      );
      expect(actionEntered, isFalse);
      expect(await stage(fixture, seeded), isTrue);
    },
  );

  test(
    'strict DB key scope rejects key reads inside SQL transactions',
    () async {
      final fixture = loadFixture();
      await fixture.db.transaction((txn) async {
        await expectLater(
          () => access(fixture).run<void>(
            db: txn,
            messageIds: const <String>['message'],
            action: (_) async {},
          ),
          throwsStateError,
        );
      });
    },
  );

  test(
    'strict DB key scope terminalizes a reopened secure media owner',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'group-key-reopen-',
      );
      var fixture = await MediaRepositoryRealDbFixture.create(
        databasePath: '${directory.path}/identity.db',
      );
      addTearDown(() async {
        await fixture.dispose();
        await directory.delete(recursive: true);
      });
      final seeded = await _seedStrictGroupMediaKeyBoundary(
        fixture,
        keyMode: 'secure',
        waveform: const <double>[],
      );
      expect(await stage(fixture, seeded), isTrue);
      fixture = await fixture.reopen();
      expect(
        await dbHasExactPreparedLocalGroupContentMessage(
          fixture.db,
          expected: expectedRow(seeded.expected),
          eventPayload: seeded.eventPayload,
          mediaKeyAccess: access(fixture),
        ),
        isTrue,
      );
      expect(
        await dbTerminalizePreparedLocalGroupContentMessageIfExact(
          fixture.db,
          expected: expectedRow(seeded.expected),
          preparedEventPayload: seeded.preparedEventPayload,
          terminalSourcePeerId: 'account-local',
          terminalSourceEventId: 'pt1:terminal-key-reopen',
          terminalSourceTimestamp: '2026-08-14T12:01:00.000000Z',
          terminalEventPayload: <String, Object?>{
            'reason': 'test-reconciliation',
          },
          mediaKeyAccess: access(fixture),
        ),
        isTrue,
      );
      final row = (await fixture.db.query(
        'group_messages',
        where: 'id = ?',
        whereArgs: <Object?>[seeded.expected.id],
      )).single;
      expect(row['status'], 'send_failed');
      expect(row['inbox_retry_payload'], isNull);
      expect(
        (await fixture.rawAttachmentRow(
          'key-boundary-image',
        ))!['encryption_key_base64'],
        secureStoreReferenceForKey(
          mediaAttachmentEncryptionKeyStoreName('key-boundary-image'),
        ),
      );
    },
  );

  test('strict DB key scope rejects proof from a different database', () async {
    final fixture = loadFixture();
    final seeded = await _seedStrictGroupMediaKeyBoundary(
      fixture,
      keyMode: 'secure',
    );
    final directory = await Directory.systemTemp.createTemp(
      'group-key-other-db-',
    );
    final other = await MediaRepositoryRealDbFixture.create(
      databasePath: '${directory.path}/other.db',
    );
    addTearDown(() async {
      await other.dispose();
      await directory.delete(recursive: true);
    });
    final otherSeeded = await _seedStrictGroupMediaKeyBoundary(
      other,
      keyMode: 'wrong-key',
    );
    expect(identical(fixture.db, other.db), isFalse);
    await access(fixture).run<void>(
      db: fixture.db,
      messageIds: <String>[seeded.expected.id],
      action: (snapshot) async {
        expect(await stage(other, otherSeeded, snapshot: snapshot), isFalse);
        expect(await stage(fixture, seeded, snapshot: snapshot), isTrue);
      },
    );
  });

  test(
    'strict DB key scope supplies proof to transaction terminalization',
    () async {
      final fixture = loadFixture();
      final seeded = await _seedStrictGroupMediaKeyBoundary(
        fixture,
        keyMode: 'secure',
      );
      expect(await stage(fixture, seeded), isTrue);
      await access(fixture).run<void>(
        db: fixture.db,
        messageIds: <String>[seeded.expected.id],
        action: (snapshot) async {
          expect(
            await fixture.db.transaction(
              (txn) =>
                  dbTerminalizePreparedLocalGroupContentMessageIfExactInTransaction(
                    txn,
                    expected: expectedRow(seeded.expected),
                    preparedEventPayload: seeded.preparedEventPayload,
                    terminalSourcePeerId: 'account-local',
                    terminalSourceEventId: 'pt1:transaction-terminal',
                    terminalSourceTimestamp: '2026-08-14T12:01:00.000000Z',
                    terminalEventPayload: <String, Object?>{
                      'reasonCode': 'authority_reconciliation_invalidated',
                    },
                    mediaKeySnapshot: snapshot,
                  ),
            ),
            isTrue,
          );
        },
      );
    },
  );

  test(
    'strict DB key scope preserves malformed retry refusal without key reads',
    () async {
      final fixture = loadFixture();
      final seeded = await _seedStrictGroupMediaKeyBoundary(
        fixture,
        keyMode: 'secure',
      );
      final unavailableStore = _FailingSnapshotSecureKeyStore()
        ..failRead = true;
      for (final malformed in <String>[
        '{',
        '{}',
        jsonEncode(<String, Object?>{
          ...(jsonDecode(seeded.expected.inboxRetryPayload!) as Map)
              .cast<String, Object?>(),
          'groupId': 42,
        }),
      ]) {
        expect(
          await dbStagePreparedLocalGroupContentMessage(
            fixture.db,
            expected: expectedRow(
              seeded.expected.copyWith(inboxRetryPayload: malformed),
            ),
            sourcePeerId: 'account-local',
            sourceEventId: localPreparedProtectedGroupMessageSourceEventId(
              seeded.expected.id,
            ),
            sourceTimestamp: '2026-08-14T12:00:00.000000Z',
            preparedEventPayload: seeded.preparedEventPayload,
            mediaKeyAccess: GroupMediaKeyAccess(
              secureKeyStore: unavailableStore,
            ),
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'strict DB key scope completes a zero-recipient secure media owner',
    () async {
      final fixture = loadFixture();
      final seeded = await _seedStrictGroupMediaKeyBoundary(
        fixture,
        keyMode: 'secure',
        waveform: const <double>[],
        zeroTarget: true,
      );
      expect(
        await dbStageAndCompleteLocalGroupContentMessage(
          fixture.db,
          expected: expectedRow(seeded.expected),
          sourcePeerId: 'account-local',
          sourceEventId: localProtectedGroupMessageSourceEventId(
            seeded.expected.id,
          ),
          sourceTimestamp: '2026-08-14T12:00:00.000000Z',
          eventPayload: seeded.eventPayload,
          mediaKeyAccess: access(fixture),
        ),
        isTrue,
      );
      expect(
        (await fixture.db.query(
          'group_messages',
          where: 'id = ?',
          whereArgs: <Object?>[seeded.expected.id],
        )).single['status'],
        'sent',
      );
    },
  );
}

Future<
  ({
    GroupMessage expected,
    Map<String, Object?> eventPayload,
    Map<String, Object?> preparedEventPayload,
  })
>
_seedStrictGroupMediaKeyBoundary(
  MediaRepositoryRealDbFixture fixture, {
  required String keyMode,
  List<double>? waveform,
  bool zeroTarget = false,
}) async {
  const groupId = 'key-boundary-group';
  const messageId = 'key-boundary-message';
  const attachmentId = 'key-boundary-image';
  const blobId = 'gmb1_key_boundary';
  const rawKey = 'test-encryption-key';
  const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final recipients = zeroTarget
      ? const <String>[]
      : const <String>['transport-remote', 'transport-z'];
  const at = '2026-08-14T12:00:00.000Z';
  final timestamp = DateTime.parse(at);
  await fixture.db.insert('groups', <String, Object?>{
    'id': groupId,
    'name': 'Synthetic key boundary',
    'type': 'chat',
    'topic_name': 'key-boundary-topic',
    'created_at': at,
    'created_by': 'account-local',
    'my_role': 'admin',
  });
  final parent = GroupMessage(
    id: messageId,
    groupId: groupId,
    senderPeerId: 'account-local',
    transportPeerId: 'transport-local',
    senderUsername: 'Local',
    text: 'synthetic caption',
    timestamp: timestamp,
    createdAt: timestamp,
    logicalDeliveryId: messageId,
    keyGeneration: 1,
    status: GroupMessage.statusQueuedOffline,
    isIncoming: false,
  );
  final fingerprint = computeGroupMediaBlobCustodyFingerprint(
    groupId: groupId,
    messageId: messageId,
    attachmentId: attachmentId,
    custodyBlobId: blobId,
    contentHash: hash,
    ciphertextSize: 80,
    recipientPeerIds: recipients,
  );
  final attachment = MediaAttachment(
    id: attachmentId,
    messageId: messageId,
    mime: 'image/jpeg',
    size: 64,
    mediaType: 'image',
    localPath: 'pending_uploads/test.jpg',
    downloadStatus: 'upload_pending',
    createdAt: at,
    contentHash: hash,
    encryptionKeyBase64: rawKey,
    encryptionNonce: 'test-nonce',
    encryptionScheme: groupMediaBlobEncryptionScheme,
    groupMediaBlobCustodyFingerprint: fingerprint,
    ownerLane: MediaOwnerLane.group,
    waveform: waveform,
  );
  final prepared = DirectMediaBlobCustodyRow(
    attachmentId: attachmentId,
    messageId: messageId,
    ownerLane: MediaBlobCustodyOwnerLane.group,
    groupId: groupId,
    custodyBlobId: blobId,
    direction: DirectMediaBlobCustodyDirection.outgoing,
    state: DirectMediaBlobCustodyState.outgoingPrepared,
    inboxCustodyIncarnationId: null,
    recipientPeerId: 'transport-remote',
    ciphertextRelativePath:
        'group_media_blob_custody_v1/identity/group/image.blob',
    custodyKind: kGroupMediaBlobCustodyKind,
    contentHash: hash,
    ciphertextSize: 80,
    expiresAtMs: null,
    custodyRelayPeerId: null,
    lastAttemptAt: null,
    nextAttemptAt: null,
    createdAt: at,
    updatedAt: at,
  );
  final repository = fixture.repo as GroupMediaBlobCustodyRepository;
  expect(
    await repository.stageFreshOutgoingGroupMediaBlobGeneration(
      parent: parent,
      attachments: <MediaAttachment>[attachment],
      custodyRows: <DirectMediaBlobCustodyRow>[
        for (final recipient in recipients)
          DirectMediaBlobCustodyRow.fromMap(<String, Object?>{
            ...prepared.toMap(),
            'recipient_peer_id': recipient,
          }),
      ],
      custodyBlobIdsByAttachmentId: const <String, String>{
        attachmentId: blobId,
      },
    ),
    GroupMediaBlobCustodyStageOutcome.applied,
  );
  for (final recipient in recipients) {
    final row = DirectMediaBlobCustodyRow.fromMap(<String, Object?>{
      ...prepared.toMap(),
      'recipient_peer_id': recipient,
    });
    expect(
      await repository.transitionGroupMediaBlobCustodyIfExact(
        expected: row,
        next: row.copyWith(
          state: DirectMediaBlobCustodyState.outgoingStored,
          expiresAtMs: 2000000000000,
          custodyRelayPeerId: 'synthetic-relay',
        ),
      ),
      isTrue,
    );
  }
  final secureName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
  expect(
    (await fixture.rawAttachmentRow(attachmentId))!['encryption_key_base64'],
    secureStoreReferenceForKey(secureName),
  );
  expect(
    (await fixture.repo.getAttachmentById(attachmentId))!.encryptionKeyBase64,
    rawKey,
  );
  if (keyMode == 'legacy' || keyMode == 'wrong-reference') {
    await fixture.db.update(
      'media_attachments',
      <String, Object?>{
        'encryption_key_base64': keyMode == 'legacy'
            ? rawKey
            : secureStoreReferenceForKey('wrong-key-slot'),
      },
      where: 'id = ?',
      whereArgs: <Object?>[attachmentId],
    );
  } else if (keyMode == 'missing-key') {
    await fixture.secureKeyStore.delete(secureName);
  } else if (keyMode == 'wrong-key') {
    await fixture.secureKeyStore.write(secureName, 'different-key');
  }
  final manifest = ProtectedGroupMediaManifest(
    groupId: groupId,
    messageId: messageId,
    attachments: <ProtectedGroupMediaAttachmentCommitment>[
      ProtectedGroupMediaAttachmentCommitment(
        attachmentId: attachmentId,
        custodyBlobId: blobId,
        ciphertextSha256: hash,
        ciphertextSize: 80,
        mime: 'image/jpeg',
        mediaType: 'image',
        encryptionKeyBase64: rawKey,
        encryptionNonce: 'test-nonce',
        caption: parent.text,
        targets: <GroupMediaBlobTargetCommitment>[
          for (final recipient in recipients)
            GroupMediaBlobTargetCommitment(
              recipientPeerId: recipient,
              expiresAtMs: 2000000000000,
            ),
        ],
      ),
    ],
  );
  final plaintext = <String, Object?>{
    'groupId': groupId,
    'senderId': 'account-local',
    'senderUsername': 'Local',
    'senderDeviceId': 'device-local',
    'transportPeerId': 'transport-local',
    'messageId': messageId,
    'logicalDeliveryId': messageId,
    'keyEpoch': 1,
    'text': parent.text,
    'timestamp': '2026-08-14T12:00:00.000000Z',
    'mediaManifest': manifest.encode(),
    'mediaManifestHash': manifest.fingerprintSha256,
  };
  final groupRepo = InMemoryGroupRepository();
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'test-group-key',
      createdAt: timestamp,
    ),
  );
  final replay = await buildGroupOfflineReplayEnvelope(
    bridge: FakeBridge(),
    groupRepo: groupRepo,
    groupId: groupId,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode(plaintext),
    senderPeerId: 'account-local',
    senderPublicKey: 'pk-local',
    senderPrivateKey: 'sk-local',
    senderDeviceId: 'device-local',
    senderTransportPeerId: 'transport-local',
    recipientPeerIds: recipients,
    messageId: messageId,
    contentEventId: messageId,
    mediaManifest: manifest,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: timestamp.subtract(const Duration(hours: 1)),
      eventId: 'synthetic-authority',
      keyEpoch: 1,
    ),
  );
  final retry = zeroTarget
      ? null
      : jsonEncode(<String, Object?>{
          'groupId': groupId,
          'message': replay,
          'custodyContract': ackOrExpiryInboxCustodyContract,
          'custodyKind': groupContentCustodyKind,
          'recipientPeerIds': recipients,
        });
  final expected = parent.copyWith(
    lastSendAttemptAt: timestamp,
    wireEnvelope: jsonEncode(plaintext),
    inboxRetryPayload: retry,
  );
  final eventPayload = buildLocalProtectedGroupContentEventPayload(
    replayEnvelope: replay,
    payload: plaintext,
  );
  return (
    expected: expected,
    eventPayload: eventPayload,
    preparedEventPayload: zeroTarget
        ? <String, Object?>{}
        : buildLocalProtectedGroupContentPreparedEventPayload(
            eventPayload: eventPayload,
            ownerKind: 'group_message',
            ownerId: messageId,
            ownerStatus: GroupMessage.statusQueuedOffline,
            inboxRetryPayload: retry!,
          ),
  );
}
