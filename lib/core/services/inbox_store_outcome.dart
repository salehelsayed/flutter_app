enum InboxStoreStatus { stored, duplicate, rejectedFull, failed }

/// Relay proof required before a direct-text v108 or direct-reaction v109
/// obligation may leave local custody.
const String ackOrExpiryInboxCustodyContract = 'ack_or_expiry_v1';

/// The only app-owned envelopes eligible for ACK-or-expiry relay custody.
enum AckCustodyKind {
  directTextV108('direct_text_v108'),
  directReactionV109('direct_reaction_v109');

  const AckCustodyKind(this.wireValue);

  final String wireValue;
}

class InboxStoreOutcome {
  final InboxStoreStatus status;
  final String? errorCode;
  final String? errorMessage;
  final String? storeStatus;
  final int? expiresAtMs;
  final int? occupancy;
  final int? capacity;
  final String? custodyContract;

  const InboxStoreOutcome({
    required this.status,
    this.errorCode,
    this.errorMessage,
    this.storeStatus,
    this.expiresAtMs,
    this.occupancy,
    this.capacity,
    this.custodyContract,
  });

  bool get accepted =>
      status == InboxStoreStatus.stored || status == InboxStoreStatus.duplicate;

  /// Narrow ownership predicate for DB v108/v109 custody rows.
  ///
  /// Generic relay success remains [accepted], but cannot prove that a relay
  /// row is non-destructive at capacity and retained until exact ACK/expiry.
  bool get ackOrExpiryAccepted =>
      accepted &&
      (storeStatus == 'stored' || storeStatus == 'duplicate') &&
      custodyContract == ackOrExpiryInboxCustodyContract;

  factory InboxStoreOutcome.fromBridgeResponse(Map<String, dynamic> response) {
    final ok = response['ok'] == true;
    final rawStoreStatus = response['storeStatus'] ?? response['store_status'];
    final storeStatus = rawStoreStatus is String ? rawStoreStatus : null;
    final rawErrorCode = response['errorCode'] ?? response['error_code'];
    final errorCode = rawErrorCode is String ? rawErrorCode : null;
    final rawErrorMessage = response['errorMessage'] ?? response['error'];
    final errorMessage = rawErrorMessage is String ? rawErrorMessage : null;
    final rawCustodyContract =
        response['custodyContract'] ?? response['custody_contract'];
    final custodyContract = rawCustodyContract is String
        ? rawCustodyContract
        : null;

    final status = _statusFromResponse(
      ok: ok,
      storeStatus: storeStatus,
      errorCode: errorCode,
    );
    final rawExpiresAtMs =
        _intField(response, 'expiresAtMs') ??
        _intField(response, 'expires_at_ms');

    return InboxStoreOutcome(
      status: status,
      errorCode: errorCode,
      errorMessage: errorMessage,
      storeStatus: storeStatus,
      // The Go bridge serializes an absent optional expiry as zero. Preserve
      // that as "unknown" so accepted duplicate replays can still complete
      // local custody instead of being rejected as a malformed timestamp.
      expiresAtMs: rawExpiresAtMs != null && rawExpiresAtMs > 0
          ? rawExpiresAtMs
          : null,
      occupancy: _intField(response, 'occupancy'),
      capacity: _intField(response, 'capacity'),
      custodyContract: custodyContract,
    );
  }

  /// Parses a strict store receipt and makes accepted-looking responses
  /// without the exact proof non-accepting even to legacy predicates.
  factory InboxStoreOutcome.fromAckOrExpiryBridgeResponse(
    Map<String, dynamic> response,
  ) {
    final parsed = InboxStoreOutcome.fromBridgeResponse(response);
    if (!parsed.accepted || parsed.ackOrExpiryAccepted) return parsed;
    return InboxStoreOutcome(
      status: InboxStoreStatus.failed,
      errorCode: parsed.errorCode ?? 'CUSTODY_PROOF_MISSING_OR_INVALID',
      errorMessage: parsed.errorMessage,
      storeStatus: parsed.storeStatus,
      expiresAtMs: parsed.expiresAtMs,
      occupancy: parsed.occupancy,
      capacity: parsed.capacity,
      custodyContract: parsed.custodyContract,
    );
  }

  static InboxStoreStatus _statusFromResponse({
    required bool ok,
    required String? storeStatus,
    required String? errorCode,
  }) {
    final normalizedStore = storeStatus?.toLowerCase();
    final normalizedError = errorCode?.toUpperCase();

    if (!ok) {
      return normalizedError == 'INBOX_FULL'
          ? InboxStoreStatus.rejectedFull
          : InboxStoreStatus.failed;
    }
    if (normalizedStore == 'duplicate') {
      return InboxStoreStatus.duplicate;
    }
    if (normalizedStore == 'rejected_full') {
      return InboxStoreStatus.rejectedFull;
    }
    return InboxStoreStatus.stored;
  }

  static int? _intField(Map<String, dynamic> response, String key) {
    final value = response[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

typedef StoreInInboxDetailedFn =
    Future<InboxStoreOutcome> Function(
      String toPeerId,
      String message, {
      int? timeoutMs,
    });

abstract class DetailedInboxStore {
  Future<InboxStoreOutcome> storeInInboxDetailed(
    String toPeerId,
    String message, {
    int? timeoutMs,
  });
}

typedef StoreInAckCustodyInboxDetailedFn =
    Future<InboxStoreOutcome> Function(
      String toPeerId,
      String message, {
      required AckCustodyKind custodyKind,
      int? timeoutMs,
    });

/// Optional strict capability implemented only by inbox stores that request
/// and validate the relay's ACK-or-expiry custody contract.
abstract class AckOrExpiryInboxStore {
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  });
}
