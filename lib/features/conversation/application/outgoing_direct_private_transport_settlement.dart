import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Settles transport-owned columns for one outgoing protected/view-once
/// message under the same attachment lifecycle lock as upload completion.
///
/// This is the sole shared post-network mutation boundary for private cached
/// envelope replay. A live attachment is settled under its exact lifecycle
/// lock. After terminal cleanup has removed that identity, the repository may
/// instead accept only the durable consumed-parent + zero-attachment shape in
/// its column-only transaction. A concurrent hide or physical parent removal
/// is returned as
/// [OutgoingDirectPrivateTransportSettlementOutcome.preservedUserIntent];
/// callers must treat that as final and must never fall through to a generic,
/// insertion-capable message save.
Future<OutgoingDirectPrivateTransportSettlementOutcome>
settleOutgoingDirectPrivateTransportUnderLifecycleLock({
  required MessageRepository messageRepository,
  required MediaAttachmentRepository? mediaAttachmentRepository,
  required List<MediaAttachment>? attachments,
  required String messageId,
  required String expectedEnvelope,
  required String status,
  required String? transport,
  required int? relayExpiresAt,
}) async {
  if ((attachments?.length ?? 0) > 1 ||
      messageRepository is! OutgoingDirectPrivateEnvelopeCustodyRepository ||
      mediaAttachmentRepository is! OutgoingDirectPrivateMutationRepository) {
    return OutgoingDirectPrivateTransportSettlementOutcome.refused;
  }
  final attachment = attachments != null && attachments.length == 1
      ? attachments.single
      : null;
  final attachmentId = attachment?.id;
  if (attachment != null &&
      (attachmentId == null ||
          attachmentId.isEmpty ||
          attachment.messageId != messageId)) {
    return OutgoingDirectPrivateTransportSettlementOutcome.refused;
  }

  final mutationRepository =
      mediaAttachmentRepository as OutgoingDirectPrivateMutationRepository;
  final envelopeRepository =
      messageRepository as OutgoingDirectPrivateEnvelopeCustodyRepository;
  if (attachmentId == null) {
    return envelopeRepository.settleOutgoingDirectPrivateTransport(
      messageId: messageId,
      attachmentId: null,
      expectedEnvelope: expectedEnvelope,
      status: status,
      transport: transport,
      relayExpiresAt: relayExpiresAt,
    );
  }
  return mutationRepository
      .outgoingDirectPrivateMutationCoordinator
      .lifecycleLock
      .synchronized(
        attachmentId,
        () => envelopeRepository.settleOutgoingDirectPrivateTransport(
          messageId: messageId,
          attachmentId: attachmentId,
          expectedEnvelope: expectedEnvelope,
          status: status,
          transport: transport,
          relayExpiresAt: relayExpiresAt,
        ),
      );
}
