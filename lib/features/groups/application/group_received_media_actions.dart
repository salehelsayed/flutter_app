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

/// Reloaded dispatch-time result shared by single-item and library batch
/// egress. A denial carries no path/hash/key material.
class GroupMediaCurrentRowDecision {
  const GroupMediaCurrentRowDecision.qualified(this.candidate)
    : refusalReason = null;

  const GroupMediaCurrentRowDecision.refused(this.refusalReason)
    : candidate = null;

  final ReceivedMediaEgressCandidate? candidate;
  final String? refusalReason;

  bool get isQualified => candidate != null;
}

Future<bool> _defaultCurrentGroupFileExists(String path) => File(path).exists();

/// Complete group-parent/attachment qualification used immediately before
/// every Save/Share dispatch. Presentation snapshots are never authority.
Future<GroupMediaCurrentRowDecision> qualifyCurrentGroupMediaRow({
  required String groupId,
  required String messageId,
  required String attachmentId,
  required GroupMessageRepository messageRepository,
  required MediaAttachmentRepository mediaAttachmentRepository,
  required MediaFileManager mediaFileManager,
  required GroupMediaEgressRestriction isEgressRestricted,
  Future<bool> Function(String resolvedPath) fileExists =
      _defaultCurrentGroupFileExists,
}) async {
  final parent = await messageRepository.getMessage(messageId);
  if (parent == null) {
    return const GroupMediaCurrentRowDecision.refused('parent_missing');
  }
  if (parent.groupId != groupId) {
    return const GroupMediaCurrentRowDecision.refused('wrong_group');
  }
  final tombstoneGroupId = await messageRepository.getLocalDeletionGroupId(
    messageId,
  );
  if (tombstoneGroupId == groupId) {
    // The durable local-deletion tombstone is visibility authority even if a
    // stale/replayed parent row survives beside it. Treat that parent exactly
    // like an absent row so neither single nor batch egress can export it.
    return const GroupMediaCurrentRowDecision.refused('parent_missing');
  }
  if (!parent.isIncoming) {
    return const GroupMediaCurrentRowDecision.refused('not_incoming');
  }

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
    return const GroupMediaCurrentRowDecision.refused(
      'attachment_not_group_owned',
    );
  }
  if (attachment.ownerLane != MediaOwnerLane.group) {
    return const GroupMediaCurrentRowDecision.refused(
      'attachment_not_group_owned',
    );
  }
  final mediaType = attachment.mediaType;
  if (mediaType != 'image' && mediaType != 'video') {
    return const GroupMediaCurrentRowDecision.refused('not_visual_media');
  }
  final normalizedMime = GroupMediaMimePolicy.normalizeMime(attachment.mime);
  if (normalizedMime == null ||
      GroupMediaMimePolicy.mediaTypeForMime(normalizedMime) != mediaType) {
    return const GroupMediaCurrentRowDecision.refused('mime_not_allowed');
  }
  if (!GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment)) {
    return const GroupMediaCurrentRowDecision.refused('not_displayable');
  }
  if (isEgressRestricted(attachment)) {
    return const GroupMediaCurrentRowDecision.refused('lifecycle_restricted');
  }
  final storedPath = await mediaFileManager.resolveStoredPath(
    attachment.localPath!,
  );
  if (!await fileExists(storedPath)) {
    return const GroupMediaCurrentRowDecision.refused('file_missing');
  }
  return GroupMediaCurrentRowDecision.qualified(
    ReceivedMediaEgressCandidate(
      attachmentId: attachment.id,
      storedPath: storedPath,
      mime: normalizedMime,
    ),
  );
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
    final decision = await qualifyCurrentGroupMediaRow(
      groupId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      messageRepository: messageRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      isEgressRestricted: isEgressRestricted,
    );
    if (!decision.isQualified) {
      return GroupReceivedMediaEgressAttempt.refused(decision.refusalReason!);
    }

    final result = await egressService.perform(
      requestId: requestIdFactory(),
      destination: destination,
      selection: [decision.candidate!],
    );
    return GroupReceivedMediaEgressAttempt.performed(result);
  }
}
