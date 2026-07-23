import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_upload_completion_authority.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_allowed_peers.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/self_removed_group_lifecycle_guard.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

typedef DeleteReplacedForegroundGroupMediaFile =
    Future<void> Function(MediaAttachment attachment);

/// Exact result of one production foreground group-upload completion leaf.
class ForegroundGroupUploadLeafResult {
  const ForegroundGroupUploadLeafResult({
    required this.outcome,
    this.completedAttachment,
    this.failureProjection,
  });

  final UploadMediaOutcome outcome;
  final MediaAttachment? completedAttachment;
  final UploadRetryProjectionResult? failureProjection;
}

/// Shared authority boundary for ordinary, voice, and device-proof foreground
/// group media. The caller owns capture/durable-copy preparation and final
/// parent publication; this leaf owns current lifecycle/member/ACL
/// requalification, the SQL-default reload comparison, upload, exact
/// completion CAS, and bounded failure projection.
Future<ForegroundGroupUploadLeafResult?> runForegroundGroupUploadLeaf({
  required GroupRepository groupRepository,
  required GroupMessageRepository groupMessageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required GroupMessage expectedParent,
  required MediaAttachment expectedAttachment,
  required String senderPeerId,
  required Future<UploadMediaOutcome> Function(List<String> allowedPeers)
  upload,
  required Future<MediaAttachment> Function(MediaAttachment uploaded)
  buildCompleted,
  GroupPrivateMediaAvailability privateMediaAvailability =
      productionGroupPrivateMediaAvailability,
  GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository,
  GroupUploadRetryProjectionRepository? uploadRetryProjectionRepository,
  DeleteReplacedForegroundGroupMediaFile? deleteReplacedAttachmentFile,
  bool replaceExistingAttachments = false,
}) async {
  final projection =
      uploadRetryProjectionRepository ??
      (groupMessageRepository is GroupUploadRetryProjectionRepository
          ? groupMessageRepository as GroupUploadRetryProjectionRepository
          : null);
  final guarded =
      await runSelfRemovedGroupLifecycleLeaf<ForegroundGroupUploadLeafResult?>(
        groupRepo: groupRepository,
        groupId: expectedParent.groupId,
        action: (currentGroup) async {
          if (currentGroup.isDissolved) return null;
          final currentParent = await groupMessageRepository.getMessage(
            expectedParent.id,
          );
          if (currentParent == null ||
              !sameExactGroupPrivateMediaDispatchParent(
                currentParent,
                expectedParent,
              )) {
            return null;
          }
          final members = await groupRepository.getMembers(
            expectedParent.groupId,
          );
          if (!members.any((member) => member.peerId == senderPeerId)) {
            return null;
          }
          var allowedPeers = groupMediaAllowedPeersForMembers(members);
          if (expectedParent.privateMediaPolicy.isPrivate) {
            if (!privateMediaAvailability.isEnabled) return null;
            final qualification = await qualifyCurrentPrivateGroupMediaSend(
              groupRepo: groupRepository,
              msgRepo: groupMessageRepository,
              expectedParent: expectedParent,
              senderPeerId: senderPeerId,
              inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
            );
            if (qualification == null) return null;
            allowedPeers = groupMediaAllowedPeersForMembers(
              qualification.members,
            );
          }

          final currentAttachments = await mediaAttachmentRepository
              .getAttachmentsForMessage(
                expectedParent.id,
                owner: MediaOwnerLane.group,
              );
          MediaAttachment? currentAttachment;
          for (final attachment in currentAttachments) {
            if (attachment.id == expectedAttachment.id) {
              currentAttachment = attachment;
              break;
            }
          }
          if (currentAttachment != null &&
              !sameExactGroupRetryAttachment(
                currentAttachment,
                expectedAttachment,
              )) {
            return null;
          }
          if (currentAttachment == null) {
            if (replaceExistingAttachments) {
              for (final attachment in currentAttachments) {
                await deleteReplacedAttachmentFile?.call(attachment);
              }
              await mediaAttachmentRepository.deleteAttachmentsForMessage(
                expectedParent.id,
                owner: MediaOwnerLane.group,
              );
            }
            await mediaAttachmentRepository.saveAttachment(
              expectedAttachment,
              owner: MediaOwnerLane.group,
            );
            final persistedAttachments = await mediaAttachmentRepository
                .getAttachmentsForMessage(
                  expectedParent.id,
                  owner: MediaOwnerLane.group,
                );
            for (final attachment in persistedAttachments) {
              if (attachment.id == expectedAttachment.id) {
                currentAttachment = attachment;
                break;
              }
            }
            if (currentAttachment == null ||
                !sameExactGroupRetryAttachment(
                  currentAttachment,
                  expectedAttachment,
                )) {
              return null;
            }
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_CONV_FL_MEDIA_DURABLE_ROW_SAVE',
              details: {
                'messageId': _shortId(expectedParent.id),
                'blobId': _shortId(expectedAttachment.id),
              },
            );
          }

          Future<ForegroundGroupUploadLeafResult?> projectOwnedFailure(
            UploadMediaFailed failure,
          ) async {
            final latestParent = await groupMessageRepository.getMessage(
              expectedParent.id,
            );
            final latestAttachments = await mediaAttachmentRepository
                .getAttachmentsForMessage(
                  expectedParent.id,
                  owner: MediaOwnerLane.group,
                );
            MediaAttachment? latestAttachment;
            for (final attachment in latestAttachments) {
              if (attachment.id == expectedAttachment.id) {
                latestAttachment = attachment;
                break;
              }
            }
            if (latestParent == null ||
                !sameExactGroupPrivateMediaDispatchParent(
                  latestParent,
                  expectedParent,
                ) ||
                latestAttachment == null ||
                !sameExactGroupRetryAttachment(
                  latestAttachment,
                  expectedAttachment,
                )) {
              return null;
            }
            if (projection != null) {
              final projected = await projection.projectUploadFailure(
                messageId: expectedParent.id,
                attachmentId: expectedAttachment.id,
                failure: failure,
              );
              if (!projected.applied) return null;
              return ForegroundGroupUploadLeafResult(
                outcome: failure,
                failureProjection: projected,
              );
            }
            final nextRetryCount = (latestAttachment.uploadRetryCount ?? 0) + 1;
            await mediaAttachmentRepository.saveAttachment(
              latestAttachment.copyWith(
                downloadStatus: nextRetryCount >= kMaxUploadRetries
                    ? 'upload_failed'
                    : 'upload_pending',
                uploadRetryCount: nextRetryCount,
                ownerLane: MediaOwnerLane.group,
              ),
              owner: MediaOwnerLane.group,
            );
            return ForegroundGroupUploadLeafResult(outcome: failure);
          }

          final outcome = await upload(allowedPeers);
          if (outcome case final UploadMediaFailed failure) {
            return projectOwnedFailure(failure);
          }

          final uploaded = (outcome as UploadMediaSucceeded).attachment;
          final completed = applyGroupUploadCompletionAuthority(
            expectedAttachment: expectedAttachment,
            completedAttachment: (await buildCompleted(
              uploaded,
            )).copyWith(ownerLane: MediaOwnerLane.group),
          );
          final completion =
              groupMessageRepository is GroupUploadRetryCompletionRepository
              ? groupMessageRepository as GroupUploadRetryCompletionRepository
              : null;
          var completionApplied = false;
          Object? completionError;
          try {
            if (completion != null) {
              completionApplied = await completion.completeUploadRetry(
                expectedParent: expectedParent,
                expectedAttachment: expectedAttachment,
                completedAttachment: completed,
              );
            } else {
              final latestParent = await groupMessageRepository.getMessage(
                expectedParent.id,
              );
              final latestAttachments = await mediaAttachmentRepository
                  .getAttachmentsForMessage(
                    expectedParent.id,
                    owner: MediaOwnerLane.group,
                  );
              MediaAttachment? latestAttachment;
              for (final attachment in latestAttachments) {
                if (attachment.id == expectedAttachment.id) {
                  latestAttachment = attachment;
                  break;
                }
              }
              if (latestParent == null ||
                  !sameExactGroupPrivateMediaDispatchParent(
                    latestParent,
                    expectedParent,
                  ) ||
                  latestAttachment == null ||
                  !sameExactGroupRetryAttachment(
                    latestAttachment,
                    expectedAttachment,
                  )) {
                return null;
              }
              await mediaAttachmentRepository.saveAttachment(
                completed,
                owner: MediaOwnerLane.group,
              );
              completionApplied = true;
            }
          } catch (error) {
            completionError = error;
          }
          if (!completionApplied) {
            emitFlowEvent(
              layer: 'FL',
              event: 'GROUP_CONV_FL_UPLOAD_COMPLETION_PERSISTENCE_FAILED',
              details: {
                'messageId': _shortId(expectedParent.id),
                'blobId': _shortId(expectedAttachment.id),
                if (completionError != null)
                  'errorType': completionError.runtimeType.toString(),
              },
            );
            return projectOwnedFailure(
              const UploadMediaFailed(
                stage: UploadMediaStage.consumerBoundary,
                disposition: UploadMediaDisposition.boundedRetryable,
                errorCode: 'GROUP_UPLOAD_COMPLETION_PERSISTENCE_FAILED',
              ),
            );
          }
          return ForegroundGroupUploadLeafResult(
            outcome: outcome,
            completedAttachment: completed,
          );
        },
      );
  return guarded.didRun ? guarded.value : null;
}

String _shortId(String value) =>
    value.length > 8 ? value.substring(0, 8) : value;
