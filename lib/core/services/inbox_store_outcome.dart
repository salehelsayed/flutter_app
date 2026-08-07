enum InboxStoreStatus { stored, duplicate, rejectedFull, failed }

class InboxStoreOutcome {
  final InboxStoreStatus status;
  final String? errorCode;
  final String? errorMessage;
  final String? storeStatus;
  final int? expiresAtMs;
  final int? occupancy;
  final int? capacity;

  const InboxStoreOutcome({
    required this.status,
    this.errorCode,
    this.errorMessage,
    this.storeStatus,
    this.expiresAtMs,
    this.occupancy,
    this.capacity,
  });

  bool get accepted =>
      status == InboxStoreStatus.stored || status == InboxStoreStatus.duplicate;

  factory InboxStoreOutcome.fromBridgeResponse(Map<String, dynamic> response) {
    final ok = response['ok'] == true;
    final rawStoreStatus = response['storeStatus'] ?? response['store_status'];
    final storeStatus = rawStoreStatus is String ? rawStoreStatus : null;
    final rawErrorCode = response['errorCode'] ?? response['error_code'];
    final errorCode = rawErrorCode is String ? rawErrorCode : null;
    final rawErrorMessage = response['errorMessage'] ?? response['error'];
    final errorMessage = rawErrorMessage is String ? rawErrorMessage : null;

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
