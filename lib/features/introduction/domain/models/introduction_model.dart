/// Status of a single party's response to an introduction.
enum IntroductionStatus { pending, accepted, passed }

/// Overall status of the introduction derived from both parties' responses.
enum IntroductionOverallStatus { pending, mutualAccepted, passed, expired, alreadyConnected }

/// Model representing an introduction between two peers, facilitated by an introducer.
class IntroductionModel {
  final String id;
  final String introducerId;
  final String recipientId;
  final String introducedId;
  final IntroductionStatus recipientStatus;
  final IntroductionStatus introducedStatus;
  final IntroductionOverallStatus status;
  final String createdAt;
  final String? recipientRespondedAt;
  final String? introducedRespondedAt;
  final String? introducerUsername;
  final String? recipientUsername;
  final String? introducedUsername;
  final String? introducedPublicKey;
  final String? introducedMlKemPublicKey;
  final String? recipientPublicKey;
  final String? recipientMlKemPublicKey;

  const IntroductionModel({
    required this.id,
    required this.introducerId,
    required this.recipientId,
    required this.introducedId,
    this.recipientStatus = IntroductionStatus.pending,
    this.introducedStatus = IntroductionStatus.pending,
    this.status = IntroductionOverallStatus.pending,
    required this.createdAt,
    this.recipientRespondedAt,
    this.introducedRespondedAt,
    this.introducerUsername,
    this.recipientUsername,
    this.introducedUsername,
    this.introducedPublicKey,
    this.introducedMlKemPublicKey,
    this.recipientPublicKey,
    this.recipientMlKemPublicKey,
  });

  /// Creates an IntroductionModel from a database row.
  factory IntroductionModel.fromMap(Map<String, dynamic> map) {
    return IntroductionModel(
      id: map['id'] as String,
      introducerId: map['introducer_id'] as String,
      recipientId: map['recipient_id'] as String,
      introducedId: map['introduced_id'] as String,
      recipientStatus: _parseIntroductionStatus(map['recipient_status'] as String? ?? 'pending'),
      introducedStatus: _parseIntroductionStatus(map['introduced_status'] as String? ?? 'pending'),
      status: _parseOverallStatus(map['status'] as String? ?? 'pending'),
      createdAt: map['created_at'] as String,
      recipientRespondedAt: map['recipient_responded_at'] as String?,
      introducedRespondedAt: map['introduced_responded_at'] as String?,
      introducerUsername: map['introducer_username'] as String?,
      recipientUsername: map['recipient_username'] as String?,
      introducedUsername: map['introduced_username'] as String?,
      introducedPublicKey: map['introduced_public_key'] as String?,
      introducedMlKemPublicKey: map['introduced_ml_kem_public_key'] as String?,
      recipientPublicKey: map['recipient_public_key'] as String?,
      recipientMlKemPublicKey: map['recipient_ml_kem_public_key'] as String?,
    );
  }

  /// Converts the model to a database row map.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'introducer_id': introducerId,
      'recipient_id': recipientId,
      'introduced_id': introducedId,
      'recipient_status': recipientStatus.toDbString(),
      'introduced_status': introducedStatus.toDbString(),
      'status': status.toDbString(),
      'created_at': createdAt,
      'recipient_responded_at': recipientRespondedAt,
      'introduced_responded_at': introducedRespondedAt,
      'introducer_username': introducerUsername,
      'recipient_username': recipientUsername,
      'introduced_username': introducedUsername,
      'introduced_public_key': introducedPublicKey,
      'introduced_ml_kem_public_key': introducedMlKemPublicKey,
      'recipient_public_key': recipientPublicKey,
      'recipient_ml_kem_public_key': recipientMlKemPublicKey,
    };
  }

  /// Creates a copy with updated fields.
  IntroductionModel copyWith({
    String? id,
    String? introducerId,
    String? recipientId,
    String? introducedId,
    IntroductionStatus? recipientStatus,
    IntroductionStatus? introducedStatus,
    IntroductionOverallStatus? status,
    String? createdAt,
    String? recipientRespondedAt,
    String? introducedRespondedAt,
    String? introducerUsername,
    String? recipientUsername,
    String? introducedUsername,
    String? introducedPublicKey,
    String? introducedMlKemPublicKey,
    String? recipientPublicKey,
    String? recipientMlKemPublicKey,
  }) {
    return IntroductionModel(
      id: id ?? this.id,
      introducerId: introducerId ?? this.introducerId,
      recipientId: recipientId ?? this.recipientId,
      introducedId: introducedId ?? this.introducedId,
      recipientStatus: recipientStatus ?? this.recipientStatus,
      introducedStatus: introducedStatus ?? this.introducedStatus,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      recipientRespondedAt: recipientRespondedAt ?? this.recipientRespondedAt,
      introducedRespondedAt: introducedRespondedAt ?? this.introducedRespondedAt,
      introducerUsername: introducerUsername ?? this.introducerUsername,
      recipientUsername: recipientUsername ?? this.recipientUsername,
      introducedUsername: introducedUsername ?? this.introducedUsername,
      introducedPublicKey: introducedPublicKey ?? this.introducedPublicKey,
      introducedMlKemPublicKey: introducedMlKemPublicKey ?? this.introducedMlKemPublicKey,
      recipientPublicKey: recipientPublicKey ?? this.recipientPublicKey,
      recipientMlKemPublicKey: recipientMlKemPublicKey ?? this.recipientMlKemPublicKey,
    );
  }

  /// Derives the overall status from the two parties' statuses and creation time.
  ///
  /// - Both accepted -> mutualAccepted
  /// - Either passed -> passed
  /// - Pending for >30 days -> expired
  /// - Otherwise -> pending
  static IntroductionOverallStatus deriveStatus({
    required IntroductionStatus recipientStatus,
    required IntroductionStatus introducedStatus,
    required String createdAt,
  }) {
    if (recipientStatus == IntroductionStatus.accepted &&
        introducedStatus == IntroductionStatus.accepted) {
      return IntroductionOverallStatus.mutualAccepted;
    }

    if (recipientStatus == IntroductionStatus.passed ||
        introducedStatus == IntroductionStatus.passed) {
      return IntroductionOverallStatus.passed;
    }

    final createdTime = DateTime.parse(createdAt);
    final now = DateTime.now().toUtc();
    if (now.difference(createdTime).inDays > 30) {
      return IntroductionOverallStatus.expired;
    }

    return IntroductionOverallStatus.pending;
  }

  @override
  String toString() {
    return 'IntroductionModel(id: ${id.substring(0, id.length < 10 ? id.length : 10)}..., status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IntroductionModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Parses a database string into an IntroductionStatus.
IntroductionStatus _parseIntroductionStatus(String value) {
  switch (value) {
    case 'accepted':
      return IntroductionStatus.accepted;
    case 'passed':
      return IntroductionStatus.passed;
    case 'pending':
    default:
      return IntroductionStatus.pending;
  }
}

/// Parses a database string into an IntroductionOverallStatus.
IntroductionOverallStatus _parseOverallStatus(String value) {
  switch (value) {
    case 'mutual_accepted':
      return IntroductionOverallStatus.mutualAccepted;
    case 'passed':
      return IntroductionOverallStatus.passed;
    case 'expired':
      return IntroductionOverallStatus.expired;
    case 'already_connected':
      return IntroductionOverallStatus.alreadyConnected;
    case 'pending':
    default:
      return IntroductionOverallStatus.pending;
  }
}

/// Extension to convert IntroductionStatus to database string.
extension IntroductionStatusExt on IntroductionStatus {
  String toDbString() {
    switch (this) {
      case IntroductionStatus.pending:
        return 'pending';
      case IntroductionStatus.accepted:
        return 'accepted';
      case IntroductionStatus.passed:
        return 'passed';
    }
  }
}

/// Extension to convert IntroductionOverallStatus to database string.
extension IntroductionOverallStatusExt on IntroductionOverallStatus {
  String toDbString() {
    switch (this) {
      case IntroductionOverallStatus.pending:
        return 'pending';
      case IntroductionOverallStatus.mutualAccepted:
        return 'mutual_accepted';
      case IntroductionOverallStatus.passed:
        return 'passed';
      case IntroductionOverallStatus.expired:
        return 'expired';
      case IntroductionOverallStatus.alreadyConnected:
        return 'already_connected';
    }
  }
}
