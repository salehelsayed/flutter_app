import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart'
    show isExactV2DirectChatInitialEnvelope;
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_direct_media_custody_stage_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

import 'in_memory_message_repository.dart';

/// In-memory [MediaAttachmentRepository] for integration tests.
///
/// 228: owner-enforcing — every stored attachment is stamped with the lane it
/// was saved under, reads filter by lane, and a same-ID save under another
/// lane (or parent) throws [MediaAttachmentOwnerViolation] exactly like the
/// production repository, so a wrong enum at a caller fails the test instead
/// of being hidden by an untyped fake.
class InMemoryMediaAttachmentRepository
    implements
        MediaAttachmentRepository,
        MediaAttachmentByIdLookup,
        OrdinaryGroupAutomaticMediaDownloadStateRepository,
        OrdinaryGroupMediaDownloadFailureRepository,
        OutgoingOrdinaryAttemptStagingRepository,
        OutgoingDirectMediaInboxCustodyStagingRepository,
        NewMessageMediaPersistenceRollback {
  final Map<String, MediaAttachment> _attachments = {};
  void Function(MediaAttachment attachment)? onSaveAttachment;
  Future<OutgoingDirectMediaCustodyStageResult> Function({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String wireEnvelope,
  })?
  onStageOutgoingDirectMediaInboxCustody;

  @override
  bool get supportsDirectMediaInboxCustody =>
      onStageOutgoingDirectMediaInboxCustody != null;

  /// Installs the strict combined parent/media/v108 authority used by
  /// production-shaped direct-media tests.
  ///
  /// This remains opt-in so tests that intentionally prove missing-capability
  /// behavior continue to fail closed. The callback accepts only a fresh
  /// marker-free attempt or an exact manifest-bound prepared predecessor,
  /// delegates parent/media CAS to the existing in-memory staging seams, and
  /// publishes one immutable v108 custody row.
  void enableDirectMediaInboxCustodyForTest(
    InMemoryMessageRepository messages,
  ) {
    onStageOutgoingDirectMediaInboxCustody =
        ({
          required expected,
          required staged,
          required attachments,
          required kind,
          required recipientPeerId,
          required wireEnvelope,
        }) async {
          final attachmentIds = attachments
              .map((attachment) => attachment.id)
              .toList(growable: false);
          final exactManifest = computeDirectMediaCustodyIntentId(
            messageId: staged.id,
            attachmentIds: attachmentIds,
          );
          final fresh =
              kind == OutgoingOrdinaryAttemptKind.fresh &&
              expected == null &&
              staged.directMediaCustodyIntentId == null;
          final prepared =
              kind == OutgoingOrdinaryAttemptKind.existing &&
              expected != null &&
              expected.id == staged.id &&
              expected.contactPeerId == recipientPeerId &&
              !expected.isIncoming &&
              expected.directMediaCustodyIntentId == exactManifest &&
              staged.directMediaCustodyIntentId == null;
          final valid =
              recipientPeerId.trim().isNotEmpty &&
              staged.id.trim().isNotEmpty &&
              staged.contactPeerId == recipientPeerId &&
              !staged.isIncoming &&
              staged.senderPeerId.trim().isNotEmpty &&
              staged.wireEnvelope == wireEnvelope &&
              wireEnvelope.trim().isNotEmpty &&
              isExactV2DirectChatInitialEnvelope(
                wireEnvelope,
                messageId: staged.id,
                senderPeerId: staged.senderPeerId,
              ) &&
              attachments.isNotEmpty &&
              attachmentIds.toSet().length == attachmentIds.length &&
              attachments.every(
                (attachment) => _isStrictDirectMediaCustodyCandidate(
                  attachment,
                  messageId: staged.id,
                ),
              ) &&
              (fresh || prepared);
          if (!valid) {
            return OutgoingDirectMediaCustodyStageResult(
              outcome: OutgoingOrdinaryMutationOutcome.refused,
              message: expected,
              custody: null,
            );
          }

          final incarnationId = prepared
              ? expected.directMediaCustodyIntentId!
              : sha256
                    .convert(
                      utf8.encode(
                        jsonEncode(<String>[
                          'in_memory_direct_media_custody_v1',
                          recipientPeerId,
                          staged.id,
                          wireEnvelope,
                        ]),
                      ),
                    )
                    .toString()
                    .substring(0, 32);
          final custodyKey = '$recipientPeerId\u0000${staged.id}';
          final existingCustody = messages.directCustodyRows[custodyKey];
          final globalMessageOwners = messages.directCustodyRows.values
              .where((entry) => entry.messageId == staged.id)
              .take(2)
              .toList(growable: false);
          final crossedOrAmbiguousGlobalOwner =
              globalMessageOwners.length > 1 ||
              (globalMessageOwners.isNotEmpty &&
                  globalMessageOwners.single.recipientPeerId !=
                      recipientPeerId);
          final incarnationCollision = messages.directCustodyRows.values.any(
            (entry) =>
                entry.incarnationId == incarnationId &&
                (entry.recipientPeerId != recipientPeerId ||
                    entry.messageId != staged.id),
          );
          if (crossedOrAmbiguousGlobalOwner ||
              incarnationCollision ||
              (existingCustody != null &&
                  (existingCustody.incarnationId != incarnationId ||
                      existingCustody.wireEnvelope != wireEnvelope))) {
            return OutgoingDirectMediaCustodyStageResult(
              outcome: OutgoingOrdinaryMutationOutcome.refused,
              message: await messages.getMessage(staged.id),
              custody: null,
            );
          }

          final stagedResult = await stageOutgoingOrdinaryAttemptWithMedia(
            messageMutationRepository: messages,
            expected: expected,
            staged: staged,
            attachments: attachments,
            kind: kind,
          );
          if (!stagedResult.authorizesTransport ||
              stagedResult.message == null) {
            return OutgoingDirectMediaCustodyStageResult(
              outcome: stagedResult.outcome,
              message: stagedResult.message,
              custody: null,
            );
          }

          final committed = stagedResult.message!;
          await messages.saveMessage(committed);
          final now = committed.createdAt;
          final custody =
              existingCustody ??
              DirectInboxCustodyOutboxEntry(
                recipientPeerId: recipientPeerId,
                messageId: committed.id,
                incarnationId: incarnationId,
                wireEnvelope: wireEnvelope,
                retryCount: 0,
                lastAttemptAt: null,
                lastErrorCode: null,
                createdAt: now,
                updatedAt: now,
              );
          messages.directCustodyRows[custodyKey] = custody;
          return OutgoingDirectMediaCustodyStageResult(
            outcome: stagedResult.outcome,
            message: committed,
            custody: custody,
          );
        };
  }

  /// Owner-migration boundary fixture: installs a legacy/unresolved row
  /// without weakening normal owner-enforcing writes. Production callers can
  /// never reach this seam; owner-scoped reads must exclude the row.
  void seedUnresolvedOwnerRowForTest(MediaAttachment attachment) {
    if (attachment.ownerLane != null) {
      throw ArgumentError('unresolved fixture must have ownerLane == null');
    }
    _attachments[attachment.id] = attachment;
  }

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    if (attachment.ownerLane != null && attachment.ownerLane != owner) {
      throw MediaAttachmentOwnerViolation(
        'attachment ${attachment.id} is stamped ${attachment.ownerLane!.dbValue} '
        'but the caller passed ${owner.dbValue}',
      );
    }
    var stamped = attachment.copyWith(ownerLane: owner);
    final existing = _attachments[attachment.id];
    if (existing != null) {
      if (existing.ownerLane != owner ||
          existing.messageId != stamped.messageId) {
        throw MediaAttachmentOwnerViolation(
          'save would re-parent attachment ${attachment.id} from '
          '(${existing.ownerLane?.dbValue}, ${existing.messageId}) to '
          '(${owner.dbValue}, ${stamped.messageId})',
        );
      }
      // Ordinary replay preserves local-only viewer state.
      stamped = stamped.copyWith(
        isBookmarked: existing.isBookmarked,
        lastPlaybackPositionMs: existing.lastPlaybackPositionMs,
      );
    }
    onSaveAttachment?.call(stamped);
    _attachments[attachment.id] = stamped;
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    return _attachments.values
        .where((a) => a.messageId == messageId && a.ownerLane == owner)
        .toList();
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    return _attachments[id];
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    final result = <String, List<MediaAttachment>>{};
    for (final id in messageIds) {
      final attachments = await getAttachmentsForMessage(id, owner: owner);
      if (attachments.isNotEmpty) {
        result[id] = attachments;
      }
    }
    return result;
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    final a = _attachments[id];
    if (a != null) {
      _attachments[id] = a.copyWith(
        localPath: localPath,
        downloadStatus: 'done',
      );
    }
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    final a = _attachments[id];
    if (a != null) {
      _attachments[id] = a.copyWith(downloadStatus: downloadStatus);
    }
  }

  @override
  Future<bool> recordOrdinaryGroupMediaDownloadFailure(
    String id, {
    required String groupId,
    required String messageId,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
    required bool clearLocalPath,
  }) async {
    final attachment = _attachments[id];
    if (attachment == null ||
        attachment.ownerLane != MediaOwnerLane.group ||
        attachment.messageId != messageId ||
        attachment.downloadStatus != expectedDownloadStatus ||
        attachment.localPath != expectedLocalPath) {
      return false;
    }
    final retryCount = incrementRetryCount
        ? (attachment.downloadRetryCount ?? 0) + 1
        : attachment.downloadRetryCount;
    final status = incrementRetryCount
        ? (retryCount! >= kMaxDownloadRetries
              ? kMediaDownloadStatusDownloadFailed
              : kMediaDownloadStatusFailed)
        : failureStatus;
    _attachments[id] = attachment.copyWith(
      downloadStatus: status,
      downloadRetryCount: retryCount,
      clearLocalPath: clearLocalPath,
    );
    return true;
  }

  @override
  Future<bool> beginOrdinaryGroupAutomaticMediaDownload(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  }) async {
    final attachment = _attachments[id];
    if (attachment == null ||
        attachment.ownerLane != MediaOwnerLane.group ||
        attachment.messageId != messageId ||
        attachment.downloadStatus != expectedDownloadStatus ||
        attachment.localPath != expectedLocalPath ||
        (attachment.downloadRetryCount ?? 0) >= kMaxDownloadRetries ||
        !const {
          kMediaDownloadStatusPending,
          kMediaDownloadStatusDownloading,
          kMediaDownloadStatusFailed,
        }.contains(attachment.downloadStatus)) {
      return false;
    }
    _attachments[id] = attachment.copyWith(
      downloadStatus: kMediaDownloadStatusDownloading,
    );
    return true;
  }

  @override
  Future<bool> commitOrdinaryGroupAutomaticMediaDownloadLocalPath(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  }) async {
    final attachment = _attachments[id];
    if (attachment == null ||
        attachment.ownerLane != MediaOwnerLane.group ||
        attachment.messageId != messageId ||
        attachment.downloadStatus != kMediaDownloadStatusDownloading ||
        attachment.localPath != expectedLocalPath) {
      return false;
    }
    _attachments[id] = attachment.copyWith(
      localPath: localPath,
      downloadStatus: kMediaDownloadStatusDone,
      downloadRetryCount: 0,
    );
    return true;
  }

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final keysToRemove = _attachments.entries
        .where(
          (e) => e.value.messageId == messageId && e.value.ownerLane == owner,
        )
        .map((e) => e.key)
        .toList();
    for (final key in keysToRemove) {
      _attachments.remove(key);
    }
    return keysToRemove.length;
  }

  @override
  Future<int> rollbackNewMessageAttachments({
    required String messageId,
    required Set<String> attachmentIds,
    required MediaOwnerLane owner,
  }) async {
    final unexpected = _attachments.values.any(
      (attachment) =>
          attachment.messageId == messageId &&
          attachment.ownerLane == owner &&
          !attachmentIds.contains(attachment.id),
    );
    if (unexpected) {
      throw StateError(
        'refusing new-message media rollback with unexpected attachment ids',
      );
    }
    return deleteAttachmentsForMessage(messageId, owner: owner);
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async {
    // In a real implementation this would join with messages table.
    // For tests, we don't have that link, so return 0.
    return 0;
  }

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    var count = 0;
    for (final entry in _attachments.entries.toList()) {
      final attachment = entry.value;
      if (attachment.messageId == messageId &&
          attachment.ownerLane == owner &&
          attachment.downloadStatus == 'upload_pending') {
        _attachments[entry.key] = attachment.copyWith(
          downloadStatus: 'upload_failed',
        );
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async {
    return _attachments.values
        .where((a) => a.downloadStatus == 'pending')
        .toList();
  }

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async {
    return _attachments.values
        .where(
          (a) => a.downloadStatus == 'upload_pending' && a.ownerLane == owner,
        )
        .toList();
  }

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttemptWithMedia({
    required OutgoingTransportMutationRepository messageMutationRepository,
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    final ids = attachments.map((attachment) => attachment.id).toSet();
    final staleProjection = _attachments.values
        .where(
          (attachment) =>
              attachment.messageId == staged.id &&
              attachment.ownerLane == MediaOwnerLane.direct &&
              !ids.contains(attachment.id),
        )
        .toList(growable: false);
    final invalid =
        attachments.isEmpty ||
        ids.length != attachments.length ||
        kind == OutgoingOrdinaryAttemptKind.tombstoneInitial ||
        kind == OutgoingOrdinaryAttemptKind.tombstoneRetry ||
        attachments.any(
          (attachment) =>
              attachment.id.isEmpty ||
              attachment.messageId != staged.id ||
              (attachment.ownerLane != null &&
                  attachment.ownerLane != MediaOwnerLane.direct),
        ) ||
        staleProjection.any(
          (attachment) =>
              attachment.downloadStatus != 'upload_pending' ||
              attachment.size != 0 ||
              attachment.contentHash != null ||
              attachment.encryptionKeyBase64 != null ||
              attachment.encryptionNonce != null ||
              attachment.encryptionScheme != null,
        ) ||
        (kind == OutgoingOrdinaryAttemptKind.fresh &&
            _attachments.values.any(
              (attachment) =>
                  attachment.messageId == staged.id &&
                  attachment.ownerLane == MediaOwnerLane.direct &&
                  ids.contains(attachment.id),
            )) ||
        attachments.any((attachment) {
          final existing = _attachments[attachment.id];
          return existing != null &&
              (existing.messageId != staged.id ||
                  existing.ownerLane != MediaOwnerLane.direct);
        });
    if (invalid) {
      return const OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
      );
    }
    final result = await messageMutationRepository.stageOutgoingOrdinaryAttempt(
      expected: expected,
      staged: staged,
      kind: kind,
    );
    if (!result.authorizesTransport) return result;
    if (result.outcome == OutgoingOrdinaryMutationOutcome.idempotent &&
        attachments.any((attachment) {
          final existing = _attachments[attachment.id];
          return existing == null ||
              !_sameOrdinaryOutgoingAttachmentAttempt(
                existing,
                attachment.copyWith(ownerLane: MediaOwnerLane.direct),
              );
        })) {
      return const OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
      );
    }
    for (final stale in staleProjection) {
      _attachments.remove(stale.id);
    }
    for (final attachment in attachments) {
      final stamped = attachment.copyWith(ownerLane: MediaOwnerLane.direct);
      final existing = _attachments[stamped.id];
      _attachments[stamped.id] = existing == null
          ? stamped
          : stamped.copyWith(
              isBookmarked: existing.isBookmarked,
              lastPlaybackPositionMs: existing.lastPlaybackPositionMs,
            );
    }
    final committed = _attachments.values
        .where(
          (attachment) =>
              attachment.messageId == staged.id &&
              attachment.ownerLane == MediaOwnerLane.direct,
        )
        .toList(growable: false);
    return OutgoingOrdinaryMutationResult(
      outcome:
          result.outcome == OutgoingOrdinaryMutationOutcome.idempotent &&
              staleProjection.isNotEmpty
          ? OutgoingOrdinaryMutationOutcome.applied
          : result.outcome,
      message: result.message?.copyWith(media: committed),
    );
  }

  @override
  Future<OutgoingDirectMediaCustodyStageResult>
  stageOutgoingDirectMediaInboxCustody({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String wireEnvelope,
    String? wireMediaBlobManifestHash,
    int? wireMediaBlobExpiresAtMs,
  }) {
    final callback = onStageOutgoingDirectMediaInboxCustody;
    if (callback == null) {
      return Future<OutgoingDirectMediaCustodyStageResult>.value(
        const OutgoingDirectMediaCustodyStageResult(
          outcome: OutgoingOrdinaryMutationOutcome.refused,
          message: null,
          custody: null,
        ),
      );
    }
    return callback(
      expected: expected,
      staged: staged,
      attachments: attachments,
      kind: kind,
      recipientPeerId: recipientPeerId,
      wireEnvelope: wireEnvelope,
    );
  }

  int get count => _attachments.length;
}

bool _sameOrdinaryOutgoingAttachmentAttempt(
  MediaAttachment current,
  MediaAttachment candidate,
) {
  final currentMap = current.toMap()
    ..remove('is_bookmarked')
    ..remove('last_playback_position_ms')
    ..['upload_retry_count'] = current.uploadRetryCount ?? 0
    ..['download_retry_count'] = current.downloadRetryCount ?? 0;
  final candidateMap = candidate.toMap()
    ..remove('is_bookmarked')
    ..remove('last_playback_position_ms')
    ..['upload_retry_count'] = candidate.uploadRetryCount ?? 0
    ..['download_retry_count'] = candidate.downloadRetryCount ?? 0;
  return currentMap.length == candidateMap.length &&
      currentMap.entries.every(
        (entry) => candidateMap[entry.key] == entry.value,
      );
}

final RegExp _strictDirectMediaSha256 = RegExp(r'^[0-9a-f]{64}$');

bool _isStrictDirectMediaCustodyCandidate(
  MediaAttachment attachment, {
  required String messageId,
}) {
  final localPath = attachment.localPath?.trim();
  final normalizedPath = localPath?.replaceAll('\\', '/');
  return attachment.id.trim().isNotEmpty &&
      attachment.messageId == messageId &&
      attachment.ownerLane == MediaOwnerLane.direct &&
      attachment.mime.trim().isNotEmpty &&
      attachment.mediaType ==
          MediaAttachment.mediaTypeFromMime(attachment.mime) &&
      attachment.size > 0 &&
      attachment.downloadStatus == 'done' &&
      attachment.createdAt.trim().isNotEmpty &&
      localPath != null &&
      localPath.isNotEmpty &&
      !normalizedPath!.startsWith('pending_uploads/') &&
      !normalizedPath.contains('/pending_uploads/') &&
      _strictDirectMediaSha256.hasMatch(attachment.contentHash ?? '') &&
      (attachment.thumbnailHash == null ||
          _strictDirectMediaSha256.hasMatch(attachment.thumbnailHash!)) &&
      (attachment.encryptionKeyBase64?.trim().isNotEmpty ?? false) &&
      (attachment.encryptionNonce?.trim().isNotEmpty ?? false) &&
      attachment.encryptionScheme ==
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1 &&
      (attachment.width == null || attachment.width! >= 0) &&
      (attachment.height == null || attachment.height! >= 0) &&
      (attachment.durationMs == null || attachment.durationMs! >= 0) &&
      (attachment.waveform == null ||
          attachment.waveform!.every(
            (sample) => sample.isFinite && sample >= 0 && sample <= 1,
          ));
}
