import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

typedef DirectMediaBlobStrictUploadFn =
    Future<Map<String, dynamic>> Function({
      required Bridge bridge,
      required String attachmentId,
      required String recipientPeerId,
      required String ciphertextPath,
      required String contentHash,
      required int ciphertextSize,
    });

typedef DirectMediaBlobGenerationReadyFn =
    Future<void> Function(List<PreparedDirectMediaBlobArtifact> artifacts);

typedef DirectMediaBlobAuthorityReadyFn =
    Future<bool> Function(List<MediaAttachment> authoritativeAttachments);

final class PreparedDirectMediaBlobSource {
  const PreparedDirectMediaBlobSource({
    required this.attachment,
    required this.plaintextPath,
    this.preparedArtifact,
  });

  final MediaAttachment attachment;
  final String plaintextPath;

  /// An encrypt-once candidate that has not yet been sent over any transport.
  /// The coordinator publishes its durable copy before exposing it to the
  /// post-publication LAN callback.
  final EncryptedMediaArtifact? preparedArtifact;
}

final class PreparedDirectMediaBlobArtifact {
  const PreparedDirectMediaBlobArtifact({
    required this.attachment,
    required this.custody,
    required this.absoluteCiphertextPath,
  });

  final MediaAttachment attachment;
  final DirectMediaBlobCustodyRow custody;
  final String absoluteCiphertextPath;
}

enum PreparedDirectMediaBlobUploadState { complete, retained, refused }

final class PreparedDirectMediaBlobUploadResult {
  const PreparedDirectMediaBlobUploadResult._({
    required this.state,
    required this.hasDurableAuthority,
    this.attachments = const <MediaAttachment>[],
  });

  const PreparedDirectMediaBlobUploadResult.complete(
    List<MediaAttachment> attachments,
  ) : this._(
        state: PreparedDirectMediaBlobUploadState.complete,
        hasDurableAuthority: true,
        attachments: attachments,
      );

  const PreparedDirectMediaBlobUploadResult.retained({
    this.hasDurableAuthority = true,
  }) : state = PreparedDirectMediaBlobUploadState.retained,
       attachments = const <MediaAttachment>[];

  const PreparedDirectMediaBlobUploadResult.refused({
    this.hasDurableAuthority = false,
  }) : state = PreparedDirectMediaBlobUploadState.refused,
       attachments = const <MediaAttachment>[];

  final PreparedDirectMediaBlobUploadState state;
  final bool hasDurableAuthority;
  final List<MediaAttachment> attachments;

  bool get isComplete => state == PreparedDirectMediaBlobUploadState.complete;
}

/// Sole sender-side owner of Plan 347 strict media network calls.
///
/// Fresh producers must publish the complete message generation through v111
/// before this owner invokes [onGenerationReady] or the relay. Retry callers
/// use [reopenAndUpload] and can never create a missing generation.
final class PreparedDirectMediaBlobCustodyCoordinator {
  PreparedDirectMediaBlobCustodyCoordinator({
    required DirectMediaBlobCustodyRepository repository,
    required DirectMediaBlobArtifactStore artifactStore,
    PrepareEncryptedMediaArtifactFn prepareArtifact =
        prepareEncryptedMediaArtifact,
    DirectMediaBlobStrictUploadFn? strictUpload,
    DateTime Function()? clock,
  }) : _repository = repository,
       _artifactStore = artifactStore,
       _prepareArtifact = prepareArtifact,
       _strictUploadFn = strictUpload ?? _callStrictUpload,
       _clock = clock ?? DateTime.now;

  final DirectMediaBlobCustodyRepository _repository;
  final DirectMediaBlobArtifactStore _artifactStore;
  final PrepareEncryptedMediaArtifactFn _prepareArtifact;
  final DirectMediaBlobStrictUploadFn _strictUploadFn;
  final DateTime Function() _clock;

  Future<PreparedDirectMediaBlobUploadResult> prepareAndUploadFresh({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage expectedParent,
    required List<PreparedDirectMediaBlobSource> sources,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    if (!_repository.supportsDirectMediaBlobCustody ||
        !_validFreshRequest(
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          parent: expectedParent,
          sources: sources,
        )) {
      return const PreparedDirectMediaBlobUploadResult.refused();
    }

    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final publication = await _publishFreshGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          expectedParent: expectedParent,
          sources: sources,
        );
        final generation = publication.generation;
        if (generation == null) {
          return PreparedDirectMediaBlobUploadResult.refused(
            hasDurableAuthority: publication.hasDurableAuthority,
          );
        }
        return _uploadPublishedGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          generation: generation,
          onGenerationReady: onGenerationReady,
        );
      });
    } on Object {
      return const PreparedDirectMediaBlobUploadResult.refused();
    }
  }

  /// Plan 348 absent-parent entry used only by an eligible external OS share.
  ///
  /// [onAuthorityReady] copies/verifies the sender-local plaintext preview after
  /// v110/v111 commit and before LAN or relay. Its failure retains ciphertext
  /// authority for the existing restart retry owner.
  Future<PreparedDirectMediaBlobUploadResult> prepareAndUploadFreshMessage({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage parent,
    required List<PreparedDirectMediaBlobSource> sources,
    required DirectMediaBlobAuthorityReadyFn onAuthorityReady,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    final freshRepository = switch (_repository) {
      FreshOutgoingDirectMediaBlobGenerationRepository repository
          when repository.supportsFreshOutgoingDirectMediaBlobGeneration =>
        repository,
      _ => null,
    };
    if (!_repository.supportsDirectMediaBlobCustody ||
        freshRepository == null ||
        !_validFreshRequest(
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          parent: parent,
          sources: sources,
        ) ||
        parent.id != parent.dedupKey ||
        parent.timestamp != parent.createdAt ||
        parent.isForwarded) {
      return const PreparedDirectMediaBlobUploadResult.refused();
    }

    var hasDurableAuthority = false;
    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final publication = await _publishFreshGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          expectedParent: parent,
          sources: sources,
          freshRepository: freshRepository,
        );
        hasDurableAuthority = publication.hasDurableAuthority;
        final generation = publication.generation;
        if (generation == null) {
          return hasDurableAuthority
              ? const PreparedDirectMediaBlobUploadResult.retained()
              : const PreparedDirectMediaBlobUploadResult.refused();
        }
        bool previewReady;
        try {
          previewReady = await onAuthorityReady(
            List<MediaAttachment>.unmodifiable(
              generation.artifacts
                  .map((artifact) => artifact.attachment)
                  .toList(growable: false),
            ),
          );
        } on Object {
          previewReady = false;
        }
        if (!previewReady) {
          return const PreparedDirectMediaBlobUploadResult.retained();
        }
        return _uploadPublishedGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          generation: generation,
          onGenerationReady: onGenerationReady,
        );
      });
    } on Object {
      return hasDurableAuthority
          ? const PreparedDirectMediaBlobUploadResult.retained()
          : const PreparedDirectMediaBlobUploadResult.refused();
    }
  }

  Future<PreparedDirectMediaBlobUploadResult> reopenAndUpload({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    if (!_repository.supportsDirectMediaBlobCustody ||
        identityPeerId.trim() != identityPeerId ||
        identityPeerId.isEmpty ||
        recipientPeerId.trim() != recipientPeerId ||
        recipientPeerId.isEmpty ||
        expectedParent.id.isEmpty ||
        expectedParent.contactPeerId != recipientPeerId ||
        expectedParent.isIncoming ||
        expectedParent.isDeleted ||
        expectedParent.isHidden ||
        expectedParent.directMediaCustodyIntentId == null ||
        expectedAttachments.isEmpty) {
      return const PreparedDirectMediaBlobUploadResult.refused();
    }
    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final rows = await _repository.loadDirectMediaBlobCustodyForMessage(
          expectedParent.id,
        );
        if (rows.isEmpty || rows.length != expectedAttachments.length) {
          return const PreparedDirectMediaBlobUploadResult.refused();
        }
        // Reuse the existing-generation branch of the atomic staging CAS as a
        // reopen authority check. Because a non-empty generation was loaded
        // while this lifecycle lease is held, this call cannot mint v111; it
        // must prove that the current parent, complete attachment projection,
        // v108 absence, and every current prepared/stored row still match.
        final revalidated = await _repository
            .stageOutgoingDirectMediaBlobGeneration(
              expectedParent: expectedParent,
              expectedAttachments: expectedAttachments
                  .map(
                    (attachment) => attachment.copyWith(
                      clearContentHash: true,
                      clearThumbnailHash: true,
                      clearEncryptionKeyBase64: true,
                      clearEncryptionNonce: true,
                      clearEncryptionScheme: true,
                      clearBlobCustody: true,
                      clearDirectMediaBlobCustodyFingerprint: true,
                    ),
                  )
                  .toList(growable: false),
              preparedAttachments: expectedAttachments,
              custodyRows: rows
                  .map(
                    (row) => row.copyWith(
                      state: DirectMediaBlobCustodyState.outgoingPrepared,
                      inboxCustodyIncarnationId: null,
                      expiresAtMs: null,
                      custodyRelayPeerId: null,
                    ),
                  )
                  .toList(growable: false),
            );
        if (revalidated.outcome !=
            DirectMediaBlobGenerationStageOutcome.idempotent) {
          return const PreparedDirectMediaBlobUploadResult.refused();
        }
        final generation = await _reopenCompleteGeneration(
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          messageId: expectedParent.id,
          attachments: revalidated.attachments,
          rows: revalidated.custodyRows,
        );
        if (generation == null) {
          return const PreparedDirectMediaBlobUploadResult.refused();
        }
        return _uploadPublishedGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          generation: generation,
          onGenerationReady: onGenerationReady,
        );
      });
    } on Object {
      return const PreparedDirectMediaBlobUploadResult.refused();
    }
  }

  Future<_GenerationPublication> _publishFreshGeneration({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage expectedParent,
    required List<PreparedDirectMediaBlobSource> sources,
    FreshOutgoingDirectMediaBlobGenerationRepository? freshRepository,
  }) async {
    final candidates = <_CandidateGenerationEntry>[];
    var stageAttempted = false;
    var hasDurableAuthority = false;
    try {
      for (final source in sources) {
        final encrypted =
            source.preparedArtifact ??
            await _prepareArtifact(
              bridge: bridge,
              localFilePath: source.plaintextPath,
            );
        final candidate = await _artifactStore.persistCandidate(
          identityPeerId: identityPeerId,
          attachmentId: source.attachment.id,
          encryptedSourcePath: encrypted.encryptedPath,
          expectedContentHash: encrypted.contentHash,
        );
        candidates.add(
          _CandidateGenerationEntry(
            source: source,
            encrypted: encrypted,
            artifact: candidate,
          ),
        );
      }

      final now = _clock().toUtc().toIso8601String();
      final prepared = <MediaAttachment>[];
      final custodyRows = <DirectMediaBlobCustodyRow>[];
      for (final candidate in candidates) {
        final source = candidate.source;
        final encrypted = candidate.encrypted;
        final artifact = candidate.artifact;
        prepared.add(
          source.attachment.copyWith(
            contentHash: artifact.contentHash,
            encryptionKeyBase64: encrypted.keyBase64,
            encryptionNonce: encrypted.nonce,
            encryptionScheme: encrypted.scheme,
            downloadStatus: 'upload_pending',
            ownerLane: MediaOwnerLane.direct,
          ),
        );
        custodyRows.add(
          DirectMediaBlobCustodyRow(
            attachmentId: source.attachment.id,
            messageId: expectedParent.id,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingPrepared,
            inboxCustodyIncarnationId: null,
            recipientPeerId: recipientPeerId,
            ciphertextRelativePath: artifact.relativePath,
            contentHash: artifact.contentHash,
            ciphertextSize: artifact.ciphertextSize,
            expiresAtMs: null,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      stageAttempted = true;
      final expectedAttachments = sources
          .map((source) => source.attachment)
          .toList(growable: false);
      late final bool authorizesStrictUpload;
      late final bool idempotent;
      late final List<MediaAttachment> stagedAttachments;
      late final List<DirectMediaBlobCustodyRow> stagedRows;
      if (freshRepository == null) {
        final staged = await _repository.stageOutgoingDirectMediaBlobGeneration(
          expectedParent: expectedParent,
          expectedAttachments: expectedAttachments,
          preparedAttachments: prepared,
          custodyRows: custodyRows,
        );
        authorizesStrictUpload = staged.authorizesStrictUpload;
        hasDurableAuthority = staged.authorizesStrictUpload;
        idempotent =
            staged.outcome == DirectMediaBlobGenerationStageOutcome.idempotent;
        stagedAttachments = staged.attachments;
        stagedRows = staged.custodyRows;
      } else {
        final staged = await freshRepository
            .stageFreshOutgoingDirectMediaBlobGeneration(
              parent: expectedParent,
              expectedAttachments: expectedAttachments,
              preparedAttachments: prepared,
              custodyRows: custodyRows,
            );
        authorizesStrictUpload = staged.authorizesStrictUpload;
        hasDurableAuthority = staged.hasDurableAuthority;
        idempotent =
            staged.outcome == DirectMediaBlobGenerationStageOutcome.idempotent;
        stagedAttachments = staged.attachments;
        stagedRows = staged.custodyRows;
      }
      if (!authorizesStrictUpload) {
        if (hasDurableAuthority) {
          await _deleteOnlyProvablyUnreferencedCandidates(
            identityPeerId: identityPeerId,
            messageId: expectedParent.id,
            candidates: candidates,
          );
        } else {
          await _deleteCandidates(identityPeerId, candidates);
        }
        await _deleteEncryptedTemps(candidates);
        return _GenerationPublication(
          generation: null,
          hasDurableAuthority: hasDurableAuthority,
        );
      }
      if (idempotent) {
        await _deleteCandidates(identityPeerId, candidates);
      }
      await _deleteEncryptedTemps(candidates);
      final generation = await _reopenCompleteGeneration(
        identityPeerId: identityPeerId,
        recipientPeerId: recipientPeerId,
        messageId: expectedParent.id,
        attachments: stagedAttachments,
        rows: stagedRows,
      );
      return _GenerationPublication(
        generation: generation,
        hasDurableAuthority: true,
      );
    } on Object {
      if (stageAttempted) {
        await _deleteOnlyProvablyUnreferencedCandidates(
          identityPeerId: identityPeerId,
          messageId: expectedParent.id,
          candidates: candidates,
        );
      } else {
        await _deleteCandidates(identityPeerId, candidates);
      }
      await _deleteEncryptedTemps(candidates);
      if (hasDurableAuthority) {
        return const _GenerationPublication(
          generation: null,
          hasDurableAuthority: true,
        );
      }
      rethrow;
    }
  }

  Future<_PublishedGeneration?> _reopenCompleteGeneration({
    required String identityPeerId,
    required String recipientPeerId,
    required String messageId,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> rows,
  }) async {
    final attachmentById = <String, MediaAttachment>{
      for (final attachment in attachments) attachment.id: attachment,
    };
    final rowById = <String, DirectMediaBlobCustodyRow>{
      for (final row in rows) row.attachmentId: row,
    };
    if (attachmentById.length != attachments.length ||
        rowById.length != rows.length ||
        attachmentById.isEmpty ||
        attachmentById.keys
            .toSet()
            .difference(rowById.keys.toSet())
            .isNotEmpty ||
        rowById.keys
            .toSet()
            .difference(attachmentById.keys.toSet())
            .isNotEmpty) {
      return null;
    }
    final artifacts = <PreparedDirectMediaBlobArtifact>[];
    final orderedIds = attachmentById.keys.toList()..sort();
    for (final attachmentId in orderedIds) {
      final attachment = attachmentById[attachmentId]!;
      final row = rowById[attachmentId]!;
      final eligibleState =
          row.state == DirectMediaBlobCustodyState.outgoingPrepared ||
          row.state == DirectMediaBlobCustodyState.outgoingStored;
      final storedProofIsLive =
          row.state != DirectMediaBlobCustodyState.outgoingStored ||
          (row.expiresAtMs != null &&
              row.expiresAtMs! > _clock().toUtc().millisecondsSinceEpoch);
      if (!eligibleState ||
          !storedProofIsLive ||
          row.direction != DirectMediaBlobCustodyDirection.outgoing ||
          row.inboxCustodyIncarnationId != null ||
          row.messageId != messageId ||
          row.recipientPeerId != recipientPeerId ||
          attachment.messageId != messageId ||
          attachment.ownerLane != MediaOwnerLane.direct ||
          attachment.contentHash != row.contentHash ||
          attachment.encryptionKeyBase64 == null ||
          attachment.encryptionNonce == null ||
          attachment.encryptionScheme !=
              kMediaAttachmentEncryptionSchemeBlobAesGcmV1 ||
          row.ciphertextRelativePath == null) {
        return null;
      }
      final artifact = await _artifactStore.verifyOwnedArtifact(
        identityPeerId: identityPeerId,
        relativePath: row.ciphertextRelativePath!,
        expectedContentHash: row.contentHash,
        expectedCiphertextSize: row.ciphertextSize,
      );
      if (artifact == null) return null;
      artifacts.add(
        PreparedDirectMediaBlobArtifact(
          attachment: attachment,
          custody: row,
          absoluteCiphertextPath: artifact.absolutePath,
        ),
      );
    }
    return _PublishedGeneration(artifacts);
  }

  Future<PreparedDirectMediaBlobUploadResult> _uploadPublishedGeneration({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required _PublishedGeneration generation,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    // Both public entry points hold the repository-wide lifecycle lease for
    // this entire method. Revalidate the complete generation before exposing
    // even the LAN acceleration callback; cancellation, parent deletion, and
    // proof-expiry terminalization therefore either win before this preflight
    // (and are refused here) or wait until every network side effect finishes.
    final liveArtifacts = <PreparedDirectMediaBlobArtifact>[];
    final preflightNowMs = _clock().toUtc().millisecondsSinceEpoch;
    for (final entry in generation.artifacts) {
      final current = await _repository.loadDirectMediaBlobCustodyForAttachment(
        entry.custody.attachmentId,
      );
      final eligibleState =
          current?.state == DirectMediaBlobCustodyState.outgoingPrepared ||
          current?.state == DirectMediaBlobCustodyState.outgoingStored;
      final storedProofIsLive =
          current?.state != DirectMediaBlobCustodyState.outgoingStored ||
          (current?.expiresAtMs != null &&
              current!.expiresAtMs! > preflightNowMs);
      if (current == null ||
          !current.exactDatabaseProjectionMatches(entry.custody) ||
          !eligibleState ||
          !storedProofIsLive ||
          current.inboxCustodyIncarnationId != null ||
          current.recipientPeerId != recipientPeerId) {
        return const PreparedDirectMediaBlobUploadResult.refused(
          hasDurableAuthority: true,
        );
      }
      final artifact = await _artifactStore.verifyOwnedArtifact(
        identityPeerId: identityPeerId,
        relativePath: current.ciphertextRelativePath!,
        expectedContentHash: current.contentHash,
        expectedCiphertextSize: current.ciphertextSize,
      );
      if (artifact == null) {
        return const PreparedDirectMediaBlobUploadResult.refused(
          hasDurableAuthority: true,
        );
      }
      liveArtifacts.add(
        PreparedDirectMediaBlobArtifact(
          attachment: entry.attachment,
          custody: current,
          absoluteCiphertextPath: artifact.absolutePath,
        ),
      );
    }

    final generationReadyNowMs = _clock().toUtc().millisecondsSinceEpoch;
    if (liveArtifacts.any(
      (entry) =>
          entry.custody.state == DirectMediaBlobCustodyState.outgoingStored &&
          (entry.custody.expiresAtMs == null ||
              entry.custody.expiresAtMs! <= generationReadyNowMs),
    )) {
      return const PreparedDirectMediaBlobUploadResult.refused(
        hasDurableAuthority: true,
      );
    }

    if (onGenerationReady != null) {
      try {
        await onGenerationReady(
          List<PreparedDirectMediaBlobArtifact>.unmodifiable(liveArtifacts),
        );
      } on Object {
        // LAN is an acceleration only. The already-published strict relay
        // generation remains the durable path.
      }
    }

    final completed = <MediaAttachment>[];
    for (final entry in liveArtifacts) {
      var row = entry.custody;
      if (row.state == DirectMediaBlobCustodyState.outgoingPrepared) {
        Map<String, dynamic> response;
        try {
          response = await _strictUploadFn(
            bridge: bridge,
            attachmentId: row.attachmentId,
            recipientPeerId: recipientPeerId,
            ciphertextPath: entry.absoluteCiphertextPath,
            contentHash: row.contentHash,
            ciphertextSize: row.ciphertextSize,
          );
        } on Object {
          return const PreparedDirectMediaBlobUploadResult.retained();
        }
        final receipt = DirectMediaBlobUploadReceipt.parseExact(
          response: response,
          attachmentId: row.attachmentId,
          contentHash: row.contentHash,
          ciphertextSize: row.ciphertextSize,
        );
        if (receipt == null ||
            receipt.commitment.expiresAtMs <=
                _clock().toUtc().millisecondsSinceEpoch) {
          return const PreparedDirectMediaBlobUploadResult.retained();
        }
        final next = row.copyWith(
          state: DirectMediaBlobCustodyState.outgoingStored,
          expiresAtMs: receipt.commitment.expiresAtMs,
          custodyRelayPeerId: receipt.custodyRelayPeerId,
          updatedAt: _clock().toUtc().toIso8601String(),
        );
        if (!await _repository.transitionDirectMediaBlobCustodyIfExact(
          expected: row,
          next: next,
        )) {
          final winner = await _repository
              .loadDirectMediaBlobCustodyForAttachment(row.attachmentId);
          if (winner == null ||
              winner.state != DirectMediaBlobCustodyState.outgoingStored ||
              winner.contentHash != row.contentHash ||
              winner.ciphertextSize != row.ciphertextSize ||
              winner.expiresAtMs != receipt.commitment.expiresAtMs ||
              winner.custodyRelayPeerId != receipt.custodyRelayPeerId) {
            return const PreparedDirectMediaBlobUploadResult.retained();
          }
          row = winner;
        } else {
          row = next;
        }
      }
      if (row.expiresAtMs == null ||
          row.expiresAtMs! <= _clock().toUtc().millisecondsSinceEpoch ||
          row.custodyRelayPeerId == null ||
          row.custodyRelayPeerId!.isEmpty ||
          row.custodyRelayPeerId!.trim() != row.custodyRelayPeerId) {
        return const PreparedDirectMediaBlobUploadResult.retained();
      }
      completed.add(
        entry.attachment.copyWith(
          downloadStatus: 'done',
          blobCustody: DirectMediaBlobCustodyCommitment(
            contentHash: row.contentHash,
            ciphertextSize: row.ciphertextSize,
            expiresAtMs: row.expiresAtMs!,
          ),
        ),
      );
    }
    return PreparedDirectMediaBlobUploadResult.complete(
      List<MediaAttachment>.unmodifiable(completed),
    );
  }

  bool _validFreshRequest({
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage parent,
    required List<PreparedDirectMediaBlobSource> sources,
  }) {
    final ids = sources.map((source) => source.attachment.id).toList();
    return identityPeerId.isNotEmpty &&
        identityPeerId == identityPeerId.trim() &&
        recipientPeerId.isNotEmpty &&
        recipientPeerId == recipientPeerId.trim() &&
        !parent.isIncoming &&
        !parent.isDeleted &&
        !parent.isHidden &&
        parent.senderPeerId == identityPeerId &&
        parent.contactPeerId == recipientPeerId &&
        parent.directMediaCustodyIntentId != null &&
        sources.isNotEmpty &&
        ids.toSet().length == sources.length &&
        sources.every(
          (source) =>
              source.attachment.messageId == parent.id &&
              source.attachment.ownerLane == MediaOwnerLane.direct &&
              source.attachment.downloadStatus == 'upload_pending' &&
              source.attachment.contentHash == null &&
              source.attachment.encryptionKeyBase64 == null &&
              source.attachment.encryptionNonce == null &&
              source.attachment.encryptionScheme == null &&
              source.plaintextPath.isNotEmpty,
        );
  }

  Future<void> _deleteCandidates(
    String identityPeerId,
    List<_CandidateGenerationEntry> entries,
  ) async {
    for (final entry in entries) {
      await _artifactStore.deleteOwnedArtifact(
        identityPeerId: identityPeerId,
        relativePath: entry.artifact.relativePath,
      );
    }
  }

  Future<void> _deleteOnlyProvablyUnreferencedCandidates({
    required String identityPeerId,
    required String messageId,
    required List<_CandidateGenerationEntry> candidates,
  }) async {
    List<DirectMediaBlobCustodyRow> currentRows;
    try {
      currentRows = await _repository.loadDirectMediaBlobCustodyForMessage(
        messageId,
      );
    } on Object {
      // A stage CAS may already have committed. If DB authority cannot be
      // inspected, retaining bounded candidates is safer than deleting the
      // ciphertext referenced by an outgoing_prepared winner.
      return;
    }
    for (final candidate in candidates) {
      final artifact = candidate.artifact;
      final referenced = currentRows.any(
        (row) =>
            row.direction == DirectMediaBlobCustodyDirection.outgoing &&
            row.ciphertextRelativePath == artifact.relativePath &&
            row.contentHash == artifact.contentHash &&
            row.ciphertextSize == artifact.ciphertextSize,
      );
      if (referenced) continue;
      await _artifactStore.deleteOwnedArtifact(
        identityPeerId: identityPeerId,
        relativePath: artifact.relativePath,
      );
    }
  }

  Future<void> _deleteEncryptedTemps(
    List<_CandidateGenerationEntry> entries,
  ) async {
    for (final entry in entries) {
      final path = entry.encrypted.encryptedPath;
      if (path == entry.artifact.absolutePath) continue;
      try {
        if (await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.file) {
          await File(path).delete();
        }
      } on Object {
        // The durable candidate is already verified. A stale bridge temp is a
        // bounded orphan and must not invalidate the published generation.
      }
    }
  }
}

final class _CandidateGenerationEntry {
  const _CandidateGenerationEntry({
    required this.source,
    required this.encrypted,
    required this.artifact,
  });

  final PreparedDirectMediaBlobSource source;
  final EncryptedMediaArtifact encrypted;
  final DirectMediaBlobArtifact artifact;
}

final class _PublishedGeneration {
  const _PublishedGeneration(this.artifacts);

  final List<PreparedDirectMediaBlobArtifact> artifacts;
}

final class _GenerationPublication {
  const _GenerationPublication({
    required this.generation,
    required this.hasDurableAuthority,
  });

  final _PublishedGeneration? generation;
  final bool hasDurableAuthority;
}

Future<Map<String, dynamic>> _callStrictUpload({
  required Bridge bridge,
  required String attachmentId,
  required String recipientPeerId,
  required String ciphertextPath,
  required String contentHash,
  required int ciphertextSize,
}) => callP2PMediaUpload(
  bridge,
  id: attachmentId,
  toPeerId: recipientPeerId,
  mime: kDirectMediaBlobTransportMime,
  filePath: ciphertextPath,
  custodyContract: kDirectMediaBlobCustodyContract,
  custodyKind: kDirectMediaBlobCustodyKind,
  contentHash: contentHash,
  payloadSizeBytes: ciphertextSize,
);
