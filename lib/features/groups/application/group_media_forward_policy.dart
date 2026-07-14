import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/announcement_media_forward_request.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

/// 238 seam: lifecycle restriction (expiry / protection / view-once) on one
/// attachment row. Plan 236 has no lifecycle metadata to consult, so the
/// production default restricts nothing; plan 238 replaces it with the real
/// policy. Forward fails closed whenever this returns true.
typedef GroupMediaForwardRestriction =
    bool Function(MediaAttachment attachment);

bool _neverRestricted(MediaAttachment _) => false;

/// Pure Forward-offer and destination policy for received group media.
///
/// Fail-closed by construction, mirroring [GroupReceivedMediaActionPolicy]:
/// only an INCOMING image/video row under the exact `MediaOwnerLane.group`
/// lane, in a `GroupType.chat` group, that is displayable-verified RIGHT NOW
/// and not lifecycle-restricted, may offer Forward. The dispatch gate below
/// re-verifies everything and captures an isolated plaintext snapshot
/// immediately before any upload or delivery.
class GroupMediaForwardPolicy {
  const GroupMediaForwardPolicy._();

  static bool canOfferForward({
    required GroupType groupType,
    required bool isIncoming,
    required MediaAttachment attachment,
    GroupMediaForwardRestriction? isLifecycleRestricted,
    GroupPrivateMediaPolicy mediaPolicy =
        const GroupPrivateMediaPolicy.ordinary(),
  }) {
    if (groupType != GroupType.chat && groupType != GroupType.announcement) {
      return false;
    }
    if (!isIncoming) return false;
    if (mediaPolicy.requiresRedaction) return false;
    final mediaType = attachment.mediaType;
    if (mediaType != 'image' && mediaType != 'video') return false;
    if (attachment.ownerLane != MediaOwnerLane.group) return false;
    if (!GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment)) {
      return false;
    }
    if ((isLifecycleRestricted ?? _neverRestricted)(attachment)) return false;
    return true;
  }

  static bool canTargetContact(ContactModel contact) =>
      !contact.isArchived && !contact.isBlocked;

  static bool canTargetGroup(GroupModel group) {
    if (group.isArchived || group.isDissolved || group.type == GroupType.qa) {
      return false;
    }
    return group.type != GroupType.announcement ||
        group.myRole == GroupRole.admin;
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
    if (group.type != GroupType.chat && group.type != GroupType.announcement) {
      return null;
    }
    final parent = await messageRepository.getMessage(messageId);
    if (parent == null || parent.groupId != group.id || !parent.isIncoming) {
      return null;
    }
    if (parent.privateMediaPolicy.requiresRedaction) return null;
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
    // The attachment read above is an await boundary: the current parent can
    // drift after the first cheap fail-fast check. Reload it immediately
    // before policy, token, caption, or picker request materialization so
    // every launcher branch receives one post-await current-parent decision.
    final currentParent = await messageRepository.getMessage(messageId);
    if (currentParent == null ||
        currentParent.groupId != group.id ||
        !currentParent.isIncoming ||
        currentParent.privateMediaPolicy.requiresRedaction) {
      return null;
    }
    if (!GroupMediaForwardPolicy.canOfferForward(
      groupType: group.type,
      isIncoming: currentParent.isIncoming,
      attachment: attachment,
      isLifecycleRestricted: _isLifecycleRestricted,
      mediaPolicy: currentParent.privateMediaPolicy,
    )) {
      return null;
    }
    final provenance = groupMediaForwardProvenanceFor(
      entryPoint: GroupMediaSendEntryPoint.internalForward,
      accepted: true,
      operationTokenFactory: _operationTokenFactory,
    );
    if (provenance == null) return null;
    if (group.type == GroupType.announcement) {
      return AnnouncementMediaForwardRequest(
        groupId: group.id,
        messageId: messageId,
        attachmentId: attachmentId,
        initialCaption: currentParent.text,
        provenance: provenance,
      );
    }
    return GroupMediaForwardRequest(
      groupId: group.id,
      messageId: messageId,
      attachmentId: attachmentId,
      initialCaption: currentParent.text,
      provenance: provenance,
    );
  }
}

/// A private, per-dispatch plaintext copy captured while the attachment's
/// lifecycle lock is held. The coordinator consumes this path instead of
/// reopening the mutable canonical source after qualification.
class GroupMediaForwardImmutableSnapshot {
  GroupMediaForwardImmutableSnapshot._({
    required this.path,
    required MediaForwardSnapshotLease lease,
  }) : _lease = lease;

  final String path;
  final MediaForwardSnapshotLease _lease;

  Future<void> dispose() => _lease.dispose();
}

/// One verified forward source: the exact reloaded group-owned attachment,
/// its canonical current path, and (when requested by a delivery coordinator)
/// an isolated snapshot captured under the attachment lifecycle lock.
class GroupMediaForwardVerifiedSource {
  const GroupMediaForwardVerifiedSource({
    required this.resolvedPath,
    required this.attachment,
    this.immutableSnapshot,
  });

  final String resolvedPath;
  final MediaAttachment attachment;
  final GroupMediaForwardImmutableSnapshot? immutableSnapshot;
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
/// canonical plaintext through
/// [GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext] immediately
/// before any target lookup or upload. The relay content hash authenticates
/// ciphertext and is never compared to the canonical plaintext. Any failed
/// check yields a denial and zero source reads downstream.
String? _groupMediaForwardUnsafeRequestReason(
  GroupMediaForwardRequest request,
) {
  if (!DirectPrivateMediaPathGuard.isSafeSegment(request.groupId)) {
    return 'unsafe_owner_scope_id';
  }
  if (!DirectPrivateMediaPathGuard.isSafeSegment(request.attachmentId)) {
    return 'unsafe_attachment_id';
  }
  return null;
}

final class _GroupMediaForwardCanonicalQualification {
  const _GroupMediaForwardCanonicalQualification.verified({
    required this.attachment,
    required this.resolvedPath,
    required this.groupType,
  }) : denialReason = null;

  const _GroupMediaForwardCanonicalQualification.denied(
    String this.denialReason,
  ) : attachment = null,
      resolvedPath = null,
      groupType = null;

  final MediaAttachment? attachment;
  final String? resolvedPath;
  final GroupType? groupType;
  final String? denialReason;

  bool get isVerified => attachment != null && resolvedPath != null;
}

bool _sameGroupForwardAttachmentSecurityState(
  MediaAttachment qualified,
  MediaAttachment current,
) {
  return qualified.id == current.id &&
      qualified.messageId == current.messageId &&
      qualified.ownerLane == current.ownerLane &&
      qualified.localPath == current.localPath &&
      qualified.downloadStatus == current.downloadStatus &&
      qualified.size == current.size &&
      qualified.mediaType == current.mediaType &&
      qualified.mime == current.mime &&
      qualified.contentHash == current.contentHash &&
      qualified.thumbnailHash == current.thumbnailHash &&
      qualified.encryptionKeyBase64 == current.encryptionKeyBase64 &&
      qualified.encryptionNonce == current.encryptionNonce &&
      qualified.encryptionScheme == current.encryptionScheme;
}

/// One canonical source qualifier shared by preview and dispatch.
///
/// Callers must hold [lifecycleLock] for the request attachment. The helper
/// performs exact-ID row hydration, shared canonical local-plaintext
/// validation, and a stable exact-row comparison while same-ID mutations are
/// excluded. Current group/tombstone/parent/private/expiry/cleanup authority
/// is the final awaited decision. It never returns a path on denial.
final class _GroupMediaForwardCanonicalQualifier {
  const _GroupMediaForwardCanonicalQualifier({
    required this.groupRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.mediaFileManager,
    required this.isLifecycleRestricted,
  });

  final GroupRepository groupRepository;
  final GroupMessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;
  final GroupMediaForwardRestriction isLifecycleRestricted;

  Future<_GroupMediaForwardCanonicalQualification> qualifyWithinLock({
    required GroupMediaForwardRequest request,
    GroupType? expectedGroupType,
  }) async {
    final initial = await recheckCurrentAuthority(
      request,
      expectedGroupType: expectedGroupType,
    );
    if (initial.denialReason != null) {
      return _GroupMediaForwardCanonicalQualification.denied(
        initial.denialReason!,
      );
    }

    final initialAttachment = await recheckCurrentAttachmentState(request);
    final attachment = initialAttachment.attachment;
    if (attachment == null) {
      return _GroupMediaForwardCanonicalQualification.denied(
        initialAttachment.denialReason ?? 'attachment_not_group_owned',
      );
    }

    final current = await recheckCurrentAuthority(
      request,
      attachment: attachment,
      expectedGroupType: expectedGroupType,
    );
    final currentParent = current.parent;
    final currentGroup = current.group;
    if (current.denialReason != null ||
        currentParent == null ||
        currentGroup == null) {
      return _GroupMediaForwardCanonicalQualification.denied(
        current.denialReason ?? 'parent_missing',
      );
    }

    final mediaType = attachment.mediaType;
    if (mediaType != 'image' && mediaType != 'video') {
      return const _GroupMediaForwardCanonicalQualification.denied(
        'not_visual_media',
      );
    }
    final normalizedMime = GroupMediaMimePolicy.normalizeMime(attachment.mime);
    if (normalizedMime == null ||
        GroupMediaMimePolicy.mediaTypeForMime(normalizedMime) != mediaType) {
      return const _GroupMediaForwardCanonicalQualification.denied(
        'mime_not_allowed',
      );
    }
    if (!GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment)) {
      return const _GroupMediaForwardCanonicalQualification.denied(
        'not_displayable',
      );
    }
    if (!GroupMediaForwardPolicy.canOfferForward(
      groupType: currentGroup.type,
      isIncoming: currentParent.isIncoming,
      attachment: attachment,
      isLifecycleRestricted: (_) => false,
      mediaPolicy: currentParent.privateMediaPolicy,
    )) {
      return const _GroupMediaForwardCanonicalQualification.denied(
        'not_forwardable',
      );
    }

    final localValidation =
        await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
          attachment: attachment,
          ownerScopeId: request.groupId,
          mediaFileManager: mediaFileManager,
        );
    final resolvedPath = localValidation.resolvedPath;
    if (!localValidation.isValid || resolvedPath == null) {
      return _GroupMediaForwardCanonicalQualification.denied(
        localValidation.reason ?? 'invalid_canonical_plaintext',
      );
    }

    // Row mutations acquire the same attachment lifecycle lock held by the
    // caller. Reload only this exact ID after every canonical file await and
    // compare the full security state before consulting final parent authority.
    final stableAttachment = await recheckCurrentAttachmentState(
      request,
      qualifiedAttachment: attachment,
    );
    final currentAttachment = stableAttachment.attachment;
    if (stableAttachment.denialReason != null || currentAttachment == null) {
      return _GroupMediaForwardCanonicalQualification.denied(
        stableAttachment.denialReason ?? 'attachment_changed',
      );
    }

    // This is deliberately the final await on the verified path. Group,
    // tombstone, parent, private, expiry, and cleanup state are all decided
    // after the exact-row await, then the path returns without another yield.
    final finalAuthority = await recheckCurrentAuthority(
      request,
      attachment: currentAttachment,
      expectedGroupType: currentGroup.type,
    );
    final finalGroup = finalAuthority.group;
    if (finalAuthority.denialReason != null || finalGroup == null) {
      return _GroupMediaForwardCanonicalQualification.denied(
        finalAuthority.denialReason ?? 'source_group_missing',
      );
    }
    return _GroupMediaForwardCanonicalQualification.verified(
      attachment: currentAttachment,
      resolvedPath: resolvedPath,
      groupType: finalGroup.type,
    );
  }

  Future<({MediaAttachment? attachment, String? denialReason})>
  recheckCurrentAttachmentState(
    GroupMediaForwardRequest request, {
    MediaAttachment? qualifiedAttachment,
  }) async {
    final repository = mediaAttachmentRepository;
    if (repository is! MediaAttachmentByIdLookup) {
      return (
        attachment: null,
        denialReason: 'attachment_exact_lookup_unavailable',
      );
    }
    final exactLookup = repository as MediaAttachmentByIdLookup;
    final MediaAttachment? current;
    try {
      current = await exactLookup.getAttachmentById(request.attachmentId);
    } catch (_) {
      return (attachment: null, denialReason: 'attachment_recheck_failed');
    }
    if (current == null ||
        current.id != request.attachmentId ||
        current.messageId != request.messageId ||
        current.ownerLane != MediaOwnerLane.group) {
      return (
        attachment: null,
        denialReason: qualifiedAttachment == null
            ? 'attachment_not_group_owned'
            : 'attachment_changed',
      );
    }
    if (qualifiedAttachment != null &&
        !_sameGroupForwardAttachmentSecurityState(
          qualifiedAttachment,
          current,
        )) {
      return (attachment: null, denialReason: 'attachment_changed');
    }
    return (attachment: current, denialReason: null);
  }

  Future<({GroupModel? group, GroupMessage? parent, String? denialReason})>
  recheckCurrentAuthority(
    GroupMediaForwardRequest request, {
    MediaAttachment? attachment,
    GroupType? expectedGroupType,
  }) async {
    GroupModel? group;
    String? groupDenialReason;
    try {
      group = await groupRepository.getGroup(request.groupId);
    } catch (_) {
      groupDenialReason = 'source_group_recheck_failed';
    }
    if (groupDenialReason == null) {
      if (group == null) {
        groupDenialReason = 'source_group_missing';
      } else if (group.type != GroupType.chat &&
          group.type != GroupType.announcement) {
        groupDenialReason = 'source_group_not_forwardable';
      } else if (expectedGroupType != null && group.type != expectedGroupType) {
        groupDenialReason = 'source_group_changed';
      }
    }

    final deletionAuthority =
        messageRepository is GroupMessageLocalDeletionAuthority
        ? messageRepository as GroupMessageLocalDeletionAuthority
        : null;
    if (deletionAuthority == null) {
      return (
        group: null,
        parent: null,
        denialReason: 'parent_deletion_state_unknown',
      );
    }
    final GroupMessageLocalDeletionState deletionState;
    try {
      deletionState = await deletionAuthority.getGroupMessageLocalDeletionState(
        request.messageId,
      );
    } catch (_) {
      return (group: null, parent: null, denialReason: 'parent_recheck_failed');
    }
    if (deletionState == GroupMessageLocalDeletionState.deleted) {
      return (group: null, parent: null, denialReason: 'parent_missing');
    }
    if (deletionState != GroupMessageLocalDeletionState.knownClear) {
      return (
        group: null,
        parent: null,
        denialReason: 'parent_deletion_state_unknown',
      );
    }

    // Load the parent only after the awaited deletion authority so a private,
    // expired, cleanup-pending, or removed row that changed during that await
    // can never be accepted from a stale pre-await object.
    final GroupMessage? parent;
    try {
      parent = await messageRepository.getMessage(request.messageId);
    } catch (_) {
      return (group: null, parent: null, denialReason: 'parent_recheck_failed');
    }
    if (parent == null) {
      return (group: null, parent: null, denialReason: 'parent_missing');
    }

    final parentDenial = _parentDenialReason(parent, request);
    if (parentDenial != null) {
      return (group: null, parent: null, denialReason: parentDenial);
    }
    if (attachment != null) {
      bool restricted;
      try {
        restricted = isLifecycleRestricted(attachment);
      } catch (_) {
        restricted = true;
      }
      if (restricted) {
        return (
          group: null,
          parent: null,
          denialReason: 'lifecycle_restricted',
        );
      }
    }
    if (groupDenialReason != null) {
      return (group: null, parent: null, denialReason: groupDenialReason);
    }
    return (group: group!, parent: parent, denialReason: null);
  }

  String? _parentDenialReason(
    GroupMessage parent,
    GroupMediaForwardRequest request,
  ) {
    if (parent.groupId != request.groupId) return 'wrong_group';
    if (!parent.isIncoming) return 'not_incoming';
    if (parent.privateMediaPolicy.requiresRedaction ||
        parent.mediaExpiredAt != null ||
        parent.mediaCleanupPending) {
      return 'lifecycle_restricted';
    }
    return null;
  }
}

/// Presentation-only preview qualification. It performs an early parent
/// recheck before path work and makes current parent authority the final await
/// after the stable exact-row comparison, so picker handoff drift cannot expose
/// private bytes merely because an earlier request was ordinary.
class GroupMediaForwardPreviewResult {
  const GroupMediaForwardPreviewResult.verified(String this.resolvedPath)
    : denialReason = null;

  const GroupMediaForwardPreviewResult.denied(String this.denialReason)
    : resolvedPath = null;

  final String? resolvedPath;
  final String? denialReason;

  bool get isVerified => resolvedPath != null;
}

class GroupMediaForwardPreviewGate {
  GroupMediaForwardPreviewGate({
    required this.groupRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    MediaFileManager? mediaFileManager,
    MediaAttachmentLifecycleLock? lifecycleLock,
    GroupMediaForwardRestriction? isLifecycleRestricted,
  }) : mediaFileManager = mediaFileManager ?? MediaFileManager(),
       lifecycleLock = lifecycleLock ?? mediaAttachmentLifecycleLock,
       isLifecycleRestricted = isLifecycleRestricted ?? _neverRestricted,
       super();

  final GroupRepository groupRepository;
  final GroupMessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;
  final MediaAttachmentLifecycleLock lifecycleLock;
  final GroupMediaForwardRestriction isLifecycleRestricted;

  Future<GroupMediaForwardPreviewResult> verify({
    required GroupType groupType,
    required GroupMediaForwardRequest request,
  }) {
    final unsafeReason = _groupMediaForwardUnsafeRequestReason(request);
    if (unsafeReason != null) {
      return Future.value(GroupMediaForwardPreviewResult.denied(unsafeReason));
    }
    final qualifier = _GroupMediaForwardCanonicalQualifier(
      groupRepository: groupRepository,
      messageRepository: messageRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      isLifecycleRestricted: isLifecycleRestricted,
    );
    return lifecycleLock.synchronized(request.attachmentId, () async {
      final qualification = await qualifier.qualifyWithinLock(
        request: request,
        expectedGroupType: groupType,
      );
      final resolvedPath = qualification.resolvedPath;
      if (!qualification.isVerified || resolvedPath == null) {
        return GroupMediaForwardPreviewResult.denied(
          qualification.denialReason ?? 'invalid_canonical_plaintext',
        );
      }
      return GroupMediaForwardPreviewResult.verified(resolvedPath);
    });
  }
}

final class GroupMediaForwardSourceGate {
  GroupMediaForwardSourceGate({
    required this.groupRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    MediaFileManager? mediaFileManager,
    MediaAttachmentLifecycleLock? lifecycleLock,
    GroupMediaForwardRestriction? isLifecycleRestricted,
  }) : mediaFileManager = mediaFileManager ?? MediaFileManager(),
       lifecycleLock = lifecycleLock ?? mediaAttachmentLifecycleLock,
       isLifecycleRestricted = isLifecycleRestricted ?? _neverRestricted;

  final GroupRepository groupRepository;
  final GroupMessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final MediaFileManager mediaFileManager;
  final MediaAttachmentLifecycleLock lifecycleLock;
  final GroupMediaForwardRestriction isLifecycleRestricted;

  Future<GroupMediaForwardSourceResult> verify(
    GroupMediaForwardRequest request, {
    bool captureImmutableSnapshot = false,
  }) {
    final unsafeReason = _groupMediaForwardUnsafeRequestReason(request);
    if (unsafeReason != null) {
      return Future.value(GroupMediaForwardSourceResult.denied(unsafeReason));
    }
    return lifecycleLock.synchronized(
      request.attachmentId,
      () => _verifyWithinLock(
        request,
        captureImmutableSnapshot: captureImmutableSnapshot,
      ),
    );
  }

  Future<GroupMediaForwardSourceResult> _verifyWithinLock(
    GroupMediaForwardRequest request, {
    required bool captureImmutableSnapshot,
  }) async {
    final qualifier = _GroupMediaForwardCanonicalQualifier(
      groupRepository: groupRepository,
      messageRepository: messageRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      mediaFileManager: mediaFileManager,
      isLifecycleRestricted: isLifecycleRestricted,
    );
    final qualification = await qualifier.qualifyWithinLock(request: request);
    final attachment = qualification.attachment;
    final storedPath = qualification.resolvedPath;
    if (!qualification.isVerified || attachment == null || storedPath == null) {
      return GroupMediaForwardSourceResult.denied(
        qualification.denialReason ?? 'invalid_canonical_plaintext',
      );
    }

    if (!captureImmutableSnapshot) {
      return GroupMediaForwardSourceResult.verified(
        GroupMediaForwardVerifiedSource(
          resolvedPath: storedPath,
          attachment: attachment,
        ),
      );
    }

    final capture = await _captureImmutableSnapshot(
      sourcePath: storedPath,
      attachment: attachment,
    );
    final snapshot = capture.snapshot;
    if (snapshot == null) {
      return GroupMediaForwardSourceResult.denied(
        capture.reason ?? 'snapshot_capture_failed',
      );
    }

    // Snapshot creation is another awaited file operation. Reload only this
    // attachment ID and compare its complete security state while the same-ID
    // lifecycle lock still excludes every production row mutation.
    final stableAttachment = await qualifier.recheckCurrentAttachmentState(
      request,
      qualifiedAttachment: attachment,
    );
    final currentAttachment = stableAttachment.attachment;
    if (stableAttachment.denialReason != null || currentAttachment == null) {
      await snapshot.dispose();
      return GroupMediaForwardSourceResult.denied(
        stableAttachment.denialReason ?? 'attachment_changed',
      );
    }

    // This is the true final await on the successful snapshot path. Current
    // group, tombstone, parent, private, expiry, and cleanup state are decided
    // after the post-copy row await; a stable decision returns without yielding.
    final finalAuthority = await qualifier.recheckCurrentAuthority(
      request,
      attachment: currentAttachment,
      expectedGroupType: qualification.groupType,
    );
    if (finalAuthority.denialReason != null) {
      await snapshot.dispose();
      return GroupMediaForwardSourceResult.denied(finalAuthority.denialReason!);
    }

    return GroupMediaForwardSourceResult.verified(
      GroupMediaForwardVerifiedSource(
        resolvedPath: storedPath,
        attachment: currentAttachment,
        immutableSnapshot: snapshot,
      ),
    );
  }

  Future<({GroupMediaForwardImmutableSnapshot? snapshot, String? reason})>
  _captureImmutableSnapshot({
    required String sourcePath,
    required MediaAttachment attachment,
  }) async {
    MediaForwardSnapshotLease? lease;
    try {
      lease = await mediaFileManager.createMediaForwardSnapshotLease();
      final directory = lease.directory;
      final extension = MediaFilePathConvention.extensionFromMime(
        attachment.mime,
      );
      final snapshotFile = File(p.join(directory.path, 'source$extension'));
      await File(sourcePath).copy(snapshotFile.path);
      final type = await FileSystemEntity.type(
        snapshotFile.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.file) {
        await lease.dispose();
        return (snapshot: null, reason: 'snapshot_not_regular_file');
      }
      if (await snapshotFile.length() != attachment.size) {
        await lease.dispose();
        return (snapshot: null, reason: 'snapshot_size_mismatch');
      }
      final signature = await GroupMediaMimePolicy.validateFile(
        path: snapshotFile.path,
        mime: attachment.mime,
        mediaType: attachment.mediaType,
      );
      if (!signature.isValid) {
        await lease.dispose();
        return (
          snapshot: null,
          reason: 'snapshot_${signature.reason ?? 'invalid_signature'}',
        );
      }
      return (
        snapshot: GroupMediaForwardImmutableSnapshot._(
          path: snapshotFile.path,
          lease: lease,
        ),
        reason: null,
      );
    } catch (_) {
      if (lease != null) {
        await lease.dispose();
      }
      return (snapshot: null, reason: 'snapshot_capture_failed');
    }
  }
}
