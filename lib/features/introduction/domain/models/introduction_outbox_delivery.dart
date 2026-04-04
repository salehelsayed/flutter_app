class IntroductionOutboxDeliveryStatus {
  static const String sending = 'sending';
  static const String sent = 'sent';
  static const String delivered = 'delivered';
  static const String failed = 'failed';
}

class IntroductionOutboxDeliveryPath {
  static const String pending = 'pending';
  static const String local = 'local';
  static const String direct = 'direct';
  static const String relay = 'relay';
  static const String inbox = 'inbox';
}

class IntroductionOutboxDelivery {
  final String deliveryId;
  final String introductionId;
  final String action;
  final String targetPeerId;
  final String senderPeerId;
  final String rawEnvelope;
  final String deliveryStatus;
  final String deliveryPath;
  final String? lastError;
  final String createdAt;
  final String updatedAt;

  const IntroductionOutboxDelivery({
    required this.deliveryId,
    required this.introductionId,
    required this.action,
    required this.targetPeerId,
    required this.senderPeerId,
    required this.rawEnvelope,
    required this.deliveryStatus,
    required this.deliveryPath,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  factory IntroductionOutboxDelivery.fromMap(Map<String, Object?> map) {
    return IntroductionOutboxDelivery(
      deliveryId: map['delivery_id'] as String,
      introductionId: map['introduction_id'] as String,
      action: map['action'] as String,
      targetPeerId: map['target_peer_id'] as String,
      senderPeerId: map['sender_peer_id'] as String,
      rawEnvelope: map['raw_envelope'] as String,
      deliveryStatus: map['delivery_status'] as String,
      deliveryPath: map['delivery_path'] as String,
      lastError: map['last_error'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'delivery_id': deliveryId,
      'introduction_id': introductionId,
      'action': action,
      'target_peer_id': targetPeerId,
      'sender_peer_id': senderPeerId,
      'raw_envelope': rawEnvelope,
      'delivery_status': deliveryStatus,
      'delivery_path': deliveryPath,
      'last_error': lastError,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  IntroductionOutboxDelivery copyWith({
    String? deliveryId,
    String? introductionId,
    String? action,
    String? targetPeerId,
    String? senderPeerId,
    String? rawEnvelope,
    String? deliveryStatus,
    String? deliveryPath,
    Object? lastError = _sentinel,
    String? createdAt,
    String? updatedAt,
  }) {
    return IntroductionOutboxDelivery(
      deliveryId: deliveryId ?? this.deliveryId,
      introductionId: introductionId ?? this.introductionId,
      action: action ?? this.action,
      targetPeerId: targetPeerId ?? this.targetPeerId,
      senderPeerId: senderPeerId ?? this.senderPeerId,
      rawEnvelope: rawEnvelope ?? this.rawEnvelope,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      deliveryPath: deliveryPath ?? this.deliveryPath,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const Object _sentinel = Object();
