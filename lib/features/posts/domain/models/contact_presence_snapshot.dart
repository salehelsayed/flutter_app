enum ContactPresenceSnapshotStatus { active, inactive }

class ContactPresenceSnapshot {
  final String peerId;
  final ContactPresenceSnapshotStatus status;
  final int? latE3;
  final int? lngE3;
  final String capturedAt;
  final double? accuracyM;
  final String updatedAt;

  const ContactPresenceSnapshot({
    required this.peerId,
    required this.status,
    this.latE3,
    this.lngE3,
    required this.capturedAt,
    this.accuracyM,
    required this.updatedAt,
  });

  factory ContactPresenceSnapshot.fromMap(Map<String, Object?> row) {
    return ContactPresenceSnapshot(
      peerId: row['peer_id'] as String,
      status: ContactPresenceSnapshotStatusWireValue.fromWireValue(
        row['status'] as String?,
      ),
      latE3: row['lat_e3'] as int?,
      lngE3: row['lng_e3'] as int?,
      capturedAt: row['captured_at'] as String,
      accuracyM: (row['accuracy_m'] as num?)?.toDouble(),
      updatedAt: row['updated_at'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'peer_id': peerId,
      'status': status.toWireValue(),
      'lat_e3': latE3,
      'lng_e3': lngE3,
      'captured_at': capturedAt,
      'accuracy_m': accuracyM,
      'updated_at': updatedAt,
    };
  }

  ContactPresenceSnapshot copyWith({
    ContactPresenceSnapshotStatus? status,
    int? latE3,
    int? lngE3,
    String? capturedAt,
    double? accuracyM,
    String? updatedAt,
    bool clearCoordinates = false,
  }) {
    return ContactPresenceSnapshot(
      peerId: peerId,
      status: status ?? this.status,
      latE3: clearCoordinates ? null : (latE3 ?? this.latE3),
      lngE3: clearCoordinates ? null : (lngE3 ?? this.lngE3),
      capturedAt: capturedAt ?? this.capturedAt,
      accuracyM: clearCoordinates ? null : (accuracyM ?? this.accuracyM),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

extension ContactPresenceSnapshotStatusWireValue
    on ContactPresenceSnapshotStatus {
  String toWireValue() {
    return switch (this) {
      ContactPresenceSnapshotStatus.active => 'active',
      ContactPresenceSnapshotStatus.inactive => 'inactive',
    };
  }

  static ContactPresenceSnapshotStatus fromWireValue(String? value) {
    return switch (value) {
      'inactive' => ContactPresenceSnapshotStatus.inactive,
      _ => ContactPresenceSnapshotStatus.active,
    };
  }
}
