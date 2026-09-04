import '../domain/call_id.dart';
import '../domain/call_signal.dart';

enum CallNegotiationMaterialType { offer, answer, ice, iceRestart }

/// Authenticated signaling material kept outside reducer-owned state.
final class CallNegotiationMaterial {
  CallNegotiationMaterial({
    required this.callId,
    required this.eventId,
    required this.type,
    required this.iceGeneration,
    required Map<String, Object?> payload,
  }) : payload = Map<String, Object?>.unmodifiable(
         payload.map(
           (key, value) => MapEntry<String, Object?>(key, _copyJson(value)),
         ),
       ) {
    if (eventId.trim().isEmpty || eventId.length > 128) {
      throw ArgumentError.value(eventId, 'eventId', 'must be 1..128 chars');
    }
    if (iceGeneration < 0) {
      throw ArgumentError.value(
        iceGeneration,
        'iceGeneration',
        'must be non-negative',
      );
    }
  }

  factory CallNegotiationMaterial.fromSignal(CallSignal signal) =>
      CallNegotiationMaterial(
        callId: signal.callId,
        eventId: signal.messageId,
        type: switch (signal.event) {
          CallSignalType.offer => CallNegotiationMaterialType.offer,
          CallSignalType.answer => CallNegotiationMaterialType.answer,
          CallSignalType.ice => CallNegotiationMaterialType.ice,
          CallSignalType.iceRestart => CallNegotiationMaterialType.iceRestart,
          _ => throw ArgumentError.value(
            signal.event,
            'signal',
            'does not contain negotiation material',
          ),
        },
        iceGeneration: signal.iceGeneration,
        payload: signal.payload,
      );

  final CallId callId;
  final String eventId;
  final CallNegotiationMaterialType type;
  final int iceGeneration;
  final Map<String, Object?> payload;

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'type': type.name,
    'iceGeneration': iceGeneration,
    'payloadFieldCount': payload.length,
  };

  @override
  String toString() => 'CallNegotiationMaterial(${toDiagnosticMap()})';

  static Object? _copyJson(Object? value) {
    if (value is Map) {
      return Map<Object?, Object?>.unmodifiable(
        value.map(
          (key, nested) => MapEntry<Object?, Object?>(key, _copyJson(nested)),
        ),
      );
    }
    if (value is List) {
      return List<Object?>.unmodifiable(value.map<Object?>(_copyJson));
    }
    return value;
  }
}

enum CallNegotiationMaterialStoreDecision {
  stored,
  duplicate,
  staleGeneration,
  capacityExceeded,
}

/// A bounded, in-memory handoff from authenticated signaling to media effects.
///
/// A newly stored generation is staged until [commitEvent] or [take]. Calling
/// [purgeEvent] rolls that stage back, so a reducer-rejected event cannot move
/// the generation watermark forward.
final class CallNegotiationMaterialStore {
  CallNegotiationMaterialStore({
    this.maxCalls = 4,
    this.maxEntriesPerCall = 64,
  }) {
    if (maxCalls <= 0 || maxEntriesPerCall <= 0) {
      throw ArgumentError('negotiation material bounds must be positive');
    }
  }

  final int maxCalls;
  final int maxEntriesPerCall;
  final Map<CallId, _CallMaterialBucket> _calls =
      <CallId, _CallMaterialBucket>{};

  int get callCount => _calls.length;

  int entryCountFor(CallId callId) => _calls[callId]?.entries.length ?? 0;

  CallNegotiationMaterialStoreDecision store(CallNegotiationMaterial material) {
    var bucket = _calls[material.callId];
    if (bucket == null) {
      if (_calls.length >= maxCalls) {
        return CallNegotiationMaterialStoreDecision.capacityExceeded;
      }
      bucket = _CallMaterialBucket();
      _calls[material.callId] = bucket;
    }

    if (bucket.entries.containsKey(material.eventId)) {
      return CallNegotiationMaterialStoreDecision.duplicate;
    }
    if (material.iceGeneration < bucket.generation) {
      return CallNegotiationMaterialStoreDecision.staleGeneration;
    }

    if (material.iceGeneration > bucket.generation) {
      final displaced = Map<String, CallNegotiationMaterial>.from(
        bucket.entries,
      );
      final previousGeneration = bucket.generation;
      bucket.entries.clear();
      bucket.generation = material.iceGeneration;
      bucket.reservations[material.eventId] = _MaterialReservation(
        previousGeneration: previousGeneration,
        displacedEntries: displaced,
      );
    } else {
      if (bucket.entries.length >= maxEntriesPerCall) {
        return CallNegotiationMaterialStoreDecision.capacityExceeded;
      }
      bucket.reservations[material.eventId] = const _MaterialReservation();
    }

    bucket.entries[material.eventId] = material;
    return CallNegotiationMaterialStoreDecision.stored;
  }

  /// Marks retained material as reducer-accepted without consuming it.
  bool commitEvent(CallId callId, String eventId) {
    final bucket = _calls[callId];
    if (bucket == null || !bucket.entries.containsKey(eventId)) return false;
    bucket.reservations.remove(eventId);
    return true;
  }

  /// Atomically consumes one accepted material item for the canonical effect.
  CallNegotiationMaterial? take(CallId callId, String eventId) {
    final bucket = _calls[callId];
    if (bucket == null) return null;
    bucket.reservations.remove(eventId);
    return bucket.entries.remove(eventId);
  }

  /// Removes one rejected staged item and restores the earlier generation.
  bool purgeEvent(CallId callId, String eventId) {
    final bucket = _calls[callId];
    if (bucket == null) return false;
    final removed = bucket.entries.remove(eventId);
    if (removed == null) return false;
    final reservation = bucket.reservations.remove(eventId);
    if (reservation?.previousGeneration != null) {
      final hasLaterEntry = bucket.entries.values.any(
        (material) => material.iceGeneration >= removed.iceGeneration,
      );
      if (!hasLaterEntry) {
        bucket.generation = reservation!.previousGeneration!;
        bucket.entries.addAll(reservation.displacedEntries);
      }
    }
    if (bucket.entries.isEmpty && bucket.generation < 0) {
      _calls.remove(callId);
    }
    return true;
  }

  void purgeCall(CallId callId) => _calls.remove(callId);

  @override
  String toString() =>
      'CallNegotiationMaterialStore(callCount: $callCount, '
      'entryCount: ${_calls.values.fold<int>(0, (sum, bucket) => sum + bucket.entries.length)})';
}

final class _CallMaterialBucket {
  int generation = -1;
  final Map<String, CallNegotiationMaterial> entries =
      <String, CallNegotiationMaterial>{};
  final Map<String, _MaterialReservation> reservations =
      <String, _MaterialReservation>{};
}

final class _MaterialReservation {
  const _MaterialReservation({
    this.previousGeneration,
    this.displacedEntries = const <String, CallNegotiationMaterial>{},
  });

  final int? previousGeneration;
  final Map<String, CallNegotiationMaterial> displacedEntries;
}
