import 'dart:io';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';

/// 238 seam: lifecycle restriction (expiry / protection / view-once) on one
/// reloaded attachment row. Plan 235 has no lifecycle metadata to consult, so
/// the production default restricts nothing; plan 238 replaces it with the
/// real policy. Egress fails closed whenever this returns true.
typedef GroupMediaEgressRestriction = bool Function(MediaAttachment attachment);

/// Outcome of one Save/Share attempt: either the typed egress service result,
/// or a refusal that made ZERO egress calls. Refusal reasons are privacy-safe
/// stable identifiers (no path, hash, key, or peer material).
class GroupReceivedMediaEgressAttempt {
  const GroupReceivedMediaEgressAttempt.performed(MediaEgressResult this.result)
    : refusalReason = null;

  const GroupReceivedMediaEgressAttempt.refused(String this.refusalReason)
    : result = null;

  final MediaEgressResult? result;
  final String? refusalReason;

  bool get performed => result != null;
}

/// 235: qualification adapter between group UI actions and
/// [ReceivedMediaEgressService]. Never trusts viewer/bubble state: it reloads
/// the exact `(group, message, attachment)` identity under the group owner
/// lane and requalifies completion/integrity/expiry/protection/path
/// eligibility immediately before every egress call. Any failed check makes
/// zero egress calls. The UI must never call the native egress gateway, a
/// sender, a share picker, or a batch-delivery seam directly.
class GroupReceivedMediaActionsController {
  GroupReceivedMediaActionsController({
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.egressService,
    MediaFileManager? mediaFileManager,
    GroupMediaEgressRestriction? isEgressRestricted,
    String Function()? requestIdFactory,
  }) : mediaFileManager = mediaFileManager ?? MediaFileManager(),
       isEgressRestricted = isEgressRestricted ?? _neverRestricted,
       requestIdFactory = requestIdFactory ?? _defaultRequestId;

  final GroupMessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final ReceivedMediaEgressService egressService;
  final MediaFileManager mediaFileManager;
  final GroupMediaEgressRestriction isEgressRestricted;
  final String Function() requestIdFactory;

  static bool _neverRestricted(MediaAttachment _) => false;

  static int _requestCounter = 0;

  static String _defaultRequestId() {
    _requestCounter = (_requestCounter + 1) % 1000000;
    return 'gma-${DateTime.now().microsecondsSinceEpoch}-$_requestCounter';
  }

  Future<GroupReceivedMediaEgressAttempt> save({
    required String groupId,
    required String messageId,
    required String attachmentId,
  }) => _perform(
    destination: MediaEgressDestination.photos,
    groupId: groupId,
    messageId: messageId,
    attachmentId: attachmentId,
  );

  Future<GroupReceivedMediaEgressAttempt> share({
    required String groupId,
    required String messageId,
    required String attachmentId,
  }) => _perform(
    destination: MediaEgressDestination.share,
    groupId: groupId,
    messageId: messageId,
    attachmentId: attachmentId,
  );

  Future<GroupReceivedMediaEgressAttempt> _perform({
    required MediaEgressDestination destination,
    required String groupId,
    required String messageId,
    required String attachmentId,
  }) async {
    // Exact parent: the untyped by-ID load is verified against the caller's
    // group and direction. A same-ID direct message cannot satisfy this
    // because group parents live in their own table.
    final parent = await messageRepository.getMessage(messageId);
    if (parent == null) {
      return const GroupReceivedMediaEgressAttempt.refused('parent_missing');
    }
    if (parent.groupId != groupId) {
      return const GroupReceivedMediaEgressAttempt.refused('wrong_group');
    }
    if (!parent.isIncoming) {
      return const GroupReceivedMediaEgressAttempt.refused('not_incoming');
    }

    // Exact group-owned attachment: the owner-scoped load excludes direct
    // same-ID collisions and unresolved legacy rows by construction.
    final rows = await mediaAttachmentRepository.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    MediaAttachment? attachment;
    for (final row in rows) {
      if (row.id == attachmentId) {
        attachment = row;
        break;
      }
    }
    if (attachment == null) {
      return const GroupReceivedMediaEgressAttempt.refused(
        'attachment_not_group_owned',
      );
    }

    // Requalify current state — never viewer/bubble metadata.
    final mediaType = attachment.mediaType;
    if (mediaType != 'image' && mediaType != 'video') {
      return const GroupReceivedMediaEgressAttempt.refused('not_visual_media');
    }
    final normalizedMime = GroupMediaMimePolicy.normalizeMime(attachment.mime);
    if (normalizedMime == null ||
        GroupMediaMimePolicy.mediaTypeForMime(normalizedMime) != mediaType) {
      return const GroupReceivedMediaEgressAttempt.refused('mime_not_allowed');
    }
    if (!GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment)) {
      return const GroupReceivedMediaEgressAttempt.refused('not_displayable');
    }
    if (isEgressRestricted(attachment)) {
      return const GroupReceivedMediaEgressAttempt.refused(
        'lifecycle_restricted',
      );
    }

    final storedPath = await mediaFileManager.resolveStoredPath(
      attachment.localPath!,
    );
    if (!await File(storedPath).exists()) {
      return const GroupReceivedMediaEgressAttempt.refused('file_missing');
    }

    final result = await egressService.perform(
      requestId: requestIdFactory(),
      destination: destination,
      selection: [
        ReceivedMediaEgressCandidate(
          attachmentId: attachment.id,
          storedPath: storedPath,
          mime: normalizedMime,
        ),
      ],
    );
    return GroupReceivedMediaEgressAttempt.performed(result);
  }
}
