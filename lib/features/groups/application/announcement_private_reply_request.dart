/// Minimum local-only provenance needed to qualify an announcement-media
/// private reply. It deliberately has no serialized or durable form.
final class AnnouncementPrivateReplyRequest {
  const AnnouncementPrivateReplyRequest({
    required this.sourceMessageId,
    required this.senderPeerId,
  });

  final String sourceMessageId;
  final String senderPeerId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AnnouncementPrivateReplyRequest &&
            other.sourceMessageId == sourceMessageId &&
            other.senderPeerId == senderPeerId;
  }

  @override
  int get hashCode => Object.hash(sourceMessageId, senderPeerId);
}
