/// Closed, local-export-only additions to the deployed v1 schemas. Receivers
/// have no negotiated capability for these fields. Never send them on v1.
const localCallConnectionEnums = <String, Set<String>>{
  'selectedLocalCandidateFamily': {'ipv4', 'ipv6', 'unknown'},
  'selectedRemoteCandidateFamily': {'ipv4', 'ipv6', 'unknown'},
  'localTurnConnectionFamily': {'ipv4', 'ipv6', 'unknown'},
  'remoteTurnConnectionFamily': {'ipv4', 'ipv6', 'unknown'},
  'pairRelayInvolvement': {'none', 'local', 'remote', 'both', 'unknown'},
  'selectedPairState': {'succeeded', 'failed', 'pending', 'unknown'},
  'failureDisposition': {'provisional', 'terminal', 'unknown'},
};

const localAppConnectionEnums = <String, Set<String>>{
  'connectionStage': {
    'candidate_failed',
    'established',
    'stream_opened',
    'stream_failed',
    'recovery',
    'recipient_ack',
    'inbox_acceptance',
  },
  'connectionOutcome': {'ok', 'failed', 'unknown'},
  'addressFamily': {'ipv4', 'ipv6', 'unknown'},
  'transportProtocol': {'tcp', 'quic', 'ws', 'wss', 'unknown'},
  'pathClass': {'direct', 'circuit', 'unknown'},
  'observedLeg': {'endpoint_to_peer', 'endpoint_to_relay', 'unknown'},
  'familyFallback': {'ipv6_to_ipv4', 'ipv4_to_ipv6', 'unknown'},
};

/// Native results are untrusted at this boundary. Only complete closed rows
/// reach a collector; unknown keys, free text and nested material are rejected.
/// The sink is synchronous and best-effort, and no observer result is returned.
void observeConnectionDiagnostics(
  Object? records,
  void Function(Map<String, Object?> values) sink,
) {
  if (records is! List) return;
  for (final raw in records.take(12)) {
    try {
      if (raw is! Map || raw.length != localAppConnectionEnums.length) continue;
      final values = <String, Object?>{};
      for (final entry in localAppConnectionEnums.entries) {
        final value = raw[entry.key];
        if (value is! String || !entry.value.contains(value)) break;
        values[entry.key] = value;
      }
      if (values.length == localAppConnectionEnums.length) sink(values);
    } catch (_) {
      // Diagnostic admission/storage cannot fail the command being observed.
    }
  }
}

/// Copy-on-upload preserves local evidence and event IDs/acknowledgments.
Map<String, Object?> withoutLocalConnectionValues(
  Map<String, Object?> event,
  Map<String, Set<String>> localEnums,
) => {
  ...event,
  'values': {
    for (final entry in (event['values'] as Map).entries)
      if (!localEnums.containsKey(entry.key)) entry.key as String: entry.value,
  },
};
