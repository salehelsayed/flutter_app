import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

import 'announcement_private_reply_request.dart';

bool _isCanonicalLocalIdentifier(String value) {
  if (value.isEmpty || value.trim() != value) {
    return false;
  }
  return !value.runes.any((rune) => rune <= 0x20 || rune == 0x7f);
}

/// One externally safe unavailable value or the freshly qualified contact.
final class AnnouncementPrivateReplyResolution {
  const AnnouncementPrivateReplyResolution._available(this.contact)
    : assert(contact != null);

  const AnnouncementPrivateReplyResolution._unavailable() : contact = null;

  static const unavailable = AnnouncementPrivateReplyResolution._unavailable();

  final ContactModel? contact;

  bool get isAvailable => contact != null;
}

/// Pure qualification over current, fully hydrated repository rows.
final class AnnouncementPrivateReplyPolicy {
  const AnnouncementPrivateReplyPolicy();

  bool isEligible({
    required AnnouncementPrivateReplyRequest request,
    required bool hasCompleteOpener,
    required String currentPeerId,
    required GroupMessage? message,
    required GroupMessageLocalDeletionState deletionState,
    required GroupModel? group,
    required GroupMember? currentMember,
    required List<MediaAttachment> attachments,
    required ContactModel? contact,
  }) {
    if (!hasCompleteOpener ||
        !_isCanonicalLocalIdentifier(request.sourceMessageId) ||
        groupMemberPeerIdRejectReason(request.senderPeerId) != null ||
        groupMemberPeerIdRejectReason(currentPeerId) != null) {
      return false;
    }
    if (message == null ||
        message.id != request.sourceMessageId ||
        !_isCanonicalLocalIdentifier(message.id) ||
        message.id.startsWith('sys-') ||
        !_isCanonicalLocalIdentifier(message.groupId) ||
        groupMemberPeerIdRejectReason(message.senderPeerId) != null ||
        message.senderPeerId != request.senderPeerId ||
        !message.isIncoming ||
        message.senderPeerId == currentPeerId) {
      return false;
    }
    if (deletionState != GroupMessageLocalDeletionState.knownClear) {
      return false;
    }
    if (group == null ||
        group.id != message.groupId ||
        !_isCanonicalLocalIdentifier(group.id) ||
        group.type != GroupType.announcement ||
        group.isDissolved) {
      return false;
    }
    if (currentMember == null ||
        currentMember.groupId != message.groupId ||
        currentMember.peerId != currentPeerId) {
      return false;
    }
    final hasCurrentVisualRelationship = attachments.any(
      (attachment) =>
          attachment.messageId == message.id &&
          attachment.ownerLane == MediaOwnerLane.group &&
          (attachment.mediaType == 'image' || attachment.mediaType == 'video'),
    );
    if (!hasCurrentVisualRelationship) {
      return false;
    }
    return contact != null &&
        contact.peerId == request.senderPeerId &&
        !contact.isArchived &&
        !contact.isBlocked;
  }
}

/// Re-reads every local authority each time a route dispatch is considered.
final class AnnouncementPrivateReplyResolver {
  AnnouncementPrivateReplyResolver({
    required IdentityRepository identityRepository,
    required GroupMessageRepository groupMessageRepository,
    required GroupRepository groupRepository,
    required MediaAttachmentRepository mediaAttachmentRepository,
    required ContactRepository contactRepository,
    AnnouncementPrivateReplyPolicy policy =
        const AnnouncementPrivateReplyPolicy(),
  }) : _identityRepository = identityRepository,
       _groupMessageRepository = groupMessageRepository,
       _groupRepository = groupRepository,
       _mediaAttachmentRepository = mediaAttachmentRepository,
       _contactRepository = contactRepository,
       _policy = policy;

  final IdentityRepository _identityRepository;
  final GroupMessageRepository _groupMessageRepository;
  final GroupRepository _groupRepository;
  final MediaAttachmentRepository _mediaAttachmentRepository;
  final ContactRepository _contactRepository;
  final AnnouncementPrivateReplyPolicy _policy;

  Future<AnnouncementPrivateReplyResolution> resolve(
    AnnouncementPrivateReplyRequest request, {
    required bool hasCompleteOpener,
  }) async {
    if (!hasCompleteOpener ||
        !_isCanonicalLocalIdentifier(request.sourceMessageId) ||
        groupMemberPeerIdRejectReason(request.senderPeerId) != null) {
      return AnnouncementPrivateReplyResolution.unavailable;
    }

    try {
      final identity = await _identityRepository.loadIdentity();
      final currentPeerId = identity?.peerId ?? '';
      if (groupMemberPeerIdRejectReason(currentPeerId) != null) {
        return AnnouncementPrivateReplyResolution.unavailable;
      }

      final message = await _groupMessageRepository.getMessage(
        request.sourceMessageId,
      );
      if (message == null ||
          message.id != request.sourceMessageId ||
          !_isCanonicalLocalIdentifier(message.id) ||
          message.id.startsWith('sys-') ||
          !_isCanonicalLocalIdentifier(message.groupId) ||
          groupMemberPeerIdRejectReason(message.senderPeerId) != null ||
          message.senderPeerId != request.senderPeerId ||
          !message.isIncoming ||
          message.senderPeerId == currentPeerId) {
        return AnnouncementPrivateReplyResolution.unavailable;
      }

      final deletionRepository = _groupMessageRepository;
      final deletionState =
          deletionRepository is GroupMessageLocalDeletionAuthority
          ? await (deletionRepository as GroupMessageLocalDeletionAuthority)
                .getGroupMessageLocalDeletionState(request.sourceMessageId)
          : GroupMessageLocalDeletionState.unknown;
      final group = await _groupRepository.getGroup(message.groupId);
      final currentMember = await _groupRepository.getMember(
        message.groupId,
        currentPeerId,
      );
      final attachments = await _mediaAttachmentRepository
          .getAttachmentsForMessage(
            request.sourceMessageId,
            owner: MediaOwnerLane.group,
          );
      final contact = await _contactRepository.getContact(request.senderPeerId);

      if (!_policy.isEligible(
        request: request,
        hasCompleteOpener: hasCompleteOpener,
        currentPeerId: currentPeerId,
        message: message,
        deletionState: deletionState,
        group: group,
        currentMember: currentMember,
        attachments: attachments,
        contact: contact,
      )) {
        return AnnouncementPrivateReplyResolution.unavailable;
      }
      return AnnouncementPrivateReplyResolution._available(contact!);
    } catch (_) {
      return AnnouncementPrivateReplyResolution.unavailable;
    }
  }
}
