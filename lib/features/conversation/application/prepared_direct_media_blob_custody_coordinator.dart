import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
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

/// Result of one Plan 362 all-target fanout preparation/upload pass.
///
/// [targetRows] maps each physical recipient to its exact STORED v114 rows;
/// [attachments] is the completed projection carrying the blob commitment of
/// the LEGACY-PRIMARY target's rows when that target exists (the first target
/// otherwise). Every target stored means `complete`; any per-target failure
/// retains the durable generation as survivor-first retry authority.
final class PreparedDirectMediaBlobFanoutUploadResult {
  const PreparedDirectMediaBlobFanoutUploadResult._({
    required this.state,
    required this.hasDurableAuthority,
    this.targetRows = const <String, List<DirectMediaBlobCustodyRow>>{},
    this.attachments = const <MediaAttachment>[],
  });

  const PreparedDirectMediaBlobFanoutUploadResult.complete({
    required Map<String, List<DirectMediaBlobCustodyRow>> targetRows,
    required List<MediaAttachment> attachments,
  }) : this._(
         state: PreparedDirectMediaBlobUploadState.complete,
         hasDurableAuthority: true,
         targetRows: targetRows,
         attachments: attachments,
       );

  const PreparedDirectMediaBlobFanoutUploadResult.retained({
    this.hasDurableAuthority = true,
  }) : state = PreparedDirectMediaBlobUploadState.retained,
       targetRows = const <String, List<DirectMediaBlobCustodyRow>>{},
       attachments = const <MediaAttachment>[];

  const PreparedDirectMediaBlobFanoutUploadResult.refused({
    this.hasDurableAuthority = false,
  }) : state = PreparedDirectMediaBlobUploadState.refused,
       targetRows = const <String, List<DirectMediaBlobCustodyRow>>{},
       attachments = const <MediaAttachment>[];

  final PreparedDirectMediaBlobUploadState state;
  final bool hasDurableAuthority;
  final Map<String, List<DirectMediaBlobCustodyRow>> targetRows;
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

  /// Plan 348/350 absent-parent entry used by an eligible external OS share or
  /// by one already-authorized internal media forward.
  ///
  /// [onAuthorityReady] copies/verifies the sender-local plaintext preview after
  /// v110/v111 commit and before LAN or relay. Its failure retains ciphertext
  /// authority for the existing restart retry owner.
  ///
  /// [authorizedForwardDedupKey] is null for the marker-free external shape. A
  /// nonblank value is one ephemeral authorization read at a reviewed forward
  /// entry: [parent] must then be forwarded with exactly that dedup key. This
  /// owner never derives the token from [parent], [sources], or provenance.
  Future<PreparedDirectMediaBlobUploadResult> prepareAndUploadFreshMessage({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage parent,
    required List<PreparedDirectMediaBlobSource> sources,
    required DirectMediaBlobAuthorityReadyFn onAuthorityReady,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
    String? authorizedForwardDedupKey,
  }) async {
    final freshRepository = switch (_repository) {
      FreshOutgoingDirectMediaBlobGenerationRepository repository
          when repository.supportsFreshOutgoingDirectMediaBlobGeneration =>
        repository,
      _ => null,
    };
    final bool canonicalIdentity;
    if (authorizedForwardDedupKey == null) {
      canonicalIdentity = parent.id == parent.dedupKey && !parent.isForwarded;
    } else {
      final token = authorizedForwardDedupKey.trim();
      canonicalIdentity =
          token.isNotEmpty &&
          token == authorizedForwardDedupKey &&
          parent.isForwarded &&
          parent.dedupKey == authorizedForwardDedupKey;
    }
    if (!_repository.supportsDirectMediaBlobCustody ||
        freshRepository == null ||
        !_validFreshRequest(
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          parent: parent,
          sources: sources,
        ) ||
        !canonicalIdentity ||
        parent.timestamp != parent.createdAt) {
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
          authorizedForwardDedupKey: authorizedForwardDedupKey,
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

  /// Plan 354 private entry for one newly authored protected/View-Once initial.
  ///
  /// The exact durable private parent plus its single convention-owned pending
  /// attachment is the whole preparation authority: no v110 intent exists and
  /// none is minted. The complete v111 generation is published before the LAN
  /// callback and before the same strict relay owner every ordinary generation
  /// already uses.
  Future<PreparedDirectMediaBlobUploadResult> prepareAndUploadPrivate({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage expectedParent,
    required PreparedDirectMediaBlobSource source,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    final privateRepository = switch (_repository) {
      OutgoingDirectPrivateMediaBlobGenerationRepository repository
          when repository.supportsOutgoingDirectPrivateMediaBlobGeneration =>
        repository,
      _ => null,
    };
    if (!_repository.supportsDirectMediaBlobCustody ||
        privateRepository == null ||
        identityPeerId.isEmpty ||
        identityPeerId != identityPeerId.trim() ||
        recipientPeerId.isEmpty ||
        recipientPeerId != recipientPeerId.trim() ||
        expectedParent.id.isEmpty ||
        expectedParent.isIncoming ||
        expectedParent.isDeleted ||
        expectedParent.isHidden ||
        expectedParent.senderPeerId != identityPeerId ||
        expectedParent.contactPeerId != recipientPeerId ||
        expectedParent.directMediaCustodyIntentId != null ||
        !privateMediaInitialProducerMatrixAllows(
          policyVersion: expectedParent.privateMediaPolicy.version,
          mode: expectedParent.privateMediaMode,
          mime: source.attachment.mime,
          mediaType: source.attachment.mediaType,
        ) ||
        source.attachment.messageId != expectedParent.id ||
        source.attachment.ownerLane != MediaOwnerLane.direct ||
        source.attachment.downloadStatus != 'upload_pending' ||
        source.attachment.contentHash != null ||
        source.attachment.encryptionKeyBase64 != null ||
        source.attachment.encryptionNonce != null ||
        source.attachment.encryptionScheme != null ||
        source.plaintextPath.isEmpty) {
      return const PreparedDirectMediaBlobUploadResult.refused();
    }

    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final publication = await _publishPrivateGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          expectedParent: expectedParent,
          source: source,
          repository: privateRepository,
        );
        final generation = publication.generation;
        if (generation == null) {
          return publication.hasDurableAuthority
              ? const PreparedDirectMediaBlobUploadResult.retained()
              : const PreparedDirectMediaBlobUploadResult.refused();
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

  /// Plan 366 initialized-roster private entry.
  ///
  /// The supported Protected/View-Once attachment is encrypted and persisted
  /// once, while the private fanout generation publishes one v114 addressing
  /// row per exact snapshot target under the incumbent private lifecycle
  /// lease. No v110 intent is minted.
  Future<PreparedDirectMediaBlobFanoutUploadResult>
  prepareAndUploadPrivateFanout({
    required Bridge bridge,
    required String identityPeerId,
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot snapshot,
    required ConversationMessage expectedParent,
    required PreparedDirectMediaBlobSource source,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    final privateFanoutRepository = _privateFanoutRepository;
    final targetPeerIds = snapshot.targets
        .map((target) => target.peerId)
        .toSet();
    if (!_repository.supportsDirectMediaBlobCustody ||
        privateFanoutRepository == null ||
        identityPeerId.isEmpty ||
        identityPeerId.trim() != identityPeerId ||
        contactAccountPeerId.isEmpty ||
        contactAccountPeerId.trim() != contactAccountPeerId ||
        snapshot.contactAccountPeerId != contactAccountPeerId ||
        snapshot.targets.isEmpty ||
        targetPeerIds.length != snapshot.targets.length ||
        expectedParent.id.isEmpty ||
        expectedParent.isIncoming ||
        expectedParent.isDeleted ||
        expectedParent.isHidden ||
        expectedParent.senderPeerId != identityPeerId ||
        expectedParent.contactPeerId != contactAccountPeerId ||
        expectedParent.directMediaCustodyIntentId != null ||
        expectedParent.directEventFanoutGenerationId != null ||
        !privateMediaInitialProducerMatrixAllows(
          policyVersion: expectedParent.privateMediaPolicy.version,
          mode: expectedParent.privateMediaMode,
          mime: source.attachment.mime,
          mediaType: source.attachment.mediaType,
        ) ||
        source.attachment.messageId != expectedParent.id ||
        source.attachment.ownerLane != MediaOwnerLane.direct ||
        source.attachment.downloadStatus != 'upload_pending' ||
        source.attachment.contentHash != null ||
        source.attachment.encryptionKeyBase64 != null ||
        source.attachment.encryptionNonce != null ||
        source.attachment.encryptionScheme != null ||
        source.plaintextPath.isEmpty) {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused();
    }

    var hasDurableAuthority = false;
    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final publication = await _publishPrivateFanoutGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          contactAccountPeerId: contactAccountPeerId,
          snapshot: snapshot,
          expectedParent: expectedParent,
          source: source,
          repository: privateFanoutRepository,
        );
        hasDurableAuthority = publication.hasDurableAuthority;
        final generation = publication.generation;
        if (generation == null) {
          return hasDurableAuthority
              ? const PreparedDirectMediaBlobFanoutUploadResult.retained()
              : const PreparedDirectMediaBlobFanoutUploadResult.refused();
        }
        return _uploadPublishedFanoutGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          generation: generation,
          lanAccelerationRecipientPeerId:
              snapshot.targets.first.isLegacyAccountTarget
              ? snapshot.targets.first.peerId
              : null,
          commitmentRecipientPeerId: _commitmentRecipientForSnapshot(snapshot),
          onGenerationReady: onGenerationReady,
        );
      });
    } on Object {
      return hasDurableAuthority
          ? const PreparedDirectMediaBlobFanoutUploadResult.retained()
          : const PreparedDirectMediaBlobFanoutUploadResult.refused();
    }
  }

  /// Roster-free reopen of the exact persisted private v114 target set.
  ///
  /// This path never creates a generation and never resolves live contact
  /// authority. Complete persisted rows (including a partial stored/pending
  /// upload matrix) are the retry obligation under the same lifecycle lease.
  Future<PreparedDirectMediaBlobFanoutUploadResult>
  reopenAndUploadPrivateFanout({
    required Bridge bridge,
    required String identityPeerId,
    required String contactAccountPeerId,
    required ConversationMessage expectedParent,
    required MediaAttachment expectedAttachment,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    if (!_repository.supportsDirectMediaBlobCustody ||
        _privateFanoutRepository == null ||
        identityPeerId.isEmpty ||
        identityPeerId.trim() != identityPeerId ||
        contactAccountPeerId.isEmpty ||
        contactAccountPeerId.trim() != contactAccountPeerId ||
        expectedParent.id.isEmpty ||
        expectedParent.isIncoming ||
        expectedParent.isDeleted ||
        expectedParent.isHidden ||
        expectedParent.contactPeerId != contactAccountPeerId ||
        expectedParent.directMediaCustodyIntentId != null ||
        expectedParent.directEventFanoutGenerationId != expectedParent.id ||
        !privateMediaInitialProducerMatrixAllows(
          policyVersion: expectedParent.privateMediaPolicy.version,
          mode: expectedParent.privateMediaMode,
          mime: expectedAttachment.mime,
          mediaType: expectedAttachment.mediaType,
        ) ||
        expectedAttachment.messageId != expectedParent.id ||
        expectedAttachment.ownerLane != MediaOwnerLane.direct ||
        expectedAttachment.contentHash == null ||
        expectedAttachment.encryptionKeyBase64 == null ||
        expectedAttachment.encryptionNonce == null ||
        expectedAttachment.encryptionScheme == null) {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused();
    }
    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final rows = await _repository.loadDirectMediaBlobCustodyForMessage(
          expectedParent.id,
        );
        if (rows.isEmpty) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused();
        }
        final recipientPeerIds = rows
            .map((row) => row.recipientPeerId)
            .whereType<String>()
            .toSet();
        if (recipientPeerIds.isEmpty ||
            rows.length != recipientPeerIds.length ||
            rows.any(
              (row) =>
                  row.attachmentId != expectedAttachment.id ||
                  row.messageId != expectedParent.id ||
                  row.direction != DirectMediaBlobCustodyDirection.outgoing ||
                  !row.isLinkedFanoutRow ||
                  row.contactAccountPeerId != contactAccountPeerId ||
                  row.recipientMlKemPublicKey == null,
            )) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        final orderedRecipients = recipientPeerIds.toList()..sort();
        if (orderedRecipients.remove(contactAccountPeerId)) {
          orderedRecipients.insert(0, contactAccountPeerId);
        }
        final keyByRecipient = <String, String>{
          for (final row in rows)
            if (row.recipientPeerId != null &&
                row.recipientMlKemPublicKey != null)
              row.recipientPeerId!: row.recipientMlKemPublicKey!,
        };
        if (keyByRecipient.length != orderedRecipients.length) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        final generation = await _reopenCompleteFanoutGeneration(
          identityPeerId: identityPeerId,
          contactAccountPeerId: contactAccountPeerId,
          orderedTargets: orderedRecipients
              .map(
                (peerId) => (
                  peerId: peerId,
                  requiredMlKemPublicKey: keyByRecipient[peerId],
                ),
              )
              .toList(growable: false),
          messageId: expectedParent.id,
          attachments: <MediaAttachment>[expectedAttachment],
          rows: rows,
        );
        if (generation == null) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        return _uploadPublishedFanoutGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          generation: generation,
          lanAccelerationRecipientPeerId: null,
          commitmentRecipientPeerId: orderedRecipients.first,
          onGenerationReady: onGenerationReady,
        );
      });
    } on Object {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused(
        hasDurableAuthority: true,
      );
    }
  }

  /// Plan 354 private failed/incomplete retry entry.
  ///
  /// This never mints a generation and never re-encrypts: it revalidates the
  /// exact durable parent, attachment and v111 projection through the same
  /// private staging CAS (which can only return `idempotent` while a generation
  /// is loaded under this lease), then reopens the byte-identical ciphertext
  /// and reuses the sole strict upload owner.
  Future<PreparedDirectMediaBlobUploadResult> reopenAndUploadPrivate({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage expectedParent,
    required MediaAttachment expectedAttachment,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    final privateRepository = switch (_repository) {
      OutgoingDirectPrivateMediaBlobGenerationRepository repository
          when repository.supportsOutgoingDirectPrivateMediaBlobGeneration =>
        repository,
      _ => null,
    };
    if (!_repository.supportsDirectMediaBlobCustody ||
        privateRepository == null ||
        identityPeerId.isEmpty ||
        identityPeerId != identityPeerId.trim() ||
        recipientPeerId.isEmpty ||
        recipientPeerId != recipientPeerId.trim() ||
        expectedParent.id.isEmpty ||
        expectedParent.isIncoming ||
        expectedParent.isDeleted ||
        expectedParent.isHidden ||
        expectedParent.contactPeerId != recipientPeerId ||
        expectedParent.directMediaCustodyIntentId != null ||
        expectedAttachment.messageId != expectedParent.id ||
        expectedAttachment.ownerLane != MediaOwnerLane.direct ||
        expectedAttachment.downloadStatus != 'upload_pending' ||
        expectedAttachment.contentHash == null ||
        expectedAttachment.encryptionKeyBase64 == null ||
        expectedAttachment.encryptionNonce == null ||
        expectedAttachment.encryptionScheme == null) {
      return const PreparedDirectMediaBlobUploadResult.refused();
    }
    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final rows = await _repository.loadDirectMediaBlobCustodyForMessage(
          expectedParent.id,
        );
        if (rows.length != 1 ||
            rows.single.attachmentId != expectedAttachment.id) {
          return const PreparedDirectMediaBlobUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        final revalidated = await privateRepository
            .stageOutgoingDirectPrivateMediaBlobGeneration(
              expectedParent: expectedParent,
              expectedAttachment: expectedAttachment.copyWith(
                clearContentHash: true,
                clearThumbnailHash: true,
                clearEncryptionKeyBase64: true,
                clearEncryptionNonce: true,
                clearEncryptionScheme: true,
                clearBlobCustody: true,
                clearDirectMediaBlobCustodyFingerprint: true,
              ),
              preparedAttachment: expectedAttachment,
              custodyRow: rows.single.copyWith(
                state: DirectMediaBlobCustodyState.outgoingPrepared,
                inboxCustodyIncarnationId: null,
                expiresAtMs: null,
                custodyRelayPeerId: null,
              ),
            );
        if (revalidated.outcome !=
            DirectMediaBlobGenerationStageOutcome.idempotent) {
          return const PreparedDirectMediaBlobUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        final generation = await _reopenCompleteGeneration(
          identityPeerId: identityPeerId,
          recipientPeerId: recipientPeerId,
          messageId: expectedParent.id,
          attachments: revalidated.attachments,
          rows: revalidated.custodyRows,
        );
        if (generation == null) {
          return const PreparedDirectMediaBlobUploadResult.refused(
            hasDurableAuthority: true,
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
      return const PreparedDirectMediaBlobUploadResult.refused(
        hasDurableAuthority: true,
      );
    }
  }

  Future<_GenerationPublication> _publishPrivateGeneration({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage expectedParent,
    required PreparedDirectMediaBlobSource source,
    required OutgoingDirectPrivateMediaBlobGenerationRepository repository,
  }) async {
    _CandidateGenerationEntry? candidate;
    var stageAttempted = false;
    var hasDurableAuthority = false;
    try {
      final encrypted =
          source.preparedArtifact ??
          await _prepareArtifact(
            bridge: bridge,
            localFilePath: source.plaintextPath,
          );
      final persisted = await _artifactStore.persistCandidate(
        identityPeerId: identityPeerId,
        attachmentId: source.attachment.id,
        encryptedSourcePath: encrypted.encryptedPath,
        expectedContentHash: encrypted.contentHash,
      );
      candidate = _CandidateGenerationEntry(
        source: source,
        encrypted: encrypted,
        artifact: persisted,
      );

      final now = _clock().toUtc().toIso8601String();
      final prepared = source.attachment.copyWith(
        contentHash: persisted.contentHash,
        encryptionKeyBase64: encrypted.keyBase64,
        encryptionNonce: encrypted.nonce,
        encryptionScheme: encrypted.scheme,
        downloadStatus: 'upload_pending',
        ownerLane: MediaOwnerLane.direct,
      );
      final custodyRow = DirectMediaBlobCustodyRow(
        attachmentId: source.attachment.id,
        messageId: expectedParent.id,
        direction: DirectMediaBlobCustodyDirection.outgoing,
        state: DirectMediaBlobCustodyState.outgoingPrepared,
        inboxCustodyIncarnationId: null,
        recipientPeerId: recipientPeerId,
        ciphertextRelativePath: persisted.relativePath,
        contentHash: persisted.contentHash,
        ciphertextSize: persisted.ciphertextSize,
        expiresAtMs: null,
        custodyRelayPeerId: null,
        lastAttemptAt: null,
        nextAttemptAt: null,
        createdAt: now,
        updatedAt: now,
      );
      stageAttempted = true;
      final staged = await repository
          .stageOutgoingDirectPrivateMediaBlobGeneration(
            expectedParent: expectedParent,
            expectedAttachment: source.attachment,
            preparedAttachment: prepared,
            custodyRow: custodyRow,
          );
      hasDurableAuthority = staged.authorizesStrictUpload;
      final idempotent =
          staged.outcome == DirectMediaBlobGenerationStageOutcome.idempotent;
      if (!staged.authorizesStrictUpload) {
        await _deleteOnlyProvablyUnreferencedCandidates(
          identityPeerId: identityPeerId,
          messageId: expectedParent.id,
          candidates: <_CandidateGenerationEntry>[candidate],
        );
        await _deleteEncryptedTemps(<_CandidateGenerationEntry>[candidate]);
        return _GenerationPublication(
          generation: null,
          hasDurableAuthority: hasDurableAuthority,
        );
      }
      if (idempotent) {
        await _deleteCandidates(identityPeerId, <_CandidateGenerationEntry>[
          candidate,
        ]);
      }
      await _deleteEncryptedTemps(<_CandidateGenerationEntry>[candidate]);
      final generation = await _reopenCompleteGeneration(
        identityPeerId: identityPeerId,
        recipientPeerId: recipientPeerId,
        messageId: expectedParent.id,
        attachments: staged.attachments,
        rows: staged.custodyRows,
      );
      return _GenerationPublication(
        generation: generation,
        hasDurableAuthority: true,
      );
    } on Object {
      final candidates = <_CandidateGenerationEntry>[?candidate];
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

  Future<_FanoutGenerationPublication> _publishPrivateFanoutGeneration({
    required Bridge bridge,
    required String identityPeerId,
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot snapshot,
    required ConversationMessage expectedParent,
    required PreparedDirectMediaBlobSource source,
    required OutgoingDirectPrivateMediaBlobFanoutGenerationRepository
    repository,
  }) async {
    _CandidateGenerationEntry? candidate;
    var stageAttempted = false;
    var hasDurableAuthority = false;
    try {
      // Private fanout still owns one canonical ciphertext. Only its durable
      // recipient/key addressing rows are plural.
      final encrypted =
          source.preparedArtifact ??
          await _prepareArtifact(
            bridge: bridge,
            localFilePath: source.plaintextPath,
          );
      final persisted = await _artifactStore.persistCandidate(
        identityPeerId: identityPeerId,
        attachmentId: source.attachment.id,
        encryptedSourcePath: encrypted.encryptedPath,
        expectedContentHash: encrypted.contentHash,
      );
      candidate = _CandidateGenerationEntry(
        source: source,
        encrypted: encrypted,
        artifact: persisted,
      );

      final now = _clock().toUtc().toIso8601String();
      final prepared = source.attachment.copyWith(
        contentHash: persisted.contentHash,
        encryptionKeyBase64: encrypted.keyBase64,
        encryptionNonce: encrypted.nonce,
        encryptionScheme: encrypted.scheme,
        downloadStatus: 'upload_pending',
        ownerLane: MediaOwnerLane.direct,
      );
      final custodyRows = snapshot.targets
          .map(
            (target) => DirectMediaBlobCustodyRow(
              attachmentId: source.attachment.id,
              messageId: expectedParent.id,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: target.peerId,
              contactAccountPeerId: contactAccountPeerId,
              recipientMlKemPublicKey: target.mlKemPublicKey,
              ciphertextRelativePath: persisted.relativePath,
              contentHash: persisted.contentHash,
              ciphertextSize: persisted.ciphertextSize,
              expiresAtMs: null,
              custodyRelayPeerId: null,
              lastAttemptAt: null,
              nextAttemptAt: null,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList(growable: false);
      stageAttempted = true;
      final staged = await repository
          .stageOutgoingDirectPrivateMediaBlobFanoutGeneration(
            expectedParent: expectedParent,
            expectedAttachment: source.attachment,
            preparedAttachment: prepared,
            custodyRows: custodyRows,
            contactAccountPeerId: contactAccountPeerId,
            expectedSnapshot: snapshot,
          );
      hasDurableAuthority = staged.authorizesStrictUpload;
      final idempotent =
          staged.outcome == DirectMediaBlobGenerationStageOutcome.idempotent;
      if (!staged.authorizesStrictUpload) {
        await _deleteOnlyProvablyUnreferencedCandidates(
          identityPeerId: identityPeerId,
          messageId: expectedParent.id,
          candidates: <_CandidateGenerationEntry>[candidate],
        );
        await _deleteEncryptedTemps(<_CandidateGenerationEntry>[candidate]);
        return _FanoutGenerationPublication(
          generation: null,
          hasDurableAuthority: hasDurableAuthority,
        );
      }
      if (idempotent) {
        await _deleteCandidates(identityPeerId, <_CandidateGenerationEntry>[
          candidate,
        ]);
      }
      await _deleteEncryptedTemps(<_CandidateGenerationEntry>[candidate]);
      final generation = await _reopenCompleteFanoutGeneration(
        identityPeerId: identityPeerId,
        contactAccountPeerId: contactAccountPeerId,
        orderedTargets: snapshot.targets
            .map(
              (target) => (
                peerId: target.peerId,
                requiredMlKemPublicKey: target.mlKemPublicKey,
              ),
            )
            .toList(growable: false),
        messageId: expectedParent.id,
        attachments: staged.attachments,
        rows: staged.custodyRows,
      );
      return _FanoutGenerationPublication(
        generation: generation,
        hasDurableAuthority: true,
      );
    } on Object {
      final candidates = <_CandidateGenerationEntry>[?candidate];
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
        return const _FanoutGenerationPublication(
          generation: null,
          hasDurableAuthority: true,
        );
      }
      rethrow;
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

  /// Plan 362 fresh all-target entry: encrypts/persists each artifact ONCE,
  /// publishes the complete `targets x attachments` linked generation plus
  /// the durable no-remint marker atomically, then uploads the exact shared
  /// bytes to every snapshot target in order.
  ///
  /// The LAN acceleration callback fires once with the legacy-primary
  /// target's artifacts ONLY when the snapshot's first target is the dynamic
  /// account target; linked-device targets never ride LAN acceleration.
  Future<PreparedDirectMediaBlobFanoutUploadResult>
  prepareAndUploadFreshFanout({
    required Bridge bridge,
    required String identityPeerId,
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot snapshot,
    required ConversationMessage expectedParent,
    required List<PreparedDirectMediaBlobSource> sources,
    bool allowFreshParent = false,
    String? authorizedForwardDedupKey,
    DirectMediaBlobAuthorityReadyFn? onAuthorityReady,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    final fanoutRepository = _fanoutRepository;
    final targetPeerIds = snapshot.targets
        .map((target) => target.peerId)
        .toSet();
    final freshParentIdentityIsCanonical = !allowFreshParent
        ? authorizedForwardDedupKey == null
        : authorizedForwardDedupKey == null
        ? expectedParent.id == expectedParent.dedupKey &&
              !expectedParent.isForwarded
        : authorizedForwardDedupKey.trim().isNotEmpty &&
              authorizedForwardDedupKey.trim() == authorizedForwardDedupKey &&
              expectedParent.isForwarded &&
              expectedParent.dedupKey == authorizedForwardDedupKey;
    if (!_repository.supportsDirectMediaBlobCustody ||
        fanoutRepository == null ||
        !freshParentIdentityIsCanonical ||
        snapshot.targets.isEmpty ||
        targetPeerIds.length != snapshot.targets.length ||
        snapshot.contactAccountPeerId != contactAccountPeerId ||
        expectedParent.contactPeerId != contactAccountPeerId ||
        !_validFreshRequest(
          identityPeerId: identityPeerId,
          recipientPeerId: contactAccountPeerId,
          parent: expectedParent,
          sources: sources,
        )) {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused();
    }

    var hasDurableAuthority = false;
    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final publication = await _publishFreshFanoutGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          contactAccountPeerId: contactAccountPeerId,
          snapshot: snapshot,
          expectedParent: expectedParent,
          sources: sources,
          fanoutRepository: fanoutRepository,
          allowFreshParent: allowFreshParent,
          authorizedForwardDedupKey: authorizedForwardDedupKey,
        );
        hasDurableAuthority = publication.hasDurableAuthority;
        final generation = publication.generation;
        if (generation == null) {
          // Refused with durable rows is retained survivor authority; refused
          // without authority stays a clean refusal.
          return hasDurableAuthority
              ? const PreparedDirectMediaBlobFanoutUploadResult.retained()
              : const PreparedDirectMediaBlobFanoutUploadResult.refused();
        }
        if (onAuthorityReady != null) {
          bool previewReady;
          try {
            previewReady = await onAuthorityReady(
              List<MediaAttachment>.unmodifiable(
                generation.artifactsByRecipient.values.first
                    .map((artifact) => artifact.attachment)
                    .toList(growable: false),
              ),
            );
          } on Object {
            previewReady = false;
          }
          if (!previewReady) {
            return const PreparedDirectMediaBlobFanoutUploadResult.retained();
          }
        }
        return _uploadPublishedFanoutGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          generation: generation,
          lanAccelerationRecipientPeerId:
              snapshot.targets.first.isLegacyAccountTarget
              ? snapshot.targets.first.peerId
              : null,
          commitmentRecipientPeerId: _commitmentRecipientForSnapshot(snapshot),
          onGenerationReady: onGenerationReady,
        );
      });
    } on Object {
      return hasDurableAuthority
          ? const PreparedDirectMediaBlobFanoutUploadResult.retained()
          : const PreparedDirectMediaBlobFanoutUploadResult.refused();
    }
  }

  /// Plan 362 crash/incomplete reopen for a COMPLETE persisted linked
  /// generation. Revalidates through the same atomic stage (idempotent
  /// branch), never re-encrypts or remints, and replays the per-target
  /// upload/transition loop on outstanding prepared rows. A terminal
  /// generation (marker with zero rows) refuses.
  Future<PreparedDirectMediaBlobFanoutUploadResult> reopenAndUploadFanout({
    required Bridge bridge,
    required String identityPeerId,
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot snapshot,
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    final fanoutRepository = _fanoutRepository;
    final targetPeerIds = snapshot.targets
        .map((target) => target.peerId)
        .toSet();
    if (!_repository.supportsDirectMediaBlobCustody ||
        fanoutRepository == null ||
        identityPeerId.trim() != identityPeerId ||
        identityPeerId.isEmpty ||
        contactAccountPeerId.trim() != contactAccountPeerId ||
        contactAccountPeerId.isEmpty ||
        snapshot.targets.isEmpty ||
        targetPeerIds.length != snapshot.targets.length ||
        snapshot.contactAccountPeerId != contactAccountPeerId ||
        expectedParent.id.isEmpty ||
        expectedParent.contactPeerId != contactAccountPeerId ||
        expectedParent.isIncoming ||
        expectedParent.isDeleted ||
        expectedParent.isHidden ||
        expectedParent.directMediaCustodyIntentId == null ||
        expectedAttachments.isEmpty) {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused();
    }
    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final rows = await _repository.loadDirectMediaBlobCustodyForMessage(
          expectedParent.id,
        );
        if (rows.isEmpty) {
          // Terminal (durable marker, zero survivors) or never published:
          // reopen NEVER remints a generation.
          return const PreparedDirectMediaBlobFanoutUploadResult.refused();
        }
        if (rows.length !=
                expectedAttachments.length * snapshot.targets.length ||
            rows.any((row) => !row.isLinkedFanoutRow)) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        // Reuse the existing-generation branch of the atomic fanout stage as
        // the reopen authority check: with a non-empty generation loaded
        // under this lease it cannot mint rows, only prove the current
        // parent/marker/snapshot/complete row set still match.
        final revalidated = await fanoutRepository
            .stageOutgoingDirectLinkedMediaBlobFanoutGeneration(
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
              contactAccountPeerId: contactAccountPeerId,
              expectedSnapshot: snapshot,
            );
        if (revalidated.outcome !=
            DirectMediaBlobGenerationStageOutcome.idempotent) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        final generation = await _reopenCompleteFanoutGeneration(
          identityPeerId: identityPeerId,
          contactAccountPeerId: contactAccountPeerId,
          orderedTargets: snapshot.targets
              .map(
                (target) => (
                  peerId: target.peerId,
                  requiredMlKemPublicKey: target.mlKemPublicKey,
                ),
              )
              .toList(growable: false),
          messageId: expectedParent.id,
          attachments: revalidated.attachments,
          rows: revalidated.custodyRows,
        );
        if (generation == null) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        return _uploadPublishedFanoutGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          generation: generation,
          lanAccelerationRecipientPeerId:
              snapshot.targets.first.isLegacyAccountTarget
              ? snapshot.targets.first.peerId
              : null,
          commitmentRecipientPeerId: _commitmentRecipientForSnapshot(snapshot),
          onGenerationReady: onGenerationReady,
        );
      });
    } on Object {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused(
        hasDurableAuthority: true,
      );
    }
  }

  /// Plan 362 survivor-first retry: replays the per-target upload/transition
  /// loop on the EXACT persisted linked rows — zero roster resolution, zero
  /// re-encryption, no snapshot read. The persisted rows are the complete
  /// retry authority even after the live roster drifts.
  Future<PreparedDirectMediaBlobFanoutUploadResult>
  retryPersistedFanoutGeneration({
    required Bridge bridge,
    required String identityPeerId,
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
  }) async {
    final expectedIds = expectedAttachments
        .map((attachment) => attachment.id)
        .toSet();
    if (!_repository.supportsDirectMediaBlobCustody ||
        identityPeerId.trim() != identityPeerId ||
        identityPeerId.isEmpty ||
        expectedParent.id.isEmpty ||
        expectedParent.contactPeerId.trim().isEmpty ||
        expectedParent.isIncoming ||
        expectedParent.isDeleted ||
        expectedParent.isHidden ||
        expectedParent.directMediaCustodyIntentId == null ||
        expectedAttachments.isEmpty ||
        expectedIds.length != expectedAttachments.length) {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused();
    }
    try {
      return await _repository.runDirectMediaBlobCustodyLifecycle(() async {
        final rows = await _repository.loadDirectMediaBlobCustodyForMessage(
          expectedParent.id,
        );
        if (rows.isEmpty) {
          // Zero rows: the caller distinguishes terminal (durable marker)
          // from never-published; neither may remint here.
          return const PreparedDirectMediaBlobFanoutUploadResult.refused();
        }
        if (rows.any(
          (row) =>
              row.direction != DirectMediaBlobCustodyDirection.outgoing ||
              !row.isLinkedFanoutRow ||
              row.contactAccountPeerId != expectedParent.contactPeerId ||
              !expectedIds.contains(row.attachmentId),
        )) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        final recipientPeerIds = rows
            .map((row) => row.recipientPeerId)
            .whereType<String>()
            .toSet();
        if (recipientPeerIds.isEmpty ||
            rows.length !=
                expectedAttachments.length * recipientPeerIds.length) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        // Deterministic order without a roster read: the dynamic account
        // recipient (when persisted) first, then lexical.
        final orderedRecipients = recipientPeerIds.toList()..sort();
        if (orderedRecipients.remove(expectedParent.contactPeerId)) {
          orderedRecipients.insert(0, expectedParent.contactPeerId);
        }
        final generation = await _reopenCompleteFanoutGeneration(
          identityPeerId: identityPeerId,
          contactAccountPeerId: expectedParent.contactPeerId,
          orderedTargets: orderedRecipients
              .map(
                (recipientPeerId) =>
                    (peerId: recipientPeerId, requiredMlKemPublicKey: null),
              )
              .toList(growable: false),
          messageId: expectedParent.id,
          attachments: expectedAttachments,
          rows: rows,
        );
        if (generation == null) {
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
            hasDurableAuthority: true,
          );
        }
        return _uploadPublishedFanoutGeneration(
          bridge: bridge,
          identityPeerId: identityPeerId,
          generation: generation,
          // Acceleration only ever targets a snapshot-proven legacy-primary;
          // the roster-free retry lane never accelerates.
          lanAccelerationRecipientPeerId: null,
          commitmentRecipientPeerId: orderedRecipients.first,
          onGenerationReady: null,
        );
      });
    } on Object {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused(
        hasDurableAuthority: true,
      );
    }
  }

  OutgoingDirectLinkedMediaBlobFanoutRepository? get _fanoutRepository =>
      switch (_repository) {
        OutgoingDirectLinkedMediaBlobFanoutRepository repository
            when repository.supportsDirectLinkedMediaBlobFanout =>
          repository,
        _ => null,
      };

  OutgoingDirectPrivateMediaBlobFanoutGenerationRepository?
  get _privateFanoutRepository => switch (_repository) {
    OutgoingDirectPrivateMediaBlobFanoutGenerationRepository repository
        when repository
            .supportsOutgoingDirectPrivateMediaBlobFanoutGeneration =>
      repository,
    _ => null,
  };

  static String _commitmentRecipientForSnapshot(
    DirectContactFanoutSnapshot snapshot,
  ) => snapshot.targets
      .firstWhere(
        (target) => target.isLegacyAccountTarget,
        orElse: () => snapshot.targets.first,
      )
      .peerId;

  Future<_FanoutGenerationPublication> _publishFreshFanoutGeneration({
    required Bridge bridge,
    required String identityPeerId,
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot snapshot,
    required ConversationMessage expectedParent,
    required List<PreparedDirectMediaBlobSource> sources,
    required OutgoingDirectLinkedMediaBlobFanoutRepository fanoutRepository,
    required bool allowFreshParent,
    required String? authorizedForwardDedupKey,
  }) async {
    final candidates = <_CandidateGenerationEntry>[];
    var stageAttempted = false;
    var hasDurableAuthority = false;
    try {
      // ENCRYPT/PERSIST EACH ARTIFACT ONCE — every target shares the exact
      // canonical ciphertext; only the addressing rows are per-target.
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
        for (final target in snapshot.targets) {
          custodyRows.add(
            DirectMediaBlobCustodyRow(
              attachmentId: source.attachment.id,
              messageId: expectedParent.id,
              direction: DirectMediaBlobCustodyDirection.outgoing,
              state: DirectMediaBlobCustodyState.outgoingPrepared,
              inboxCustodyIncarnationId: null,
              recipientPeerId: target.peerId,
              contactAccountPeerId: contactAccountPeerId,
              recipientMlKemPublicKey: target.mlKemPublicKey,
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
      }
      stageAttempted = true;
      final staged = await fanoutRepository
          .stageOutgoingDirectLinkedMediaBlobFanoutGeneration(
            expectedParent: expectedParent,
            expectedAttachments: sources
                .map((source) => source.attachment)
                .toList(growable: false),
            preparedAttachments: prepared,
            custodyRows: custodyRows,
            contactAccountPeerId: contactAccountPeerId,
            expectedSnapshot: snapshot,
            allowFreshParent: allowFreshParent,
            authorizedForwardDedupKey: authorizedForwardDedupKey,
          );
      hasDurableAuthority = staged.authorizesStrictUpload;
      final idempotent =
          staged.outcome == DirectMediaBlobGenerationStageOutcome.idempotent;
      if (!staged.authorizesStrictUpload) {
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
        return _FanoutGenerationPublication(
          generation: null,
          hasDurableAuthority: hasDurableAuthority,
        );
      }
      if (idempotent) {
        // Survivor replay (reopen path): the durable winner's artifacts are
        // authoritative; this attempt's fresh candidates are losers.
        await _deleteCandidates(identityPeerId, candidates);
      }
      await _deleteEncryptedTemps(candidates);
      final generation = await _reopenCompleteFanoutGeneration(
        identityPeerId: identityPeerId,
        contactAccountPeerId: contactAccountPeerId,
        orderedTargets: snapshot.targets
            .map(
              (target) => (
                peerId: target.peerId,
                requiredMlKemPublicKey: target.mlKemPublicKey,
              ),
            )
            .toList(growable: false),
        messageId: expectedParent.id,
        attachments: staged.attachments,
        rows: staged.custodyRows,
      );
      return _FanoutGenerationPublication(
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
        return const _FanoutGenerationPublication(
          generation: null,
          hasDurableAuthority: true,
        );
      }
      rethrow;
    }
  }

  /// Fanout sibling of [_reopenCompleteGeneration]: validates the complete
  /// `targets x attachments` linked row set and verifies the ONE shared
  /// artifact behind every exact target row.
  Future<_PublishedFanoutGeneration?> _reopenCompleteFanoutGeneration({
    required String identityPeerId,
    required String contactAccountPeerId,
    required List<({String peerId, String? requiredMlKemPublicKey})>
    orderedTargets,
    required String messageId,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> rows,
  }) async {
    final attachmentById = <String, MediaAttachment>{
      for (final attachment in attachments) attachment.id: attachment,
    };
    if (attachmentById.isEmpty ||
        attachmentById.length != attachments.length ||
        orderedTargets.isEmpty ||
        orderedTargets.map((target) => target.peerId).toSet().length !=
            orderedTargets.length ||
        rows.length != attachments.length * orderedTargets.length) {
      return null;
    }
    final rowsByRecipient = <String, Map<String, DirectMediaBlobCustodyRow>>{};
    for (final row in rows) {
      final recipientPeerId = row.recipientPeerId;
      if (recipientPeerId == null) return null;
      final byAttachment = rowsByRecipient.putIfAbsent(
        recipientPeerId,
        () => <String, DirectMediaBlobCustodyRow>{},
      );
      if (byAttachment.containsKey(row.attachmentId)) return null;
      byAttachment[row.attachmentId] = row;
    }
    if (rowsByRecipient.length != orderedTargets.length) return null;

    final orderedIds = attachmentById.keys.toList()..sort();
    final artifactsByRecipient =
        <String, List<PreparedDirectMediaBlobArtifact>>{};
    for (final target in orderedTargets) {
      final byAttachment = rowsByRecipient[target.peerId];
      if (byAttachment == null || byAttachment.length != orderedIds.length) {
        return null;
      }
      final artifacts = <PreparedDirectMediaBlobArtifact>[];
      for (final attachmentId in orderedIds) {
        final attachment = attachmentById[attachmentId]!;
        final row = byAttachment[attachmentId];
        if (row == null) return null;
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
            row.contactAccountPeerId != contactAccountPeerId ||
            row.recipientMlKemPublicKey == null ||
            (target.requiredMlKemPublicKey != null &&
                row.recipientMlKemPublicKey != target.requiredMlKemPublicKey) ||
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
      artifactsByRecipient[target.peerId] = artifacts;
    }
    return _PublishedFanoutGeneration(
      orderedRecipientPeerIds: orderedTargets
          .map((target) => target.peerId)
          .toList(growable: false),
      artifactsByRecipient: artifactsByRecipient,
    );
  }

  Future<PreparedDirectMediaBlobFanoutUploadResult>
  _uploadPublishedFanoutGeneration({
    required Bridge bridge,
    required String identityPeerId,
    required _PublishedFanoutGeneration generation,
    required String? lanAccelerationRecipientPeerId,
    required String commitmentRecipientPeerId,
    required DirectMediaBlobGenerationReadyFn? onGenerationReady,
  }) async {
    // The caller holds the repository-wide lifecycle lease for this entire
    // method. Revalidate every exact (target, attachment) row before any
    // network side effect, exactly like the single-target owner.
    final liveByRecipient = <String, List<PreparedDirectMediaBlobArtifact>>{};
    final preflightNowMs = _clock().toUtc().millisecondsSinceEpoch;
    for (final recipientPeerId in generation.orderedRecipientPeerIds) {
      final liveArtifacts = <PreparedDirectMediaBlobArtifact>[];
      for (final entry in generation.artifactsByRecipient[recipientPeerId]!) {
        final current = await _repository
            .loadOutgoingDirectMediaBlobCustodyForTarget(
              attachmentId: entry.custody.attachmentId,
              recipientPeerId: recipientPeerId,
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
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
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
          return const PreparedDirectMediaBlobFanoutUploadResult.refused(
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
      liveByRecipient[recipientPeerId] = liveArtifacts;
    }

    final generationReadyNowMs = _clock().toUtc().millisecondsSinceEpoch;
    if (liveByRecipient.values.any(
      (artifacts) => artifacts.any(
        (entry) =>
            entry.custody.state == DirectMediaBlobCustodyState.outgoingStored &&
            (entry.custody.expiresAtMs == null ||
                entry.custody.expiresAtMs! <= generationReadyNowMs),
      ),
    )) {
      return const PreparedDirectMediaBlobFanoutUploadResult.refused(
        hasDurableAuthority: true,
      );
    }

    // Acceleration only, once, and only for the legacy-primary account
    // target; its failure never invalidates the published generation.
    final lanArtifacts = lanAccelerationRecipientPeerId == null
        ? null
        : liveByRecipient[lanAccelerationRecipientPeerId];
    if (onGenerationReady != null && lanArtifacts != null) {
      try {
        await onGenerationReady(
          List<PreparedDirectMediaBlobArtifact>.unmodifiable(lanArtifacts),
        );
      } on Object {
        // LAN is an acceleration only. The already-published strict relay
        // generation remains the durable path.
      }
    }

    final storedByRecipient = <String, List<DirectMediaBlobCustodyRow>>{};
    for (final recipientPeerId in generation.orderedRecipientPeerIds) {
      final storedRows = <DirectMediaBlobCustodyRow>[];
      for (final entry in liveByRecipient[recipientPeerId]!) {
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
            return const PreparedDirectMediaBlobFanoutUploadResult.retained();
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
            return const PreparedDirectMediaBlobFanoutUploadResult.retained();
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
                .loadOutgoingDirectMediaBlobCustodyForTarget(
                  attachmentId: row.attachmentId,
                  recipientPeerId: recipientPeerId,
                );
            if (winner == null ||
                winner.state != DirectMediaBlobCustodyState.outgoingStored ||
                winner.contentHash != row.contentHash ||
                winner.ciphertextSize != row.ciphertextSize ||
                winner.expiresAtMs != receipt.commitment.expiresAtMs ||
                winner.custodyRelayPeerId != receipt.custodyRelayPeerId) {
              return const PreparedDirectMediaBlobFanoutUploadResult.retained();
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
          return const PreparedDirectMediaBlobFanoutUploadResult.retained();
        }
        storedRows.add(row);
      }
      storedByRecipient[recipientPeerId] =
          List<DirectMediaBlobCustodyRow>.unmodifiable(storedRows);
    }

    // The completed projection carries the commitment of the legacy-primary
    // recipient's rows (the first recipient when no legacy target exists).
    final commitmentRows = <String, DirectMediaBlobCustodyRow>{
      for (final row in storedByRecipient[commitmentRecipientPeerId]!)
        row.attachmentId: row,
    };
    final completed = <MediaAttachment>[];
    for (final entry
        in generation.artifactsByRecipient[commitmentRecipientPeerId]!) {
      final row = commitmentRows[entry.custody.attachmentId]!;
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
    return PreparedDirectMediaBlobFanoutUploadResult.complete(
      targetRows: Map<String, List<DirectMediaBlobCustodyRow>>.unmodifiable(
        storedByRecipient,
      ),
      attachments: List<MediaAttachment>.unmodifiable(completed),
    );
  }

  Future<_GenerationPublication> _publishFreshGeneration({
    required Bridge bridge,
    required String identityPeerId,
    required String recipientPeerId,
    required ConversationMessage expectedParent,
    required List<PreparedDirectMediaBlobSource> sources,
    FreshOutgoingDirectMediaBlobGenerationRepository? freshRepository,
    String? authorizedForwardDedupKey,
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
              authorizedForwardDedupKey: authorizedForwardDedupKey,
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
      final current = await _repository
          .loadOutgoingDirectMediaBlobCustodyForTarget(
            attachmentId: entry.custody.attachmentId,
            recipientPeerId: recipientPeerId,
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
              .loadOutgoingDirectMediaBlobCustodyForTarget(
                attachmentId: row.attachmentId,
                recipientPeerId: recipientPeerId,
              );
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

final class _PublishedFanoutGeneration {
  const _PublishedFanoutGeneration({
    required this.orderedRecipientPeerIds,
    required this.artifactsByRecipient,
  });

  final List<String> orderedRecipientPeerIds;
  final Map<String, List<PreparedDirectMediaBlobArtifact>> artifactsByRecipient;
}

final class _FanoutGenerationPublication {
  const _FanoutGenerationPublication({
    required this.generation,
    required this.hasDurableAuthority,
  });

  final _PublishedFanoutGeneration? generation;
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
