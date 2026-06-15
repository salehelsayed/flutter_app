import 'dart:convert';

enum MigrationCutoverDeviceRole {
  unknown('unknown'),
  oldPhone('old_phone'),
  newPhone('new_phone');

  const MigrationCutoverDeviceRole(this.wireName);

  final String wireName;

  static MigrationCutoverDeviceRole? fromWireName(String wireName) {
    for (final role in values) {
      if (role.wireName == wireName) return role;
    }
    return null;
  }
}

enum MigrationCutoverPhase {
  oldNetworkBlocked('old_network_blocked'),
  oldBlockProofReceived('old_block_proof_received'),
  newActiveCommitted('new_active_committed'),
  oldMigratedOutCommitted('old_migrated_out_committed'),
  leaseCleanupPending('lease_cleanup_pending'),
  complete('complete'),
  failed('failed');

  const MigrationCutoverPhase(this.wireName);

  final String wireName;

  static MigrationCutoverPhase? fromWireName(String wireName) {
    for (final phase in values) {
      if (phase.wireName == wireName) return phase;
    }
    return null;
  }
}

class MigrationCutoverRecord {
  static const int currentVersion = 1;

  final String sessionId;
  final String? accountPeerId;
  final String? devicePeerId;
  final MigrationCutoverDeviceRole deviceRole;
  final MigrationCutoverPhase phase;
  final bool oldNetworkBlocked;
  final bool oldBlockProofReceived;
  final bool newActiveCommitted;
  final bool oldMigratedOutCommitted;
  final bool rendezvousUnregisterIssued;
  final bool inboxPushTokenUnregisterIssued;
  final bool stalePushTokenCleared;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? oldNetworkBlockedAt;
  final DateTime? oldBlockProofReceivedAt;
  final DateTime? newActiveCommittedAt;
  final DateTime? oldMigratedOutCommittedAt;
  final DateTime? leaseCleanupAttemptedAt;
  final String? failureCode;
  final String? failureDetails;
  final bool isFailClosed;

  const MigrationCutoverRecord({
    required this.sessionId,
    required this.accountPeerId,
    required this.devicePeerId,
    required this.deviceRole,
    required this.phase,
    required this.oldNetworkBlocked,
    required this.oldBlockProofReceived,
    required this.newActiveCommitted,
    required this.oldMigratedOutCommitted,
    required this.rendezvousUnregisterIssued,
    required this.inboxPushTokenUnregisterIssued,
    required this.stalePushTokenCleared,
    required this.createdAt,
    required this.updatedAt,
    this.oldNetworkBlockedAt,
    this.oldBlockProofReceivedAt,
    this.newActiveCommittedAt,
    this.oldMigratedOutCommittedAt,
    this.leaseCleanupAttemptedAt,
    this.failureCode,
    this.failureDetails,
    this.isFailClosed = false,
  });

  factory MigrationCutoverRecord.initial({
    required String sessionId,
    required String accountPeerId,
    required String devicePeerId,
    required MigrationCutoverDeviceRole deviceRole,
    required DateTime now,
  }) {
    return MigrationCutoverRecord(
      sessionId: sessionId,
      accountPeerId: accountPeerId,
      devicePeerId: devicePeerId,
      deviceRole: deviceRole,
      phase: MigrationCutoverPhase.oldNetworkBlocked,
      oldNetworkBlocked: false,
      oldBlockProofReceived: false,
      newActiveCommitted: false,
      oldMigratedOutCommitted: false,
      rendezvousUnregisterIssued: false,
      inboxPushTokenUnregisterIssued: false,
      stalePushTokenCleared: false,
      createdAt: now.toUtc(),
      updatedAt: now.toUtc(),
    );
  }

  factory MigrationCutoverRecord.failClosed() {
    final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return MigrationCutoverRecord(
      sessionId: 'unknown',
      accountPeerId: null,
      devicePeerId: null,
      deviceRole: MigrationCutoverDeviceRole.unknown,
      phase: MigrationCutoverPhase.failed,
      oldNetworkBlocked: false,
      oldBlockProofReceived: false,
      newActiveCommitted: false,
      oldMigratedOutCommitted: false,
      rendezvousUnregisterIssued: false,
      inboxPushTokenUnregisterIssued: false,
      stalePushTokenCleared: false,
      createdAt: now,
      updatedAt: now,
      failureCode: 'malformed_cutover_record',
      failureDetails: 'persisted record could not be parsed',
      isFailClosed: true,
    );
  }

  factory MigrationCutoverRecord.fromPersistedJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return MigrationCutoverRecord.failClosed();
      }
      return MigrationCutoverRecord.fromJson(decoded);
    } catch (_) {
      return MigrationCutoverRecord.failClosed();
    }
  }

  factory MigrationCutoverRecord.fromJson(Map<String, dynamic> decoded) {
    try {
      if (decoded['version'] != currentVersion) {
        return MigrationCutoverRecord.failClosed();
      }

      final sessionId = decoded['sessionId'];
      final roleWireName = decoded['deviceRole'];
      final phaseWireName = decoded['phase'];
      if (sessionId is! String ||
          roleWireName is! String ||
          phaseWireName is! String) {
        return MigrationCutoverRecord.failClosed();
      }

      final role = MigrationCutoverDeviceRole.fromWireName(roleWireName);
      final phase = MigrationCutoverPhase.fromWireName(phaseWireName);
      if (role == null || phase == null) {
        return MigrationCutoverRecord.failClosed();
      }

      final createdAt = _parsePersistedDate(decoded['createdAt']);
      final updatedAt = _parsePersistedDate(decoded['updatedAt']);
      if (createdAt == null || updatedAt == null) {
        return MigrationCutoverRecord.failClosed();
      }

      final accountPeerId = decoded['accountPeerId'];
      final devicePeerId = decoded['devicePeerId'];
      if (accountPeerId != null && accountPeerId is! String) {
        return MigrationCutoverRecord.failClosed();
      }
      if (devicePeerId != null && devicePeerId is! String) {
        return MigrationCutoverRecord.failClosed();
      }

      return MigrationCutoverRecord(
        sessionId: sessionId,
        accountPeerId: accountPeerId as String?,
        devicePeerId: devicePeerId as String?,
        deviceRole: role,
        phase: phase,
        oldNetworkBlocked: _readBool(decoded, 'oldNetworkBlocked'),
        oldBlockProofReceived: _readBool(decoded, 'oldBlockProofReceived'),
        newActiveCommitted: _readBool(decoded, 'newActiveCommitted'),
        oldMigratedOutCommitted: _readBool(decoded, 'oldMigratedOutCommitted'),
        rendezvousUnregisterIssued: _readBool(
          decoded,
          'rendezvousUnregisterIssued',
        ),
        inboxPushTokenUnregisterIssued: _readBool(
          decoded,
          'inboxPushTokenUnregisterIssued',
        ),
        stalePushTokenCleared: _readBool(decoded, 'stalePushTokenCleared'),
        createdAt: createdAt,
        updatedAt: updatedAt,
        oldNetworkBlockedAt: _parsePersistedDate(
          decoded['oldNetworkBlockedAt'],
        ),
        oldBlockProofReceivedAt: _parsePersistedDate(
          decoded['oldBlockProofReceivedAt'],
        ),
        newActiveCommittedAt: _parsePersistedDate(
          decoded['newActiveCommittedAt'],
        ),
        oldMigratedOutCommittedAt: _parsePersistedDate(
          decoded['oldMigratedOutCommittedAt'],
        ),
        leaseCleanupAttemptedAt: _parsePersistedDate(
          decoded['leaseCleanupAttemptedAt'],
        ),
        failureCode: _readOptionalString(decoded, 'failureCode'),
        failureDetails: _readOptionalString(decoded, 'failureDetails'),
      );
    } catch (_) {
      return MigrationCutoverRecord.failClosed();
    }
  }

  bool get hasPendingLeaseCleanup {
    return !rendezvousUnregisterIssued ||
        !inboxPushTokenUnregisterIssued ||
        !stalePushTokenCleared;
  }

  bool get provesOldNetworkBlocked {
    return oldNetworkBlocked && oldNetworkBlockedAt != null;
  }

  bool get provesNewActiveCommitted {
    return newActiveCommitted && newActiveCommittedAt != null;
  }

  MigrationCutoverRecord copyWith({
    String? sessionId,
    String? accountPeerId,
    String? devicePeerId,
    MigrationCutoverDeviceRole? deviceRole,
    MigrationCutoverPhase? phase,
    bool? oldNetworkBlocked,
    bool? oldBlockProofReceived,
    bool? newActiveCommitted,
    bool? oldMigratedOutCommitted,
    bool? rendezvousUnregisterIssued,
    bool? inboxPushTokenUnregisterIssued,
    bool? stalePushTokenCleared,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? oldNetworkBlockedAt,
    DateTime? oldBlockProofReceivedAt,
    DateTime? newActiveCommittedAt,
    DateTime? oldMigratedOutCommittedAt,
    DateTime? leaseCleanupAttemptedAt,
    String? failureCode,
    String? failureDetails,
    bool clearFailure = false,
  }) {
    return MigrationCutoverRecord(
      sessionId: sessionId ?? this.sessionId,
      accountPeerId: accountPeerId ?? this.accountPeerId,
      devicePeerId: devicePeerId ?? this.devicePeerId,
      deviceRole: deviceRole ?? this.deviceRole,
      phase: phase ?? this.phase,
      oldNetworkBlocked: oldNetworkBlocked ?? this.oldNetworkBlocked,
      oldBlockProofReceived:
          oldBlockProofReceived ?? this.oldBlockProofReceived,
      newActiveCommitted: newActiveCommitted ?? this.newActiveCommitted,
      oldMigratedOutCommitted:
          oldMigratedOutCommitted ?? this.oldMigratedOutCommitted,
      rendezvousUnregisterIssued:
          rendezvousUnregisterIssued ?? this.rendezvousUnregisterIssued,
      inboxPushTokenUnregisterIssued:
          inboxPushTokenUnregisterIssued ?? this.inboxPushTokenUnregisterIssued,
      stalePushTokenCleared:
          stalePushTokenCleared ?? this.stalePushTokenCleared,
      createdAt: (createdAt ?? this.createdAt).toUtc(),
      updatedAt: (updatedAt ?? this.updatedAt).toUtc(),
      oldNetworkBlockedAt:
          oldNetworkBlockedAt?.toUtc() ?? this.oldNetworkBlockedAt,
      oldBlockProofReceivedAt:
          oldBlockProofReceivedAt?.toUtc() ?? this.oldBlockProofReceivedAt,
      newActiveCommittedAt:
          newActiveCommittedAt?.toUtc() ?? this.newActiveCommittedAt,
      oldMigratedOutCommittedAt:
          oldMigratedOutCommittedAt?.toUtc() ?? this.oldMigratedOutCommittedAt,
      leaseCleanupAttemptedAt:
          leaseCleanupAttemptedAt?.toUtc() ?? this.leaseCleanupAttemptedAt,
      failureCode: clearFailure ? null : failureCode ?? this.failureCode,
      failureDetails: clearFailure
          ? null
          : failureDetails ?? this.failureDetails,
      isFailClosed: isFailClosed,
    );
  }

  String toPersistedJson() {
    return jsonEncode(toJson());
  }

  Map<String, Object?> toJson() {
    return {
      'version': currentVersion,
      'sessionId': sessionId,
      if (accountPeerId != null) 'accountPeerId': accountPeerId,
      if (devicePeerId != null) 'devicePeerId': devicePeerId,
      'deviceRole': deviceRole.wireName,
      'phase': phase.wireName,
      'oldNetworkBlocked': oldNetworkBlocked,
      'oldBlockProofReceived': oldBlockProofReceived,
      'newActiveCommitted': newActiveCommitted,
      'oldMigratedOutCommitted': oldMigratedOutCommitted,
      'rendezvousUnregisterIssued': rendezvousUnregisterIssued,
      'inboxPushTokenUnregisterIssued': inboxPushTokenUnregisterIssued,
      'stalePushTokenCleared': stalePushTokenCleared,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      if (oldNetworkBlockedAt != null)
        'oldNetworkBlockedAt': oldNetworkBlockedAt!.toUtc().toIso8601String(),
      if (oldBlockProofReceivedAt != null)
        'oldBlockProofReceivedAt': oldBlockProofReceivedAt!
            .toUtc()
            .toIso8601String(),
      if (newActiveCommittedAt != null)
        'newActiveCommittedAt': newActiveCommittedAt!.toUtc().toIso8601String(),
      if (oldMigratedOutCommittedAt != null)
        'oldMigratedOutCommittedAt': oldMigratedOutCommittedAt!
            .toUtc()
            .toIso8601String(),
      if (leaseCleanupAttemptedAt != null)
        'leaseCleanupAttemptedAt': leaseCleanupAttemptedAt!
            .toUtc()
            .toIso8601String(),
      if (failureCode != null) 'failureCode': failureCode,
      if (failureDetails != null) 'failureDetails': failureDetails,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MigrationCutoverRecord &&
            other.sessionId == sessionId &&
            other.accountPeerId == accountPeerId &&
            other.devicePeerId == devicePeerId &&
            other.deviceRole == deviceRole &&
            other.phase == phase &&
            other.oldNetworkBlocked == oldNetworkBlocked &&
            other.oldBlockProofReceived == oldBlockProofReceived &&
            other.newActiveCommitted == newActiveCommitted &&
            other.oldMigratedOutCommitted == oldMigratedOutCommitted &&
            other.rendezvousUnregisterIssued == rendezvousUnregisterIssued &&
            other.inboxPushTokenUnregisterIssued ==
                inboxPushTokenUnregisterIssued &&
            other.stalePushTokenCleared == stalePushTokenCleared &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt &&
            other.oldNetworkBlockedAt == oldNetworkBlockedAt &&
            other.oldBlockProofReceivedAt == oldBlockProofReceivedAt &&
            other.newActiveCommittedAt == newActiveCommittedAt &&
            other.oldMigratedOutCommittedAt == oldMigratedOutCommittedAt &&
            other.leaseCleanupAttemptedAt == leaseCleanupAttemptedAt &&
            other.failureCode == failureCode &&
            other.failureDetails == failureDetails &&
            other.isFailClosed == isFailClosed;
  }

  @override
  int get hashCode => Object.hashAll([
    sessionId,
    accountPeerId,
    devicePeerId,
    deviceRole,
    phase,
    oldNetworkBlocked,
    oldBlockProofReceived,
    newActiveCommitted,
    oldMigratedOutCommitted,
    rendezvousUnregisterIssued,
    inboxPushTokenUnregisterIssued,
    stalePushTokenCleared,
    createdAt,
    updatedAt,
    oldNetworkBlockedAt,
    oldBlockProofReceivedAt,
    newActiveCommittedAt,
    oldMigratedOutCommittedAt,
    leaseCleanupAttemptedAt,
    failureCode,
    failureDetails,
    isFailClosed,
  ]);
}

bool _readBool(Map<String, dynamic> decoded, String key) {
  final value = decoded[key];
  if (value is bool) return value;
  throw FormatException('Expected boolean $key');
}

String? _readOptionalString(Map<String, dynamic> decoded, String key) {
  final value = decoded[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('Expected optional string $key');
}

DateTime? _parsePersistedDate(Object? value) {
  if (value == null) return null;
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}
