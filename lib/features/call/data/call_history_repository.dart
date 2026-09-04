import '../domain/call_end_reason.dart';
import '../domain/call_id.dart';
import '../domain/call_session_snapshot.dart';

enum CallHistoryStatus { completed, missed, declined, busy, cancelled, failed }

extension CallHistoryStatusWire on CallHistoryStatus {
  String get wireName => switch (this) {
    CallHistoryStatus.completed => 'completed',
    CallHistoryStatus.missed => 'missed',
    CallHistoryStatus.declined => 'declined',
    CallHistoryStatus.busy => 'busy',
    CallHistoryStatus.cancelled => 'cancelled',
    CallHistoryStatus.failed => 'failed',
  };

  static CallHistoryStatus parse(String value) => switch (value) {
    'completed' => CallHistoryStatus.completed,
    'missed' => CallHistoryStatus.missed,
    'declined' => CallHistoryStatus.declined,
    'busy' => CallHistoryStatus.busy,
    'cancelled' => CallHistoryStatus.cancelled,
    'failed' => CallHistoryStatus.failed,
    _ => throw const FormatException('unsupported call history status'),
  };
}

/// The complete privacy-safe local projection of one terminal call.
final class CallHistoryEntry {
  CallHistoryEntry({
    required this.callId,
    required this.contactAccountPeerId,
    required this.direction,
    required this.terminalReason,
    required this.status,
    required DateTime startedAt,
    DateTime? connectedAt,
    required DateTime endedAt,
    required this.transportRoute,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : startedAt = startedAt.toUtc(),
       connectedAt = connectedAt?.toUtc(),
       endedAt = endedAt.toUtc(),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (contactAccountPeerId.trim().isEmpty ||
        contactAccountPeerId.length > 512) {
      throw ArgumentError.value(contactAccountPeerId, 'contactAccountPeerId');
    }
    if (this.endedAt.isBefore(this.startedAt) ||
        (this.connectedAt != null &&
            (this.connectedAt!.isBefore(this.startedAt) ||
                this.endedAt.isBefore(this.connectedAt!))) ||
        this.updatedAt.isBefore(this.createdAt)) {
      throw ArgumentError('call history timestamps are not monotonic');
    }
  }

  final CallId callId;
  final String contactAccountPeerId;
  final CallDirection direction;
  final CallEndReason terminalReason;
  final CallHistoryStatus status;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final DateTime endedAt;
  final CallRouteClass? transportRoute;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Duration begins at local connection. Calls that never connected have no
  /// talk duration.
  Duration? get duration =>
      connectedAt == null ? null : endedAt.difference(connectedAt!);

  factory CallHistoryEntry.fromMap(Map<String, Object?> map) =>
      CallHistoryEntry(
        callId: CallId.parse(map['call_id']! as String),
        contactAccountPeerId: map['contact_account_peer_id']! as String,
        direction: CallDirection.values.byName(map['direction']! as String),
        terminalReason: CallEndReason.parseWire(
          map['terminal_reason']! as String,
        ),
        status: CallHistoryStatusWire.parse(map['status']! as String),
        startedAt: DateTime.parse(map['started_at']! as String),
        connectedAt: map['connected_at'] == null
            ? null
            : DateTime.parse(map['connected_at']! as String),
        endedAt: DateTime.parse(map['ended_at']! as String),
        transportRoute: map['transport_route_class'] == null
            ? null
            : CallRouteClassWire.parse(map['transport_route_class']! as String),
        createdAt: DateTime.parse(map['created_at']! as String),
        updatedAt: DateTime.parse(map['updated_at']! as String),
      );

  Map<String, Object?> toMap() => <String, Object?>{
    'call_id': callId.value,
    'contact_account_peer_id': contactAccountPeerId,
    'direction': direction.name,
    'terminal_reason': terminalReason.wireName,
    'status': status.wireName,
    'started_at': startedAt.toIso8601String(),
    'connected_at': connectedAt?.toIso8601String(),
    'ended_at': endedAt.toIso8601String(),
    'transport_route_class': transportRoute?.wireName,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'direction': direction.name,
    'terminalReason': terminalReason.name,
    'status': status.name,
    'hasConnectedAt': connectedAt != null,
    'transportRoute': transportRoute?.name,
  };

  @override
  String toString() => 'CallHistoryEntry(${toDiagnosticMap()})';
}

abstract interface class CallHistoryRepository {
  /// Insert-only by call ID. A replay or conflicting terminal result cannot
  /// rewrite the first durable terminal projection.
  Future<void> upsertTerminal(CallHistoryEntry entry);

  Future<CallHistoryEntry?> getByCallId(CallId callId);

  /// Returns contact-scoped entries in newest-first storage order.
  Future<List<CallHistoryEntry>> listForContact(String contactAccountPeerId);
}
