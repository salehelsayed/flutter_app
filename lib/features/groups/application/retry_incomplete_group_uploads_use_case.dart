import 'dart:io';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_connectivity_probe.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

class _PreparedGroupRetryUpload {
  final MediaAttachment pendingAttachment;
  final String absolutePath;

  const _PreparedGroupRetryUpload({
    required this.pendingAttachment,
    required this.absolutePath,
  });
}

const Duration kFreshGroupUploadRetrySendingThreshold = Duration(minutes: 2);

bool _retryIncompleteGroupUploadsInFlight = false;

/// Re-uploads any group attachment rows with downloadStatus='upload_pending',
/// grouped by messageId, then re-sends the full message once per group message.
///
/// This mirrors the durable retry contract used by the group composer:
/// - only group-owned rows are processed
/// - done attachments are preserved
/// - only upload_pending rows are re-uploaded
/// - the original messageId/timestamp are reused on send
/// - durable pending_uploads copies are used when available
Future<int> retryIncompleteGroupUploads({
  required GroupRepository groupRepo,
  required GroupMessageRepository groupMsgRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  UploadMediaFn uploadMediaFn = uploadMedia,
  MediaFileManager? mediaFileManager,
  String? messageId,
  GroupPrivateMediaAvailability privateMediaAvailability =
      productionGroupPrivateMediaAvailability,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
  bool requireOsConnectivity = false,
  MediaUploadConnectivityProbe connectivityProbe = probeMediaUploadConnectivity,
  GroupUploadRetryProjectionRepository? uploadRetryProjectionRepo,
  GroupManualUploadRetryRearmRepository? uploadRetryRearmRepo,
  TryClaimMediaUploadLeaseForSource? tryClaimUploadLease,
  ReleaseMediaUploadLease? releaseUploadLease,
  bool manualRetry = false,
}) async {
  final retryStopwatch = Stopwatch()..start();
  void emitRetryTiming({
    required String outcome,
    required int attachmentCount,
    required int messageCount,
    required int succeeded,
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING',
      details: {
        'elapsedMs': retryStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'attachmentCount': attachmentCount,
        'messageCount': messageCount,
        'succeeded': succeeded,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_START',
    details: {},
  );

  if (requireOsConnectivity && !await connectivityProbe()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_SKIPPED_NO_CONNECTIVITY',
      details: {},
    );
    emitRetryTiming(
      outcome: 'no_connectivity',
      attachmentCount: 0,
      messageCount: 0,
      succeeded: 0,
    );
    return 0;
  }

  final GroupUploadRetryProjectionRepository? projection =
      uploadRetryProjectionRepo ??
      (groupMsgRepo is GroupUploadRetryProjectionRepository
          ? groupMsgRepo as GroupUploadRetryProjectionRepository
          : null);

  // Automatic passes are coalesced process-wide. Manual Retry bypasses this
  // coarse guard and relies on the exact all-or-none blob lease below, so an
  // unrelated automatic upload cannot turn a valid user action into a dead
  // tap. The lease still prevents overlap on the same attachment set.
  final ownsProcessCoalescer = !manualRetry;
  if (ownsProcessCoalescer && _retryIncompleteGroupUploadsInFlight) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_SKIPPED_IN_FLIGHT',
      details: {},
    );
    emitRetryTiming(
      outcome: 'already_running',
      attachmentCount: 0,
      messageCount: 0,
      succeeded: 0,
    );
    return 0;
  }

  if (ownsProcessCoalescer) {
    _retryIncompleteGroupUploadsInFlight = true;
  }
  MediaUploadLease? manualUploadLease;
  try {
    if (manualRetry) {
      if (messageId == null) {
        emitRetryTiming(
          outcome: 'manual_message_required',
          attachmentCount: 0,
          messageCount: 0,
          succeeded: 0,
        );
        return 0;
      }
      final allAttachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.group,
      );
      final unfinished = allAttachments
          .where((attachment) => attachment.downloadStatus != 'done')
          .toList(growable: false);
      if (unfinished.isEmpty ||
          unfinished.length > kReuploadMaxAttachmentsPerMessage ||
          unfinished.any((attachment) {
            final retryCount = attachment.uploadRetryCount ?? 0;
            return attachment.downloadStatus != 'upload_pending' &&
                !(attachment.downloadStatus == 'upload_failed' &&
                    retryCount >= kMaxUploadRetries);
          })) {
        emitRetryTiming(
          outcome: 'manual_not_eligible',
          attachmentCount: unfinished.length,
          messageCount: 1,
          succeeded: 0,
        );
        return 0;
      }

      final expectations = <ManualUploadRetryAttachmentExpectation>[];
      for (final attachment in unfinished) {
        final storedPath = attachment.localPath?.trim();
        if (storedPath == null || storedPath.isEmpty) {
          emitRetryTiming(
            outcome: 'manual_source_missing',
            attachmentCount: unfinished.length,
            messageCount: 1,
            succeeded: 0,
          );
          return 0;
        }
        try {
          final resolvedPath = mediaFileManager == null
              ? storedPath
              : await mediaFileManager.resolveStoredPath(storedPath);
          if (!await File(resolvedPath).exists()) {
            emitRetryTiming(
              outcome: 'manual_source_missing',
              attachmentCount: unfinished.length,
              messageCount: 1,
              succeeded: 0,
            );
            return 0;
          }
        } catch (_) {
          emitRetryTiming(
            outcome: 'manual_source_missing',
            attachmentCount: unfinished.length,
            messageCount: 1,
            succeeded: 0,
          );
          return 0;
        }
        expectations.add(
          ManualUploadRetryAttachmentExpectation(
            attachmentId: attachment.id,
            storedLocalPath: storedPath,
            downloadStatus: attachment.downloadStatus,
            uploadRetryCount: attachment.uploadRetryCount ?? 0,
          ),
        );
      }

      // Rearm is a durable budget mutation, so prove the core send authority
      // before claiming or changing any terminal row. These checks are run
      // again after rearm to catch subsequent races; the parent status and the
      // exact attachment snapshot are also revalidated atomically by the
      // repository CAS.
      final manualIdentity = await identityRepo.loadIdentity();
      if (manualIdentity == null) {
        emitRetryTiming(
          outcome: 'manual_no_identity',
          attachmentCount: unfinished.length,
          messageCount: 1,
          succeeded: 0,
        );
        return 0;
      }
      final manualParent = await groupMsgRepo.getMessage(messageId);
      if (manualParent == null ||
          manualParent.isIncoming ||
          manualParent.status != 'failed') {
        emitRetryTiming(
          outcome: 'manual_parent_not_eligible',
          attachmentCount: unfinished.length,
          messageCount: 1,
          succeeded: 0,
        );
        return 0;
      }
      if (manualParent.privateMediaPolicy.isUnsupported ||
          (manualParent.privateMediaPolicy.isPrivate &&
              !privateMediaAvailability.isEnabled) ||
          (manualParent.privateMediaPolicy.isPrivate &&
              !await requalifyCurrentPrivateGroupMediaSend(
                groupRepo: groupRepo,
                msgRepo: groupMsgRepo,
                expectedParent: manualParent,
                senderPeerId: manualIdentity.peerId,
              ))) {
        emitRetryTiming(
          outcome: 'manual_private_policy_not_eligible',
          attachmentCount: unfinished.length,
          messageCount: 1,
          succeeded: 0,
        );
        return 0;
      }
      if (await groupRepo.getGroup(manualParent.groupId) == null) {
        emitRetryTiming(
          outcome: 'manual_group_missing',
          attachmentCount: unfinished.length,
          messageCount: 1,
          succeeded: 0,
        );
        return 0;
      }

      final rearm =
          uploadRetryRearmRepo ??
          (groupMsgRepo is GroupManualUploadRetryRearmRepository
              ? groupMsgRepo as GroupManualUploadRetryRearmRepository
              : null);
      if (tryClaimUploadLease == null ||
          releaseUploadLease == null ||
          rearm == null) {
        emitRetryTiming(
          outcome: 'manual_capability_unavailable',
          attachmentCount: unfinished.length,
          messageCount: 1,
          succeeded: 0,
        );
        return 0;
      }

      manualUploadLease = tryClaimUploadLease(
        unfinished.map((attachment) => attachment.id),
      );
      if (manualUploadLease == null) {
        emitRetryTiming(
          outcome: 'manual_ownership_unavailable',
          attachmentCount: unfinished.length,
          messageCount: 1,
          succeeded: 0,
        );
        return 0;
      }

      final applied = await rearm.rearmUploadRetryForManualRetry(
        messageId: messageId,
        attachments: expectations,
      );
      if (!applied) {
        emitRetryTiming(
          outcome: 'manual_rearm_race_lost',
          attachmentCount: unfinished.length,
          messageCount: 1,
          succeeded: 0,
        );
        return 0;
      }
    }

    final allPendingAttachments = await mediaAttachmentRepo
        .getUploadPendingAttachments(owner: MediaOwnerLane.group);
    final pendingAttachments = messageId == null
        ? allPendingAttachments
        : allPendingAttachments
              .where((attachment) => attachment.messageId == messageId)
              .toList(growable: false);
    if (pendingAttachments.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_NONE',
        details: {},
      );
      emitRetryTiming(
        outcome: 'none',
        attachmentCount: 0,
        messageCount: 0,
        succeeded: 0,
      );
      return 0;
    }

    final identity = await identityRepo.loadIdentity();
    if (identity == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_NO_IDENTITY',
        details: {},
      );
      emitRetryTiming(
        outcome: 'no_identity',
        attachmentCount: pendingAttachments.length,
        messageCount: 0,
        succeeded: 0,
      );
      return 0;
    }

    final byMessageId = <String, List<MediaAttachment>>{};
    for (final attachment in pendingAttachments) {
      byMessageId.putIfAbsent(attachment.messageId, () => []).add(attachment);
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_FOUND',
      details: {
        'attachmentCount': pendingAttachments.length,
        'messageCount': byMessageId.length,
      },
    );

    var successCount = 0;

    for (final entry in byMessageId.entries) {
      final messageId = entry.key;
      final pendingAttachmentsForMessage = entry.value;

      // E11: the process-wide group guard above only coalesces whole passes.
      // Blob ownership is this atomic all-or-none lease, shared with direct,
      // foreground, restored, periodic, resume, and manual upload lanes.
      final uploadLease =
          manualUploadLease ??
          tryClaimUploadLease?.call(
            pendingAttachmentsForMessage.map((attachment) => attachment.id),
          );
      if (tryClaimUploadLease != null && uploadLease == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_IN_FLIGHT',
          details: {'attachmentCount': pendingAttachmentsForMessage.length},
        );
        continue;
      }

      try {
        final parentMessage = await groupMsgRepo.getMessage(messageId);
        if (parentMessage == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_NO_MSG',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
            },
          );
          continue;
        }

        if (parentMessage.isIncoming) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_INCOMING',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
            },
          );
          continue;
        }

        if (parentMessage.status != 'sending' &&
            parentMessage.status != 'queued_offline' &&
            parentMessage.status != 'failed') {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_STATUS',
            details: {'status': parentMessage.status},
          );
          continue;
        }

        if (_isFreshOutgoingGroupSend(parentMessage)) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_FRESH_SENDING',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'thresholdSeconds':
                  kFreshGroupUploadRetrySendingThreshold.inSeconds,
            },
          );
          continue;
        }

        if (parentMessage.privateMediaPolicy.isUnsupported ||
            (parentMessage.privateMediaPolicy.isPrivate &&
                !privateMediaAvailability.isEnabled) ||
            (parentMessage.privateMediaPolicy.isPrivate &&
                !await requalifyCurrentPrivateGroupMediaSend(
                  groupRepo: groupRepo,
                  msgRepo: groupMsgRepo,
                  expectedParent: parentMessage,
                  senderPeerId: identity.peerId,
                ))) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_PRIVATE_POLICY',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
            },
          );
          continue;
        }

        final allAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);

        final group = await groupRepo.getGroup(parentMessage.groupId);
        if (group == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_NO_GROUP',
            details: {
              'groupId': parentMessage.groupId.length > 8
                  ? parentMessage.groupId.substring(0, 8)
                  : parentMessage.groupId,
            },
          );
          continue;
        }

        final members = await groupRepo.getMembers(parentMessage.groupId);
        var allowedPeers = groupMediaAllowedPeersForMembers(members);

        final preparedUploads = <_PreparedGroupRetryUpload>[];
        final resolvedPendingAttachments = <String, MediaAttachment>{};
        var allUploadsSucceeded = true;
        var hasTerminalInvalidMedia = false;

        for (final attachment in pendingAttachmentsForMessage) {
          final validation = GroupMediaMimePolicy.validateDescriptor(
            mime: attachment.mime,
            mediaType: attachment.mediaType,
          );
          if (!validation.isValid) {
            await _projectTerminalGroupUploadFailure(
              projection: projection,
              mediaAttachmentRepo: mediaAttachmentRepo,
              messageId: messageId,
              attachment: attachment,
              stage: UploadMediaStage.validation,
              errorCode: 'INVALID_GROUP_MEDIA_DESCRIPTOR',
            );
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_INVALID_MIME',
              details: {
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
                'mime': attachment.mime,
                'mediaType': attachment.mediaType,
                'reason': validation.reason,
              },
            );
            allUploadsSucceeded = false;
            hasTerminalInvalidMedia = true;
            break;
          }

          var localPath = attachment.localPath;
          if (localPath == null || localPath.isEmpty) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_NO_PATH',
              details: {
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
              },
            );
            allUploadsSucceeded = false;
            hasTerminalInvalidMedia = true;
            await _projectTerminalGroupUploadFailure(
              projection: projection,
              mediaAttachmentRepo: mediaAttachmentRepo,
              messageId: messageId,
              attachment: attachment,
              stage: UploadMediaStage.localSource,
              errorCode: 'MISSING_LOCAL_SOURCE',
            );
            break;
          }

          if (mediaFileManager != null) {
            localPath = await mediaFileManager.resolveStoredPath(localPath);
          }

          final fileValidation = await GroupMediaMimePolicy.validateFile(
            path: localPath,
            mime: attachment.mime,
            mediaType: attachment.mediaType,
          );
          if (!fileValidation.isValid) {
            await _projectTerminalGroupUploadFailure(
              projection: projection,
              mediaAttachmentRepo: mediaAttachmentRepo,
              messageId: messageId,
              attachment: attachment,
              stage: UploadMediaStage.localSource,
              errorCode: 'INVALID_LOCAL_SOURCE',
            );
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_INVALID_FILE',
              details: {
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
                'mime': attachment.mime,
                'mediaType': attachment.mediaType,
                'reason': fileValidation.reason,
              },
            );
            allUploadsSucceeded = false;
            hasTerminalInvalidMedia = true;
            break;
          }

          final resolvedSize = await _resolveRetryAttachmentSize(
            attachment: attachment,
            absolutePath: localPath,
          );
          if (resolvedSize == null) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_NO_SIZE',
              details: {
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
              },
            );
            allUploadsSucceeded = false;
            hasTerminalInvalidMedia = true;
            await _projectTerminalGroupUploadFailure(
              projection: projection,
              mediaAttachmentRepo: mediaAttachmentRepo,
              messageId: messageId,
              attachment: attachment,
              stage: UploadMediaStage.localSource,
              errorCode: 'UNREADABLE_LOCAL_SOURCE',
            );
            break;
          }

          final sizeValidation = GroupMediaSizePolicy.validateSize(
            sizeBytes: resolvedSize,
            mime: attachment.mime,
          );
          if (!sizeValidation.isValid) {
            final failed = attachment.copyWith(
              size: resolvedSize,
              downloadStatus: 'upload_failed',
            );
            await _projectTerminalGroupUploadFailure(
              projection: projection,
              mediaAttachmentRepo: mediaAttachmentRepo,
              messageId: messageId,
              attachment: failed,
              stage: UploadMediaStage.validation,
              errorCode: 'INVALID_GROUP_MEDIA_SIZE',
            );
            resolvedPendingAttachments[attachment.id] = failed;
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_INVALID_SIZE',
              details: {
                'attachmentId': attachment.id.length > 8
                    ? attachment.id.substring(0, 8)
                    : attachment.id,
                'reason': sizeValidation.reason,
              },
            );
            allUploadsSucceeded = false;
            hasTerminalInvalidMedia = true;
            break;
          }

          final resolvedAttachment = attachment.copyWith(size: resolvedSize);
          resolvedPendingAttachments[attachment.id] = resolvedAttachment;
          preparedUploads.add(
            _PreparedGroupRetryUpload(
              pendingAttachment: resolvedAttachment,
              absolutePath: localPath,
            ),
          );
        }

        if (!allUploadsSucceeded) {
          if (hasTerminalInvalidMedia) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_MSG_DEFERRED',
              details: {
                'messageId': messageId.length > 8
                    ? messageId.substring(0, 8)
                    : messageId,
                'reason': 'invalid_group_media',
                'totalAttachments': pendingAttachmentsForMessage.length,
              },
            );
            continue;
          }

          final failedCount = <String, int>{};
          for (final attachment in pendingAttachmentsForMessage) {
            failedCount[attachment.id] = (attachment.uploadRetryCount ?? 0) + 1;
            final retryCount = failedCount[attachment.id]!;
            await mediaAttachmentRepo.saveAttachment(
              attachment.copyWith(
                downloadStatus: retryCount >= kMaxUploadRetries
                    ? 'upload_failed'
                    : 'upload_pending',
                uploadRetryCount: retryCount,
              ),
              owner: MediaOwnerLane.group,
            );
          }
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_MSG_DEFERRED',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'reason': 'invalid_pending_path',
              'totalAttachments': pendingAttachmentsForMessage.length,
            },
          );
          continue;
        }

        final preUploadAttachments = allAttachments
            .map(
              (attachment) =>
                  resolvedPendingAttachments[attachment.id] ?? attachment,
            )
            .toList(growable: false);
        final preUploadSizeValidation =
            GroupMediaSizePolicy.validateAttachments(preUploadAttachments);
        if (!preUploadSizeValidation.isValid) {
          for (final attachment in pendingAttachmentsForMessage) {
            await _projectTerminalGroupUploadFailure(
              projection: projection,
              mediaAttachmentRepo: mediaAttachmentRepo,
              messageId: messageId,
              attachment:
                  resolvedPendingAttachments[attachment.id] ?? attachment,
              stage: UploadMediaStage.validation,
              errorCode: 'INVALID_GROUP_MEDIA_TOTAL_SIZE',
            );
          }
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_MSG_DEFERRED',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'reason': preUploadSizeValidation.reason,
              'totalAttachments': preUploadAttachments.length,
            },
          );
          continue;
        }

        if (parentMessage.privateMediaPolicy.isPrivate) {
          final preUploadQualification =
              await qualifyCurrentPrivateGroupMediaSend(
                groupRepo: groupRepo,
                msgRepo: groupMsgRepo,
                expectedParent: parentMessage,
                senderPeerId: identity.peerId,
                inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
              );
          if (preUploadQualification == null) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SKIP_PRIVATE_POLICY',
              details: {
                'messageId': messageId.length > 8
                    ? messageId.substring(0, 8)
                    : messageId,
                'reason': 'pre_upload_requalification_failed',
              },
            );
            continue;
          }
          allowedPeers = groupMediaAllowedPeersForMembers(
            preUploadQualification.members,
          );
        }

        final uploadOutcomes = await Future.wait(
          preparedUploads.map((plan) async {
            final mime = plan.pendingAttachment.mime;
            final outcome = await runUploadMedia(
              uploadMediaFn: uploadMediaFn,
              bridge: bridge,
              localFilePath: plan.absolutePath,
              mime: mime,
              recipientPeerId: parentMessage.groupId,
              mediaFileManager: mediaFileManager,
              width: plan.pendingAttachment.width,
              height: plan.pendingAttachment.height,
              durationMs: plan.pendingAttachment.durationMs,
              waveform: plan.pendingAttachment.waveform,
              allowedPeers: allowedPeers,
              blobId: plan.pendingAttachment.id,
            );
            return outcome;
          }),
        );

        final failedPlans = <_PreparedGroupRetryUpload>[];
        for (var i = 0; i < uploadOutcomes.length; i++) {
          final plan = preparedUploads[i];
          final outcome = uploadOutcomes[i];
          if (outcome case final UploadMediaFailed failure) {
            failedPlans.add(plan);
            if (projection != null) {
              await projection.projectUploadFailure(
                messageId: messageId,
                attachmentId: plan.pendingAttachment.id,
                failure: failure,
              );
            }
            continue;
          }
          final successfulUpload = (outcome as UploadMediaSucceeded).attachment;

          final contentHash =
              successfulUpload.contentHash ??
              await GroupMediaIntegrityPolicy.computeFileSha256Hex(
                plan.absolutePath,
              );
          final completed = successfulUpload.copyWith(
            id: plan.pendingAttachment.id,
            messageId: parentMessage.id,
            downloadStatus: 'done',
            uploadRetryCount: plan.pendingAttachment.uploadRetryCount,
            contentHash: contentHash,
          );
          await mediaAttachmentRepo.saveAttachment(
            completed,
            owner: MediaOwnerLane.group,
          );
        }

        if (failedPlans.isNotEmpty) {
          if (projection == null) {
            // Compatibility for lightweight repository doubles that predate
            // the atomic capability. Production projects each typed failure
            // exactly once in the loop above.
            for (final plan in failedPlans) {
              final nextRetryCount =
                  (plan.pendingAttachment.uploadRetryCount ?? 0) + 1;
              await mediaAttachmentRepo.saveAttachment(
                plan.pendingAttachment.copyWith(
                  downloadStatus: nextRetryCount >= kMaxUploadRetries
                      ? 'upload_failed'
                      : 'upload_pending',
                  uploadRetryCount: nextRetryCount,
                ),
                owner: MediaOwnerLane.group,
              );
            }
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_MSG_DEFERRED',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'reason': 'transient_failure',
              'totalAttachments': pendingAttachmentsForMessage.length,
            },
          );
          continue;
        }

        final refreshedMessage = await groupMsgRepo.getMessage(messageId);
        final refreshedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
        final abortReason = _lateGroupSendAbortReason(
          message: refreshedMessage,
          attachments: refreshedAttachments,
          expectedAttachmentIds: {
            for (final attachment in allAttachments) attachment.id,
          },
        );
        if (abortReason != null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_ABORT_FINAL_SEND',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'reason': abortReason,
            },
          );
          continue;
        }

        if (refreshedMessage!.privateMediaPolicy.isUnsupported ||
            (refreshedMessage.privateMediaPolicy.isPrivate &&
                !await requalifyCurrentPrivateGroupMediaSend(
                  groupRepo: groupRepo,
                  msgRepo: groupMsgRepo,
                  expectedParent: refreshedMessage,
                  senderPeerId: identity.peerId,
                ))) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_ABORT_FINAL_SEND',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'reason': 'private_media_parent_not_currently_qualified',
            },
          );
          continue;
        }

        final fullAttachmentList = refreshedAttachments
            .where((attachment) => attachment.downloadStatus == 'done')
            .toList(growable: false);

        final senderDeviceId = p2pService.currentState.peerId?.trim();
        final currentSenderDeviceId =
            senderDeviceId == null || senderDeviceId.isEmpty
            ? null
            : senderDeviceId;
        final (result, _) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
          groupId: refreshedMessage.groupId,
          text: refreshedMessage.text,
          senderPeerId: identity.peerId,
          senderPublicKey: identity.publicKey,
          senderPrivateKey: identity.privateKey,
          senderUsername: identity.username,
          messageId: refreshedMessage.id,
          logicalDeliveryId:
              refreshedMessage.logicalDeliveryId ?? refreshedMessage.id,
          timestamp: refreshedMessage.timestamp,
          quotedMessageId: refreshedMessage.quotedMessageId,
          isForwarded: refreshedMessage.isForwarded,
          privateMediaPolicy: refreshedMessage.privateMediaPolicy,
          privateMediaAvailability: privateMediaAvailability,
          expectedPrivateParentBeforeDispatch:
              refreshedMessage.privateMediaPolicy.isPrivate
              ? refreshedMessage
              : null,
          senderDeviceId: currentSenderDeviceId,
          senderTransportPeerId: currentSenderDeviceId,
          mediaAttachments: fullAttachmentList,
          mediaAttachmentRepo: mediaAttachmentRepo,
          inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
          emitTimingEvent: false,
        );

        // 210b: queuedOffline counts as completed upload work — the media is
        // durably re-uploaded and the row is honestly queued (repush lane
        // settles it), so the staging dir can go and the pass must not
        // mislabel it SEND_FAILED.
        if (result == SendGroupMessageResult.success ||
            result == SendGroupMessageResult.successNoPeers ||
            result == SendGroupMessageResult.queuedOffline) {
          successCount++;
          if (mediaFileManager != null) {
            try {
              await mediaFileManager.deletePendingUploadDir(messageId);
            } catch (_) {}
          }
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SUCCESS',
            details: {
              'messageId': messageId.length > 8
                  ? messageId.substring(0, 8)
                  : messageId,
              'attachmentCount': fullAttachmentList.length,
              if (result == SendGroupMessageResult.successNoPeers)
                'topicPeers': 0,
              if (result == SendGroupMessageResult.queuedOffline)
                'queuedOffline': true,
            },
          );
        } else {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_SEND_FAILED',
            details: {'result': result.name},
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_GROUP_UPLOAD_ERROR',
          details: {'error': e.toString()},
        );
      } finally {
        if (uploadLease != null) {
          releaseUploadLease?.call(uploadLease);
          if (identical(uploadLease, manualUploadLease)) {
            manualUploadLease = null;
          }
        }
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_INCOMPLETE_GROUP_UPLOADS_COMPLETE',
      details: {
        'totalAttachments': pendingAttachments.length,
        'totalMessages': byMessageId.length,
        'succeeded': successCount,
      },
    );
    emitRetryTiming(
      outcome: 'complete',
      attachmentCount: pendingAttachments.length,
      messageCount: byMessageId.length,
      succeeded: successCount,
    );

    return successCount;
  } finally {
    if (manualUploadLease != null) {
      releaseUploadLease?.call(manualUploadLease);
    }
    if (ownsProcessCoalescer) {
      _retryIncompleteGroupUploadsInFlight = false;
    }
  }
}

bool _isFreshOutgoingGroupSend(GroupMessage message) {
  if (message.isIncoming || message.status != 'sending') {
    return false;
  }
  final age = DateTime.now().toUtc().difference(message.timestamp.toUtc());
  return age < kFreshGroupUploadRetrySendingThreshold;
}

String? _lateGroupSendAbortReason({
  required GroupMessage? message,
  required List<MediaAttachment> attachments,
  required Set<String> expectedAttachmentIds,
}) {
  if (message == null) {
    return 'message_missing';
  }
  if (message.isIncoming) {
    return 'message_incoming';
  }
  if (message.status != 'sending' &&
      message.status != 'queued_offline' &&
      message.status != 'failed') {
    return 'message_status_${message.status}';
  }

  if (attachments.length != expectedAttachmentIds.length ||
      attachments.any(
        (attachment) => !expectedAttachmentIds.contains(attachment.id),
      )) {
    return 'attachment_set_changed';
  }
  if (attachments.any((attachment) => attachment.downloadStatus != 'done')) {
    return 'attachments_not_done';
  }
  final sizeValidation = GroupMediaSizePolicy.validateAttachments(attachments);
  if (!sizeValidation.isValid) {
    return sizeValidation.reason ?? 'invalid_group_media_size';
  }
  return null;
}

Future<int?> _resolveRetryAttachmentSize({
  required MediaAttachment attachment,
  required String absolutePath,
}) async {
  if (attachment.size > 0) {
    return attachment.size;
  }

  try {
    final file = File(absolutePath);
    if (!await file.exists()) return null;
    final size = await file.length();
    return size > 0 ? size : null;
  } catch (_) {
    return null;
  }
}

Future<void> _projectTerminalGroupUploadFailure({
  required GroupUploadRetryProjectionRepository? projection,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required String messageId,
  required MediaAttachment attachment,
  required UploadMediaStage stage,
  required String errorCode,
}) async {
  if (projection != null) {
    await projection.projectUploadFailure(
      messageId: messageId,
      attachmentId: attachment.id,
      failure: UploadMediaFailed(
        stage: stage,
        disposition: UploadMediaDisposition.terminal,
        errorCode: errorCode,
      ),
    );
    return;
  }
  await mediaAttachmentRepo.saveAttachment(
    attachment.copyWith(downloadStatus: 'upload_failed'),
    owner: MediaOwnerLane.group,
  );
}
