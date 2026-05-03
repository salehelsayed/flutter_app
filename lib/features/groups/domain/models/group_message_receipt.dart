const groupMessageReceiptTypeDelivered = 'delivered';
const groupMessageReceiptTypeRead = 'read';

class GroupMessageReceipt {
  final String groupId;
  final String messageId;
  final String receiptType;
  final String memberPeerId;
  final String? senderDeviceId;
  final DateTime receiptAt;
  final String? sourceEventId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupMessageReceipt({
    required this.groupId,
    required this.messageId,
    required this.receiptType,
    required this.memberPeerId,
    this.senderDeviceId,
    required this.receiptAt,
    this.sourceEventId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupMessageReceipt.fromMap(Map<String, Object?> map) {
    return GroupMessageReceipt(
      groupId: map['group_id'] as String,
      messageId: map['message_id'] as String,
      receiptType: map['receipt_type'] as String,
      memberPeerId: map['member_peer_id'] as String,
      senderDeviceId: map['sender_device_id'] as String?,
      receiptAt: DateTime.parse(map['receipt_at'] as String).toUtc(),
      sourceEventId: map['source_event_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'group_id': groupId,
      'message_id': messageId,
      'receipt_type': receiptType,
      'member_peer_id': memberPeerId,
      'sender_device_id': senderDeviceId,
      'receipt_at': receiptAt.toUtc().toIso8601String(),
      'source_event_id': sourceEventId,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }
}
