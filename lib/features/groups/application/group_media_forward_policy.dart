import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// 238 seam: lifecycle restriction (expiry / protection / view-once) on one
/// attachment row. Plan 236 has no lifecycle metadata to consult, so the
/// production default restricts nothing; plan 238 replaces it with the real
/// policy. Forward fails closed whenever this returns true.
typedef GroupMediaForwardRestriction = bool Function(MediaAttachment attachment);

bool _neverRestricted(MediaAttachment _) => false;

/// 236: pure Forward-offer policy for received media in discussion groups.
///
/// Fail-closed by construction, mirroring [GroupReceivedMediaActionPolicy]:
/// only an INCOMING image/video row under the exact `MediaOwnerLane.group`
/// lane, in a `GroupType.chat` group, that is displayable-verified RIGHT NOW
/// and not lifecycle-restricted, may offer Forward. The dispatch gate below
/// re-verifies everything again — including the current file hash —
/// immediately before any upload or delivery.
class GroupMediaForwardPolicy {
  const GroupMediaForwardPolicy._();

  static bool canOfferForward({
    required GroupType groupType,
    required bool isIncoming,
    required MediaAttachment attachment,
    GroupMediaForwardRestriction? isLifecycleRestricted,
  }) {
    if (groupType != GroupType.chat) return false;
    if (!isIncoming) return false;
    final mediaType = attachment.mediaType;
    if (mediaType != 'image' && mediaType != 'video') return false;
    if (attachment.ownerLane != MediaOwnerLane.group) return false;
    if (!GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment)) {
      return false;
    }
    if ((isLifecycleRestricted ?? _neverRestricted)(attachment)) return false;
    return true;
  }
}

const _forwardTokenUuid = Uuid();

String _defaultForwardOperationToken() => _forwardTokenUuid.v4();

/// 236: builds one ACCEPTED forward request from freshly loaded rows.
///
/// Returns null (and the UI offers/launches nothing) unless the reloaded
/// parent is an incoming message of this discussion group and the reloaded
/// group-owned attachment passes [GroupMediaForwardPolicy.canOfferForward]
/// RIGHT NOW. The request seeds the picker caption from the parent's current
/// text and carries only the stable `(groupId, messageId, attachmentId)`
/// identity — the viewer-SELECTED attachment, never the whole album.
class GroupMediaForwardRequestBuilder {
  GroupMediaForwardRequestBuilder({
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    String Function() operationTokenFactory = _defaultForwardOperationToken,
    GroupMediaForwardRestriction? isLifecycleRestricted,
  }) : _operationTokenFactory = operationTokenFactory,
       _isLifecycleRestricted = isLifecycleRestricted ?? _neverRestricted;

  final GroupMessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final String Function() _operationTokenFactory;
  final GroupMediaForwardRestriction _isLifecycleRestricted;

  Future<GroupMediaForwardRequest?> build({
    required GroupModel group,
    required String messageId,
    required String attachmentId,
  }) async {
    if (group.type != GroupType.chat) return null;
    final parent = await messageRepository.getMessage(messageId);
    if (parent == null || parent.groupId != group.id || !parent.isIncoming) {
      return null;
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
    if (attachment == null) return null;
    if (!GroupMediaForwardPolicy.canOfferForward(
      groupType: group.type,
      isIncoming: parent.isIncoming,
      attachment: attachment,
      isLifecycleRestricted: _isLifecycleRestricted,
    )) {
      return null;
    }
    final provenance = groupMediaForwardProvenanceFor(
      entryPoint: GroupMediaSendEntryPoint.internalForward,
      accepted: true,
      operationTokenFactory: _operationTokenFactory,
    );
    if (provenance == null) return null;
    return GroupMediaForwardRequest(
      groupId: group.id,
      messageId: messageId,
      attachmentId: attachmentId,
      initialCaption: parent.text,
      provenance: provenance,
    );
  }
}

/// One verified forward source: the exact reloaded group-owned attachment and
/// the resolved CURRENT stored file whose SHA-256 matched the stored content
/// hash at dispatch time.
class GroupMediaForwardVerifiedSource {
  const GroupMediaForwardVerifiedSource({
    required this.resolvedPath,
    required this.attachment,
  });

  final String resolvedPath;
  final MediaAttachment attachment;
}

/// Outcome of one dispatch-time source verification: either a verified
/// source, or a privacy-safe stable denial reason (no path, hash, key, or
/// peer material) with ZERO side effects.
class GroupMediaForwardSourceResult {
  const GroupMediaForwardSourceResult.verified(
    GroupMediaForwardVerifiedSource this.source,
  ) : denialReason = null;

  const GroupMediaForwardSourceResult.denied(String this.denialReason)
    : source = null;

  final GroupMediaForwardVerifiedSource? source;
  final String? denialReason;

  bool get isVerified => source != null;
}

/// 236: dispatch-time source gate between one accepted forward request and
/// the batch delivery fanout. Never trusts viewer/picker state: it reloads
/// the exact `(group, message, attachment)` identity under the group owner
/// lane, requalifies type/lane/integrity/lifecycle eligibility, resolves the
/// canonical file, and requires [GroupMediaIntegrityPolicy.validateFileContentHash]
/// success against the CURRENT bytes immediately before any target lookup or
/// upload. Any failed check yields a denial and zero source reads downstream.
typedef GroupMediaForwardContentHashValidator =
    Future<GroupMediaValidationResult> Function({
      required String path,
      required String? expectedHash,
    });

Future<bool> _defaultForwardFileExists(String path) => File(path).exists();

class GroupMediaForwardSourceGate {
  GroupMediaForwardSourceGate({
    required this.groupRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    MediaFileManager? mediaFileManager,
    GroupMediaForwardRestriction? isLifecycleRestricted,
    Future<bool> Function(String resolvedPath)? fileExists,
    GroupMediaForwardContentHashValidator? validateContentHash,
  }) : mediaFileManager = mediaFileManager ?? MediaFileManager(),
       isLifecycleRestricted = isLifecycleRestricted ?? _neverRestricted,
       fileExists = fileExists ?? _defaultForwardFileExists,
       validateContentHash =
           validateContentHash ??
           GroupMediaIntegrityPolicy.validateFileContentHash;

  final GroupRepository groupRepository;
  final GroupMessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;
  final GroupMediaForwardRestriction isLifecycleRestricted;

  /// Test seams only: widget tests replace the real (stream-based) file
  /// probe/hash with synchronous equivalents because real dart:io streams
  /// never complete inside the fake-async test zone. GMF-01R pins the real
  /// defaults.
  final Future<bool> Function(String resolvedPath) fileExists;
  final GroupMediaForwardContentHashValidator validateContentHash;

  Future<GroupMediaForwardSourceResult> verify(
    GroupMediaForwardRequest request,
  ) async {
    // Exact parent: the untyped by-ID load is verified against the caller's
    // group and direction. A same-ID direct message cannot satisfy this
    // because group parents live in their own table.
    final parent = await messageRepository.getMessage(request.messageId);
    if (parent == null) {
      return const GroupMediaForwardSourceResult.denied('parent_missing');
    }
    if (parent.groupId != request.groupId) {
      return const GroupMediaForwardSourceResult.denied('wrong_group');
    }
    if (!parent.isIncoming) {
      return const GroupMediaForwardSourceResult.denied('not_incoming');
    }

    // Source-lane authority: only a discussion group can be forwarded FROM.
    final sourceGroup = await groupRepository.getGroup(request.groupId);
    if (sourceGroup == null) {
      return const GroupMediaForwardSourceResult.denied(
        'source_group_missing',
      );
    }
    if (sourceGroup.type != GroupType.chat) {
      return const GroupMediaForwardSourceResult.denied(
        'source_group_not_discussion',
      );
    }

    // Exact group-owned attachment: the owner-scoped load excludes direct
    // same-ID collisions and unresolved legacy rows by construction.
    final rows = await mediaAttachmentRepository.getAttachmentsForMessage(
      request.messageId,
      owner: MediaOwnerLane.group,
    );
    MediaAttachment? attachment;
    for (final row in rows) {
      if (row.id == request.attachmentId) {
        attachment = row;
        break;
      }
    }
    if (attachment == null) {
      return const GroupMediaForwardSourceResult.denied(
        'attachment_not_group_owned',
      );
    }

    // Requalify current state — never viewer/bubble metadata.
    final mediaType = attachment.mediaType;
    if (mediaType != 'image' && mediaType != 'video') {
      return const GroupMediaForwardSourceResult.denied('not_visual_media');
    }
    final normalizedMime = GroupMediaMimePolicy.normalizeMime(attachment.mime);
    if (normalizedMime == null ||
        GroupMediaMimePolicy.mediaTypeForMime(normalizedMime) != mediaType) {
      return const GroupMediaForwardSourceResult.denied('mime_not_allowed');
    }
    if (!GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment)) {
      return const GroupMediaForwardSourceResult.denied('not_displayable');
    }
    if (isLifecycleRestricted(attachment)) {
      return const GroupMediaForwardSourceResult.denied(
        'lifecycle_restricted',
      );
    }

    final storedPath = await mediaFileManager.resolveStoredPath(
      attachment.localPath!,
    );
    if (!await fileExists(storedPath)) {
      return const GroupMediaForwardSourceResult.denied('missing_file');
    }

    // The decisive dispatch check: hash the CURRENT bytes. Metadata plus
    // existence is insufficient because bytes can change after the viewer
    // first qualified them.
    final hashValidation = await validateContentHash(
      path: storedPath,
      expectedHash: attachment.contentHash,
    );
    if (!hashValidation.isValid) {
      return GroupMediaForwardSourceResult.denied(
        hashValidation.reason ?? 'content_hash_mismatch',
      );
    }

    return GroupMediaForwardSourceResult.verified(
      GroupMediaForwardVerifiedSource(
        resolvedPath: storedPath,
        attachment: attachment,
      ),
    );
  }
}
