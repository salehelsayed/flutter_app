import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

const int _maximumStrictGroupMediaAttachments = 10;

typedef GroupMediaBlobStrictUploadFn =
    Future<Map<String, dynamic>> Function({
      required Bridge bridge,
      required String custodyBlobId,
      required String recipientPeerId,
      required String ciphertextPath,
      required String contentHash,
      required int ciphertextSize,
    });

final class PreparedGroupMediaBlobSource {
  const PreparedGroupMediaBlobSource({
    required this.attachment,
    required this.plaintextPath,
    this.preparedArtifact,
  });

  final MediaAttachment attachment;
  final String plaintextPath;

  /// Test/producer seam for an encrypt-once candidate that has not been sent.
  final EncryptedMediaArtifact? preparedArtifact;
}

enum PreparedGroupMediaBlobState {
  complete,
  retained,
  refused,
  legacyUninitialized,
}

final class PreparedGroupMediaBlobResult {
  const PreparedGroupMediaBlobResult._({
    required this.state,
    required this.hasDurableAuthority,
    this.parent,
    this.attachments = const <MediaAttachment>[],
    this.preparedManifest,
  });

  const PreparedGroupMediaBlobResult.complete({
    required GroupMessage parent,
    required List<MediaAttachment> attachments,
    required PreparedGroupMediaManifestAuthority preparedManifest,
  }) : this._(
         state: PreparedGroupMediaBlobState.complete,
         hasDurableAuthority: true,
         parent: parent,
         attachments: attachments,
         preparedManifest: preparedManifest,
       );

  const PreparedGroupMediaBlobResult.retained()
    : this._(
        state: PreparedGroupMediaBlobState.retained,
        hasDurableAuthority: true,
      );

  const PreparedGroupMediaBlobResult.refused({bool hasDurableAuthority = false})
    : this._(
        state: PreparedGroupMediaBlobState.refused,
        hasDurableAuthority: hasDurableAuthority,
      );

  const PreparedGroupMediaBlobResult.legacyUninitialized()
    : this._(
        state: PreparedGroupMediaBlobState.legacyUninitialized,
        hasDurableAuthority: false,
      );

  final PreparedGroupMediaBlobState state;
  final bool hasDurableAuthority;
  final GroupMessage? parent;
  final List<MediaAttachment> attachments;
  final PreparedGroupMediaManifestAuthority? preparedManifest;

  bool get isComplete => state == PreparedGroupMediaBlobState.complete;
}

final class PreparedGroupMediaSendResult {
  const PreparedGroupMediaSendResult({
    required this.preparation,
    this.sendResult,
    this.message,
  });

  final PreparedGroupMediaBlobResult preparation;
  final SendGroupMessageResult? sendResult;
  final GroupMessage? message;

  bool get shouldUseLegacyPath =>
      preparation.state == PreparedGroupMediaBlobState.legacyUninitialized;
}

/// Sole producer for initialized ordinary group media and voice.
///
/// Source validation and Plan-364 admission happen before this owner creates a
/// file, database row, background task, or network request. Each logical blob
/// is encrypted once, persisted once, and then addressed by independent
/// per-physical-recipient custody rows. Restart retry reopens only those rows;
/// it never resolves the roster or encrypts again.
final class PreparedGroupMediaBlobCustodyCoordinator {
  PreparedGroupMediaBlobCustodyCoordinator({
    required GroupMediaBlobArtifactStore artifactStore,
    PrepareEncryptedMediaArtifactFn prepareArtifact =
        prepareEncryptedMediaArtifact,
    GroupMediaBlobStrictUploadFn? strictUpload,
    DateTime Function()? clock,
  }) : _artifactStore = artifactStore,
       _prepareArtifact = prepareArtifact,
       _strictUpload = strictUpload ?? _callStrictGroupUpload,
       _clock = clock ?? DateTime.now;

  final GroupMediaBlobArtifactStore _artifactStore;
  final PrepareEncryptedMediaArtifactFn _prepareArtifact;
  final GroupMediaBlobStrictUploadFn _strictUpload;
  final DateTime Function() _clock;

  Future<PreparedGroupMediaSendResult> prepareAndSend({
    required Bridge bridge,
    required GroupRepository groupRepository,
    required GroupMessageRepository messageRepository,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required String identityPeerId,
    required String senderPublicKey,
    required String senderPrivateKey,
    required String senderUsername,
    required GroupMessage parent,
    required List<PreparedGroupMediaBlobSource> sources,
    String? senderDeviceId,
    String? senderTransportPeerId,
    GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
    GroupContentAuthoringContext? groupContentAuthoring,
  }) async {
    final prepared = await prepareAndUploadFresh(
      bridge: bridge,
      groupRepository: groupRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      identityPeerId: identityPeerId,
      senderPublicKey: senderPublicKey,
      parent: parent,
      sources: sources,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
      groupContentAuthoring: groupContentAuthoring,
    );
    if (!prepared.isComplete) {
      return PreparedGroupMediaSendResult(preparation: prepared);
    }
    final stagedParent = prepared.parent!;
    final authority = prepared.preparedManifest!;
    final (sendResult, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepository,
      msgRepo: messageRepository,
      groupId: stagedParent.groupId,
      text: stagedParent.text,
      senderPeerId: identityPeerId,
      senderPublicKey: senderPublicKey,
      senderPrivateKey: senderPrivateKey,
      senderUsername: senderUsername,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      messageId: stagedParent.id,
      logicalDeliveryId: stagedParent.logicalDeliveryId ?? stagedParent.id,
      timestamp: stagedParent.timestamp,
      quotedMessageId: stagedParent.quotedMessageId,
      isForwarded: stagedParent.isForwarded,
      mediaAttachments: prepared.attachments,
      mediaAttachmentRepo: mediaAttachmentRepository,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
      groupContentAuthoring: groupContentAuthoring,
      preparedGroupMediaManifest: authority,
    );
    if (authority.manifest.recipientPeerIds.isEmpty &&
        (sendResult == SendGroupMessageResult.success ||
            sendResult == SendGroupMessageResult.successNoPeers)) {
      await _cleanupSoleGroupArtifacts(
        identityPeerId: identityPeerId,
        manifest: authority.manifest,
      );
    }
    return PreparedGroupMediaSendResult(
      preparation: prepared,
      sendResult: sendResult,
      message: message,
    );
  }

  Future<PreparedGroupMediaBlobResult> prepareAndUploadFresh({
    required Bridge bridge,
    required GroupRepository groupRepository,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required String identityPeerId,
    required String senderPublicKey,
    required GroupMessage parent,
    required List<PreparedGroupMediaBlobSource> sources,
    String? senderDeviceId,
    String? senderTransportPeerId,
    GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
    GroupContentAuthoringContext? groupContentAuthoring,
  }) async {
    final repository = switch (mediaAttachmentRepository) {
      GroupMediaBlobCustodyRepository value
          when value.supportsGroupMediaBlobCustody =>
        value,
      _ => null,
    };
    if (repository == null ||
        !_validFreshRequest(identityPeerId, parent, sources) ||
        !await _validateSources(sources)) {
      return const PreparedGroupMediaBlobResult.refused();
    }
    final admission = await prepareGroupContentAuthoringAdmission(
      groupRepo: groupRepository,
      groupId: parent.groupId,
      senderPeerId: identityPeerId,
      senderPublicKey: senderPublicKey,
      senderDeviceId: senderDeviceId,
      senderTransportPeerId: senderTransportPeerId,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
      explicitContext: groupContentAuthoring,
    );
    if (admission.kind ==
        GroupContentAuthoringResolutionKind.legacyUninitialized) {
      return const PreparedGroupMediaBlobResult.legacyUninitialized();
    }
    final snapshot = admission.snapshot;
    final sanitizedText = sanitizeMessageText(parent.text);
    if (admission.kind != GroupContentAuthoringResolutionKind.strict ||
        snapshot == null ||
        parent.senderPeerId != identityPeerId ||
        parent.isIncoming ||
        (parent.isForwarded &&
            (parent.quotedMessageId?.isNotEmpty == true ||
                sources.any(
                  (source) =>
                      source.attachment.mediaType != 'image' &&
                      source.attachment.mediaType != 'video',
                ))) ||
        !parent.privateMediaPolicy.isOrdinary ||
        sanitizedText.trimLeft().startsWith(r'{"__sys":') ||
        snapshot.recipientPeerIds.length >
            protectedGroupMediaMaxPhysicalRecipients) {
      return const PreparedGroupMediaBlobResult.refused();
    }

    var hasDurableAuthority = false;
    try {
      return await repository.runGroupMediaBlobCustodyLifecycle(() async {
        final publication = await _publishFreshGeneration(
          bridge: bridge,
          repository: repository,
          identityPeerId: identityPeerId,
          snapshot: snapshot,
          parent: parent.copyWith(text: sanitizedText),
          sources: sources,
        );
        hasDurableAuthority = publication.hasDurableAuthority;
        final generation = publication.generation;
        if (generation == null) {
          return hasDurableAuthority
              ? const PreparedGroupMediaBlobResult.retained()
              : const PreparedGroupMediaBlobResult.refused();
        }
        return _uploadGeneration(
          bridge: bridge,
          repository: repository,
          mediaAttachmentRepository: mediaAttachmentRepository,
          identityPeerId: identityPeerId,
          generation: generation,
        );
      });
    } on Object {
      return hasDurableAuthority
          ? const PreparedGroupMediaBlobResult.retained()
          : const PreparedGroupMediaBlobResult.refused();
    }
  }

  /// Survivor-only restart entry. It loads the frozen target matrix and the
  /// existing ciphertext; there is intentionally no group/roster argument.
  Future<PreparedGroupMediaBlobResult> retryPersistedGeneration({
    required Bridge bridge,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required String identityPeerId,
    required GroupMessage expectedParent,
  }) async {
    final repository = switch (mediaAttachmentRepository) {
      GroupMediaBlobCustodyRepository value
          when value.supportsGroupMediaBlobCustody =>
        value,
      _ => null,
    };
    if (repository == null ||
        !_trimmed(identityPeerId) ||
        !_trimmed(expectedParent.groupId) ||
        !_trimmed(expectedParent.id) ||
        expectedParent.senderPeerId != identityPeerId ||
        expectedParent.isIncoming ||
        // Fresh survivor refresh ends permanently when protected content
        // persists either side of its exact signed authority. Even malformed
        // non-null bytes fail closed here: the content retry/terminal owner,
        // never blob upload retry, owns all post-binding convergence.
        expectedParent.wireEnvelope != null ||
        expectedParent.inboxRetryPayload != null) {
      return const PreparedGroupMediaBlobResult.refused();
    }
    try {
      return await repository.runGroupMediaBlobCustodyLifecycle(() async {
        final attachments = await mediaAttachmentRepository
            .getAttachmentsForMessage(
              expectedParent.id,
              owner: MediaOwnerLane.group,
            );
        final rows = await repository.loadGroupMediaBlobCustodyForMessage(
          groupId: expectedParent.groupId,
          messageId: expectedParent.id,
        );
        if (attachments.isEmpty ||
            attachments.any(
              (attachment) =>
                  attachment.groupMediaBlobCustodyFingerprint == null,
            )) {
          return const PreparedGroupMediaBlobResult.refused();
        }
        final generation = await _reopenGeneration(
          identityPeerId: identityPeerId,
          parent: expectedParent,
          attachments: attachments,
          rows: rows,
        );
        if (generation == null) {
          return const PreparedGroupMediaBlobResult.refused(
            hasDurableAuthority: true,
          );
        }
        return _uploadGeneration(
          bridge: bridge,
          repository: repository,
          mediaAttachmentRepository: mediaAttachmentRepository,
          identityPeerId: identityPeerId,
          generation: generation,
        );
      });
    } on Object {
      return const PreparedGroupMediaBlobResult.refused(
        hasDurableAuthority: true,
      );
    }
  }

  /// Existing lifecycle drain for terminal outgoing rows plus bounded
  /// crash-orphan reconciliation. Content retry atomically moves one target's
  /// rows to `outgoing_cleanup_pending`; this owner retires only those exact
  /// rows and deletes the shared artifact after its final reference.
  Future<int> drainOutgoingCleanupAndOrphans({
    required MediaAttachmentRepository mediaAttachmentRepository,
    required String identityPeerId,
    int limit = 50,
  }) async {
    final repository = switch (mediaAttachmentRepository) {
      GroupMediaBlobCustodyRepository value
          when value.supportsGroupMediaBlobCustody =>
        value,
      _ => null,
    };
    if (repository == null || !_trimmed(identityPeerId) || limit <= 0) {
      return 0;
    }
    var progress = 0;
    try {
      await repository.runGroupMediaBlobCustodyLifecycle(() async {
        final pending = await repository.loadGroupMediaBlobCustodyByStates(
          const <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingCleanupPending,
          },
          limit: limit > 50 ? 50 : limit,
        );
        for (final expected in pending) {
          final relativePath = expected.ciphertextRelativePath;
          final groupId = expected.groupId;
          if (expected.ownerLane != MediaBlobCustodyOwnerLane.group ||
              expected.direction != DirectMediaBlobCustodyDirection.outgoing ||
              expected.state !=
                  DirectMediaBlobCustodyState.outgoingCleanupPending ||
              groupId == null ||
              relativePath == null) {
            continue;
          }
          final otherReferences = await repository
              .countOtherGroupMediaBlobCustodyRowsReferencingArtifact(expected);
          if (!await repository.deleteGroupMediaBlobCleanupPendingIfExact(
            expected,
          )) {
            continue;
          }
          progress++;
          if (otherReferences == 0 &&
              await _artifactStore.deleteOwnedArtifact(
                identityPeerId: identityPeerId,
                groupId: groupId,
                relativePath: relativePath,
              )) {
            progress++;
          }
        }

        final inventory =
            mediaAttachmentRepository
                is GroupMediaBlobArtifactReferenceInventoryRepository
            ? mediaAttachmentRepository
                  as GroupMediaBlobArtifactReferenceInventoryRepository
            : null;
        if (inventory != null) {
          final referenced = await inventory
              .loadGroupMediaBlobArtifactRelativePaths();
          final reconciled = await _artifactStore
              .cleanupUnreferencedArtifactsForIdentity(
                identityPeerId: identityPeerId,
                referencedRelativePaths: referenced,
                limit: limit > 50 ? 50 : limit,
              );
          progress += reconciled.deleted;
        }
      });
    } on Object {
      // Exact rows retain authority for the next bounded pass. A row already
      // retired before a file failure is recovered by the inventory sweep.
    }
    return progress;
  }

  Future<_GenerationPublication> _publishFreshGeneration({
    required Bridge bridge,
    required GroupMediaBlobCustodyRepository repository,
    required String identityPeerId,
    required StrictGroupContentAuthoringSnapshot snapshot,
    required GroupMessage parent,
    required List<PreparedGroupMediaBlobSource> sources,
  }) async {
    final candidates = <_GroupCandidate>[];
    var stageAttempted = false;
    try {
      for (final source in sources) {
        final encrypted =
            source.preparedArtifact ??
            await _prepareArtifact(
              bridge: bridge,
              localFilePath: source.plaintextPath,
            );
        final artifact = await _artifactStore.persistCandidate(
          identityPeerId: identityPeerId,
          groupId: parent.groupId,
          attachmentId: source.attachment.id,
          encryptedSourcePath: encrypted.encryptedPath,
          expectedContentHash: encrypted.contentHash,
        );
        final custodyBlobId = deterministicGroupMediaCustodyBlobId(
          groupId: parent.groupId,
          messageId: parent.id,
          attachmentId: source.attachment.id,
        );
        final fingerprint = computeGroupMediaBlobCustodyFingerprint(
          groupId: parent.groupId,
          messageId: parent.id,
          attachmentId: source.attachment.id,
          custodyBlobId: custodyBlobId,
          contentHash: artifact.contentHash,
          ciphertextSize: artifact.ciphertextSize,
          recipientPeerIds: snapshot.recipientPeerIds,
        );
        final plaintextSize = await File(source.plaintextPath).length();
        final prepared = source.attachment.copyWith(
          messageId: parent.id,
          size: plaintextSize,
          localPath: source.attachment.localPath ?? source.plaintextPath,
          downloadStatus: 'upload_pending',
          contentHash: artifact.contentHash,
          encryptionKeyBase64: encrypted.keyBase64,
          encryptionNonce: encrypted.nonce,
          encryptionScheme: encrypted.scheme,
          groupMediaBlobCustodyFingerprint: fingerprint,
          ownerLane: MediaOwnerLane.group,
        );
        candidates.add(
          _GroupCandidate(
            encrypted: encrypted,
            artifact: artifact,
            attachment: prepared,
            custodyBlobId: custodyBlobId,
          ),
        );
      }

      final now = _clock().toUtc().toIso8601String();
      final rows = <DirectMediaBlobCustodyRow>[];
      for (final candidate in candidates) {
        for (final recipientPeerId in snapshot.recipientPeerIds) {
          rows.add(
            DirectMediaBlobCustodyRow(
              attachmentId: candidate.attachment.id,
              messageId: parent.id,
              ownerLane: MediaBlobCustodyOwnerLane.group,
              groupId: parent.groupId,
              custodyBlobId: candidate.custodyBlobId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: recipientPeerId,
              contactAccountPeerId: null,
              recipientMlKemPublicKey: null,
              ciphertextRelativePath: candidate.artifact.relativePath,
              custodyKind: groupMediaBlobCustodyKind,
              custodyContract: groupMediaBlobCustodyContract,
              contentHash: candidate.artifact.contentHash,
              ciphertextSize: candidate.artifact.ciphertextSize,
              transportMime: groupMediaBlobTransportMime,
              expiresAtMs: null,
              custodyRelayPeerId: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }
      final stagedParent = parent.copyWith(
        transportPeerId: snapshot.senderTransportPeerId,
        logicalDeliveryId: parent.logicalDeliveryId ?? parent.id,
        keyGeneration: snapshot.key.keyGeneration,
        status: GroupMessage.statusQueuedOffline,
        isIncoming: false,
        isForwarded: parent.isForwarded,
        lastSendAttemptAt: null,
        wireEnvelope: null,
        inboxStored: false,
        inboxRetryPayload: null,
      );
      stageAttempted = true;
      final staged = await repository
          .stageFreshOutgoingGroupMediaBlobGeneration(
            parent: stagedParent,
            attachments: candidates
                .map((candidate) => candidate.attachment)
                .toList(growable: false),
            custodyBlobIdsByAttachmentId: <String, String>{
              for (final candidate in candidates)
                candidate.attachment.id: candidate.custodyBlobId,
            },
            custodyRows: rows,
          );
      if (staged == GroupMediaBlobCustodyStageOutcome.refused) {
        final persistedRows = await repository
            .loadGroupMediaBlobCustodyForMessage(
              groupId: parent.groupId,
              messageId: parent.id,
            );
        await _deleteOnlyUnreferencedCandidates(
          repository: repository,
          identityPeerId: identityPeerId,
          groupId: parent.groupId,
          rows: persistedRows,
          candidates: candidates,
        );
        await _deleteEncryptedTemps(candidates);
        return const _GenerationPublication(
          generation: null,
          hasDurableAuthority: false,
        );
      }
      await _deleteEncryptedTemps(candidates);
      final persistedRows = await repository
          .loadGroupMediaBlobCustodyForMessage(
            groupId: parent.groupId,
            messageId: parent.id,
          );
      final generation = await _reopenGeneration(
        identityPeerId: identityPeerId,
        parent: stagedParent,
        attachments: candidates
            .map((candidate) => candidate.attachment)
            .toList(growable: false),
        rows: persistedRows,
        soleGroupArtifacts: <String, GroupMediaBlobArtifact>{
          if (snapshot.recipientPeerIds.isEmpty)
            for (final candidate in candidates)
              candidate.attachment.id: candidate.artifact,
        },
      );
      return _GenerationPublication(
        generation: generation,
        hasDurableAuthority: true,
      );
    } on Object {
      if (stageAttempted) {
        final rows = await repository.loadGroupMediaBlobCustodyForMessage(
          groupId: parent.groupId,
          messageId: parent.id,
        );
        await _deleteOnlyUnreferencedCandidates(
          repository: repository,
          identityPeerId: identityPeerId,
          groupId: parent.groupId,
          rows: rows,
          candidates: candidates,
        );
      } else {
        await _deleteCandidates(
          identityPeerId: identityPeerId,
          groupId: parent.groupId,
          candidates: candidates,
        );
      }
      await _deleteEncryptedTemps(candidates);
      rethrow;
    }
  }

  Future<_PublishedGroupGeneration?> _reopenGeneration({
    required String identityPeerId,
    required GroupMessage parent,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> rows,
    Map<String, GroupMediaBlobArtifact> soleGroupArtifacts = const {},
  }) async {
    final attachmentById = <String, MediaAttachment>{
      for (final attachment in attachments) attachment.id: attachment,
    };
    if (attachmentById.isEmpty ||
        attachmentById.length != attachments.length ||
        rows.any(
          (row) =>
              row.ownerLane != MediaBlobCustodyOwnerLane.group ||
              row.groupId != parent.groupId ||
              row.messageId != parent.id ||
              row.direction != DirectMediaBlobCustodyDirection.outgoing,
        )) {
      return null;
    }
    final recipientPeerIds =
        rows
            .map((row) => row.recipientPeerId)
            .whereType<String>()
            .toSet()
            .toList(growable: false)
          ..sort();
    if (rows.length != attachmentById.length * recipientPeerIds.length) {
      return null;
    }
    final artifacts = <String, GroupMediaBlobArtifact>{};
    for (final attachment in attachments) {
      final matching = rows
          .where((row) => row.attachmentId == attachment.id)
          .toList(growable: false);
      final custodyBlobId = matching.isEmpty
          ? deterministicGroupMediaCustodyBlobId(
              groupId: parent.groupId,
              messageId: parent.id,
              attachmentId: attachment.id,
            )
          : matching.first.custodyBlobId;
      final ciphertextSize = matching.isEmpty
          ? soleGroupArtifacts[attachment.id]?.ciphertextSize
          : matching.first.ciphertextSize;
      final contentHash = matching.isEmpty
          ? soleGroupArtifacts[attachment.id]?.contentHash
          : matching.first.contentHash;
      if (ciphertextSize == null || contentHash == null) return null;
      final expectedFingerprint = computeGroupMediaBlobCustodyFingerprint(
        groupId: parent.groupId,
        messageId: parent.id,
        attachmentId: attachment.id,
        custodyBlobId: custodyBlobId,
        contentHash: contentHash,
        ciphertextSize: ciphertextSize,
        recipientPeerIds: recipientPeerIds,
      );
      if (attachment.ownerLane != MediaOwnerLane.group ||
          attachment.messageId != parent.id ||
          attachment.contentHash != contentHash ||
          attachment.encryptionKeyBase64 == null ||
          attachment.encryptionNonce == null ||
          attachment.encryptionScheme != groupMediaBlobEncryptionScheme ||
          attachment.groupMediaBlobCustodyFingerprint != expectedFingerprint ||
          matching.length != recipientPeerIds.length ||
          matching.any(
            (row) =>
                row.custodyBlobId != custodyBlobId ||
                row.contentHash != contentHash ||
                row.ciphertextSize != ciphertextSize ||
                row.custodyKind != groupMediaBlobCustodyKind ||
                row.custodyContract != groupMediaBlobCustodyContract ||
                row.transportMime != groupMediaBlobTransportMime ||
                row.ciphertextRelativePath == null ||
                (row.state != DirectMediaBlobCustodyState.outgoingPrepared &&
                    row.state != DirectMediaBlobCustodyState.outgoingStored),
          )) {
        return null;
      }
      final candidate = matching.isEmpty
          ? soleGroupArtifacts[attachment.id]
          : await _artifactStore.verifyOwnedArtifact(
              identityPeerId: identityPeerId,
              groupId: parent.groupId,
              relativePath: matching.first.ciphertextRelativePath!,
              expectedContentHash: contentHash,
              expectedCiphertextSize: ciphertextSize,
            );
      if (candidate == null) return null;
      artifacts[attachment.id] = candidate;
    }
    return _PublishedGroupGeneration(
      parent: parent,
      attachments: List<MediaAttachment>.unmodifiable(attachments),
      rows: List<DirectMediaBlobCustodyRow>.unmodifiable(rows),
      recipientPeerIds: List<String>.unmodifiable(recipientPeerIds),
      artifacts: Map<String, GroupMediaBlobArtifact>.unmodifiable(artifacts),
    );
  }

  Future<PreparedGroupMediaBlobResult> _uploadGeneration({
    required Bridge bridge,
    required GroupMediaBlobCustodyRepository repository,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required String identityPeerId,
    required _PublishedGroupGeneration generation,
  }) async {
    final storedRows = <DirectMediaBlobCustodyRow>[];
    final nowMs = _clock().toUtc().millisecondsSinceEpoch;
    for (final recipientPeerId in generation.recipientPeerIds) {
      for (final attachment in generation.attachments) {
        final seed = generation.rows.singleWhere(
          (row) =>
              row.attachmentId == attachment.id &&
              row.recipientPeerId == recipientPeerId,
        );
        var current = await repository.loadGroupMediaBlobCustodyForTarget(
          groupId: generation.parent.groupId,
          attachmentId: seed.attachmentId,
          custodyBlobId: seed.custodyBlobId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          recipientPeerId: recipientPeerId,
        );
        if (current == null ||
            (!current.exactDatabaseProjectionMatches(seed) &&
                seed.state == DirectMediaBlobCustodyState.outgoingPrepared)) {
          return const PreparedGroupMediaBlobResult.refused(
            hasDurableAuthority: true,
          );
        }
        final proofIsLive =
            current.state == DirectMediaBlobCustodyState.outgoingStored &&
            current.expiresAtMs != null &&
            current.expiresAtMs! > nowMs;
        if (!proofIsLive) {
          final artifact = generation.artifacts[attachment.id]!;
          Map<String, dynamic> response;
          try {
            response = await _strictUpload(
              bridge: bridge,
              custodyBlobId: current.custodyBlobId,
              recipientPeerId: recipientPeerId,
              ciphertextPath: artifact.absolutePath,
              contentHash: current.contentHash,
              ciphertextSize: current.ciphertextSize,
            );
          } on Object {
            return const PreparedGroupMediaBlobResult.retained();
          }
          final receipt = GroupMediaBlobUploadReceipt.parseExact(
            response: response,
            custodyBlobId: current.custodyBlobId,
            contentHash: current.contentHash,
            ciphertextSize: current.ciphertextSize,
          );
          if (receipt == null || receipt.expiresAtMs <= nowMs) {
            return const PreparedGroupMediaBlobResult.retained();
          }
          final next = current.copyWith(
            state: DirectMediaBlobCustodyState.outgoingStored,
            expiresAtMs: receipt.expiresAtMs,
            custodyRelayPeerId: receipt.custodyRelayPeerId,
            updatedAt: _clock().toUtc().toIso8601String(),
          );
          if (!await repository.transitionGroupMediaBlobCustodyIfExact(
            expected: current,
            next: next,
          )) {
            final winner = await repository.loadGroupMediaBlobCustodyForTarget(
              groupId: generation.parent.groupId,
              attachmentId: current.attachmentId,
              custodyBlobId: current.custodyBlobId,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              recipientPeerId: recipientPeerId,
            );
            if (winner == null ||
                winner.state != DirectMediaBlobCustodyState.outgoingStored ||
                winner.contentHash != current.contentHash ||
                winner.ciphertextSize != current.ciphertextSize ||
                winner.expiresAtMs != receipt.expiresAtMs ||
                winner.custodyRelayPeerId != receipt.custodyRelayPeerId) {
              return const PreparedGroupMediaBlobResult.retained();
            }
            current = winner;
          } else {
            current = next;
          }
        }
        if (current.state != DirectMediaBlobCustodyState.outgoingStored ||
            current.expiresAtMs == null ||
            current.expiresAtMs! <= nowMs ||
            current.custodyRelayPeerId?.trim().isEmpty != false) {
          return const PreparedGroupMediaBlobResult.retained();
        }
        storedRows.add(current);
      }
    }

    final manifest = _buildManifest(
      parent: generation.parent,
      attachments: generation.attachments,
      rows: storedRows,
      artifacts: generation.artifacts,
    );
    final completedAttachments = generation.attachments
        .map((attachment) => attachment.copyWith(downloadStatus: 'done'))
        .toList(growable: false);
    final preparedManifest = PreparedGroupMediaManifestAuthority(
      manifest: manifest,
      verifyDurableAuthority: (candidate) => _verifyManifestAuthority(
        repository: repository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityPeerId: identityPeerId,
        manifest: candidate,
        soleGroupArtifacts: generation.recipientPeerIds.isEmpty
            ? generation.artifacts
            : const <String, GroupMediaBlobArtifact>{},
      ),
    );
    return PreparedGroupMediaBlobResult.complete(
      parent: generation.parent,
      attachments: List<MediaAttachment>.unmodifiable(completedAttachments),
      preparedManifest: preparedManifest,
    );
  }

  ProtectedGroupMediaManifest _buildManifest({
    required GroupMessage parent,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> rows,
    required Map<String, GroupMediaBlobArtifact> artifacts,
  }) {
    final sortedIds = attachments.map((attachment) => attachment.id).toList()
      ..sort();
    return ProtectedGroupMediaManifest(
      groupId: parent.groupId,
      messageId: parent.id,
      attachments: attachments.map((attachment) {
        final targetRows = rows
            .where((row) => row.attachmentId == attachment.id)
            .toList(growable: false);
        final artifact = artifacts[attachment.id]!;
        return ProtectedGroupMediaAttachmentCommitment(
          attachmentId: attachment.id,
          custodyBlobId: targetRows.isEmpty
              ? deterministicGroupMediaCustodyBlobId(
                  groupId: parent.groupId,
                  messageId: parent.id,
                  attachmentId: attachment.id,
                )
              : targetRows.first.custodyBlobId,
          ciphertextSha256: artifact.contentHash,
          ciphertextSize: artifact.ciphertextSize,
          mime: attachment.mime,
          mediaType: attachment.mediaType,
          width: attachment.width,
          height: attachment.height,
          durationMs: attachment.durationMs,
          waveform: attachment.waveform,
          encryptionKeyBase64: attachment.encryptionKeyBase64!,
          encryptionNonce: attachment.encryptionNonce!,
          encryptionScheme: attachment.encryptionScheme!,
          caption: attachment.id == sortedIds.first && parent.text.isNotEmpty
              ? parent.text
              : null,
          targets: targetRows.map(
            (row) => GroupMediaBlobTargetCommitment(
              recipientPeerId: row.recipientPeerId!,
              expiresAtMs: row.expiresAtMs!,
            ),
          ),
        );
      }),
    );
  }

  Future<bool> _verifyManifestAuthority({
    required GroupMediaBlobCustodyRepository repository,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required String identityPeerId,
    required ProtectedGroupMediaManifest manifest,
    Map<String, GroupMediaBlobArtifact> soleGroupArtifacts = const {},
  }) async {
    final attachments = await mediaAttachmentRepository
        .getAttachmentsForMessage(
          manifest.messageId,
          owner: MediaOwnerLane.group,
        );
    final attachmentById = <String, MediaAttachment>{
      for (final attachment in attachments) attachment.id: attachment,
    };
    if (attachmentById.length != manifest.attachments.length) return false;
    final rows = await repository.loadGroupMediaBlobCustodyForMessage(
      groupId: manifest.groupId,
      messageId: manifest.messageId,
    );
    if (rows.length !=
        manifest.attachments.length * manifest.recipientPeerIds.length) {
      return false;
    }
    for (final commitment in manifest.attachments) {
      final attachment = attachmentById[commitment.attachmentId];
      final expectedFingerprint = computeGroupMediaBlobCustodyFingerprint(
        groupId: manifest.groupId,
        messageId: manifest.messageId,
        attachmentId: commitment.attachmentId,
        custodyBlobId: commitment.custodyBlobId,
        contentHash: commitment.ciphertextSha256,
        ciphertextSize: commitment.ciphertextSize,
        recipientPeerIds: manifest.recipientPeerIds,
      );
      if (attachment == null ||
          attachment.groupMediaBlobCustodyFingerprint != expectedFingerprint ||
          attachment.contentHash != commitment.ciphertextSha256 ||
          attachment.encryptionKeyBase64 != commitment.encryptionKeyBase64 ||
          attachment.encryptionNonce != commitment.encryptionNonce ||
          attachment.encryptionScheme != commitment.encryptionScheme) {
        return false;
      }
      String? relativePath;
      for (final target in commitment.targets) {
        final row = await repository.loadGroupMediaBlobCustodyForTarget(
          groupId: manifest.groupId,
          attachmentId: commitment.attachmentId,
          custodyBlobId: commitment.custodyBlobId,
          direction: DirectMediaBlobCustodyDirection.outgoing,
          recipientPeerId: target.recipientPeerId,
        );
        if (row == null ||
            row.state != DirectMediaBlobCustodyState.outgoingStored ||
            row.contentHash != commitment.ciphertextSha256 ||
            row.ciphertextSize != commitment.ciphertextSize ||
            row.expiresAtMs != target.expiresAtMs ||
            row.custodyKind != target.custodyKind ||
            row.custodyContract != target.custodyContract ||
            row.ciphertextRelativePath == null ||
            (relativePath != null &&
                relativePath != row.ciphertextRelativePath)) {
          return false;
        }
        relativePath = row.ciphertextRelativePath;
      }
      final artifact = relativePath == null
          ? soleGroupArtifacts[commitment.attachmentId]
          : await _artifactStore.verifyOwnedArtifact(
              identityPeerId: identityPeerId,
              groupId: manifest.groupId,
              relativePath: relativePath,
              expectedContentHash: commitment.ciphertextSha256,
              expectedCiphertextSize: commitment.ciphertextSize,
            );
      if (artifact == null) return false;
    }
    return true;
  }

  Future<bool> _validateSources(
    List<PreparedGroupMediaBlobSource> sources,
  ) async {
    final sanitized = <MediaAttachment>[];
    for (final source in sources) {
      final descriptor = await GroupMediaMimePolicy.validateFile(
        path: source.plaintextPath,
        mime: source.attachment.mime,
        mediaType: source.attachment.mediaType,
      );
      if (!descriptor.isValid) return false;
      final size = await File(source.plaintextPath).length();
      if (size != source.attachment.size) return false;
      sanitized.add(
        GroupMediaMimePolicy.sanitizeAttachment(
          source.attachment.copyWith(size: size),
        ),
      );
    }
    return GroupMediaSizePolicy.validateAttachments(sanitized).isValid;
  }

  bool _validFreshRequest(
    String identityPeerId,
    GroupMessage parent,
    List<PreparedGroupMediaBlobSource> sources,
  ) {
    final ids = sources.map((source) => source.attachment.id).toSet();
    return _trimmed(identityPeerId) &&
        _trimmed(parent.id) &&
        _trimmed(parent.groupId) &&
        sources.isNotEmpty &&
        sources.length <= _maximumStrictGroupMediaAttachments &&
        ids.length == sources.length &&
        sources.every(
          (source) =>
              _trimmed(source.attachment.id) &&
              _trimmed(source.plaintextPath) &&
              source.attachment.messageId == parent.id &&
              (source.attachment.ownerLane == null ||
                  source.attachment.ownerLane == MediaOwnerLane.group) &&
              source.attachment.groupMediaBlobCustodyFingerprint == null,
        );
  }

  Future<void> _deleteOnlyUnreferencedCandidates({
    required GroupMediaBlobCustodyRepository repository,
    required String identityPeerId,
    required String groupId,
    required List<DirectMediaBlobCustodyRow> rows,
    required List<_GroupCandidate> candidates,
  }) async {
    for (final candidate in candidates) {
      final referenced = rows.any(
        (row) =>
            row.ciphertextRelativePath == candidate.artifact.relativePath &&
            row.contentHash == candidate.artifact.contentHash &&
            row.ciphertextSize == candidate.artifact.ciphertextSize,
      );
      if (referenced) continue;
      await _artifactStore.deleteOwnedArtifact(
        identityPeerId: identityPeerId,
        groupId: groupId,
        relativePath: candidate.artifact.relativePath,
      );
    }
  }

  Future<void> _deleteCandidates({
    required String identityPeerId,
    required String groupId,
    required List<_GroupCandidate> candidates,
  }) async {
    for (final candidate in candidates) {
      await _artifactStore.deleteOwnedArtifact(
        identityPeerId: identityPeerId,
        groupId: groupId,
        relativePath: candidate.artifact.relativePath,
      );
    }
  }

  Future<void> _deleteEncryptedTemps(List<_GroupCandidate> candidates) async {
    for (final candidate in candidates) {
      final path = candidate.encrypted.encryptedPath;
      if (path == candidate.artifact.absolutePath) continue;
      try {
        if (await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.file) {
          await File(path).delete();
        }
      } on Object {
        // A verified durable artifact already owns retry authority.
      }
    }
  }

  Future<void> _cleanupSoleGroupArtifacts({
    required String identityPeerId,
    required ProtectedGroupMediaManifest manifest,
  }) => _artifactStore.cleanupUnreferencedArtifacts(
    identityPeerId: identityPeerId,
    groupId: manifest.groupId,
    referencedRelativePaths: const <String>{},
    limit: _maximumStrictGroupMediaAttachments,
  );
}

final class _GroupCandidate {
  const _GroupCandidate({
    required this.encrypted,
    required this.artifact,
    required this.attachment,
    required this.custodyBlobId,
  });

  final EncryptedMediaArtifact encrypted;
  final GroupMediaBlobArtifact artifact;
  final MediaAttachment attachment;
  final String custodyBlobId;
}

final class _PublishedGroupGeneration {
  const _PublishedGroupGeneration({
    required this.parent,
    required this.attachments,
    required this.rows,
    required this.recipientPeerIds,
    required this.artifacts,
  });

  final GroupMessage parent;
  final List<MediaAttachment> attachments;
  final List<DirectMediaBlobCustodyRow> rows;
  final List<String> recipientPeerIds;
  final Map<String, GroupMediaBlobArtifact> artifacts;
}

final class _GenerationPublication {
  const _GenerationPublication({
    required this.generation,
    required this.hasDurableAuthority,
  });

  final _PublishedGroupGeneration? generation;
  final bool hasDurableAuthority;
}

bool _trimmed(String value) => value.trim().isNotEmpty && value == value.trim();

Future<Map<String, dynamic>> _callStrictGroupUpload({
  required Bridge bridge,
  required String custodyBlobId,
  required String recipientPeerId,
  required String ciphertextPath,
  required String contentHash,
  required int ciphertextSize,
}) => callP2PMediaUpload(
  bridge,
  id: custodyBlobId,
  toPeerId: recipientPeerId,
  mime: groupMediaBlobTransportMime,
  filePath: ciphertextPath,
  custodyContract: groupMediaBlobCustodyContract,
  custodyKind: groupMediaBlobCustodyKind,
  contentHash: contentHash,
  payloadSizeBytes: ciphertextSize,
);
