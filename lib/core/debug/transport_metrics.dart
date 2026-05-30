import 'package:flutter/foundation.dart';

/// Canonical transport buckets used across all metrics.
const List<String> kTransportBuckets = [
  'direct',
  'relay',
  'wifi',
  'inbox',
  'unknown',
];

/// Canonical fallback rungs (ordered worst-improving → last-resort).
const List<String> kFallbackRungs = [
  'reuse',
  'local_race',
  'direct_race',
  'relay_probe',
  'inbox_fallback',
  'failed',
];

/// Canonical send-attempt legs.
///
/// Distinct from delivered [kTransportBuckets] and from terminal
/// [kFallbackRungs]: a leg can be ATTEMPTED and FAIL before a later leg
/// delivers (e.g. a direct race leg fails, then the relay probe wins). The
/// delivered-only transport mix structurally cannot show those failed attempts,
/// so a low `direct` share is ambiguous — it might mean direct was never tried,
/// or that direct was tried and failed often. These per-leg attempt/failure
/// counts disambiguate that, which is the exact signal NET-REL-02/03
/// prioritization depends on.
const List<String> kSendAttemptLegs = [
  'reuse',
  'local',
  'direct',
  'relay_probe',
  'inbox',
];

/// Privacy-safe LAN availability snapshot.
///
/// Holds only the discovery-active flag and the discovered-peer count — never
/// peer identifiers, hostnames, or addresses.
class LanAvailabilitySnapshot {
  final bool discoveryActive;
  final int discoveredPeerCount;

  /// Heuristic, never authoritative: true when discovery has been active with
  /// zero discovered peers long enough that a denied iOS Local-Network
  /// permission is *suspected* (see P4 — no accurate permission API exists
  /// without heavy native code). Has a false positive when the user is simply
  /// alone on the LAN, hence "suspected", never "denied".
  final bool suspectedPermissionDenied;

  const LanAvailabilitySnapshot({
    required this.discoveryActive,
    required this.discoveredPeerCount,
    this.suspectedPermissionDenied = false,
  });

  static const empty = LanAvailabilitySnapshot(
    discoveryActive: false,
    discoveredPeerCount: 0,
    suspectedPermissionDenied: false,
  );
}

/// Computed latency summary for one transport (all values in milliseconds).
class TransportLatencyStats {
  final int sampleCount;
  final int? medianMs; // null when sampleCount == 0
  final int? p95Ms; // null when sampleCount == 0

  const TransportLatencyStats({
    required this.sampleCount,
    required this.medianMs,
    required this.p95Ms,
  });
}

/// In-memory, session-scoped, aggregate-only transport diagnostics.
///
/// Stores only integer counts per bucket/rung, bounded integer latency samples,
/// and a `(bool, int)` LAN snapshot. No peer IDs, message content, conversation
/// IDs, timestamps, or any identifier are ever stored. No data leaves the
/// device.
class TransportMetrics {
  final int _maxSamplesPerTransport;

  final Map<String, int> _transportCounts = {
    for (final bucket in kTransportBuckets) bucket: 0,
  };
  final Map<String, int> _rungCounts = {
    for (final rung in kFallbackRungs) rung: 0,
  };
  final Map<String, List<int>> _latency = {
    for (final bucket in kTransportBuckets) bucket: <int>[],
  };
  final Map<String, int> _latencyWriteIndex = {
    for (final bucket in kTransportBuckets) bucket: 0,
  };
  final Map<String, int> _attemptCounts = {
    for (final leg in kSendAttemptLegs) leg: 0,
  };
  final Map<String, int> _attemptFailureCounts = {
    for (final leg in kSendAttemptLegs) leg: 0,
  };

  LanAvailabilitySnapshot _lanAvailability = LanAvailabilitySnapshot.empty;
  int _totalTransportSamples = 0;

  // NET-REL-02 Option A hole-punch / relay->direct upgrade counters.
  int _holePunchAttempts = 0;
  int _holePunchSuccesses = 0;
  int _holePunchFailures = 0;
  int _relayToDirectUpgrades = 0;

  TransportMetrics({int maxSamplesPerTransport = 256})
    : _maxSamplesPerTransport = maxSamplesPerTransport;

  // ---- Canonicalization ----

  String _canonicalTransport(String? t) {
    final lower = t?.toLowerCase().trim();
    switch (lower) {
      case 'local':
        return 'wifi';
      case 'reuse':
        return 'direct';
      case 'direct':
      case 'relay':
      case 'wifi':
      case 'inbox':
        return lower!;
      default:
        return 'unknown';
    }
  }

  String _canonicalRung(String sendPath) {
    switch (sendPath) {
      case 'reuse':
        return 'reuse';
      case 'local':
        return 'local_race';
      case 'direct':
        return 'direct_race';
      case 'relay':
        return 'relay_probe';
      case 'inbox':
        return 'inbox_fallback';
      default:
        return 'failed';
    }
  }

  // ---- Recording (called from send/receive paths) ----

  /// Record a delivered/received message's transport. [transport] is
  /// canonicalized; null or unrecognized → 'unknown'.
  void recordTransport(String? transport) {
    final bucket = _canonicalTransport(transport);
    _transportCounts[bucket] = (_transportCounts[bucket] ?? 0) + 1;
    _totalTransportSamples++;
  }

  /// Record which fallback rung delivered (or failed) a send. [sendPath] is the
  /// use-case's sendPath label.
  void recordRung(String sendPath) {
    final rung = _canonicalRung(sendPath);
    _rungCounts[rung] = (_rungCounts[rung] ?? 0) + 1;
  }

  /// Record one send-attempt leg outcome, independent of which leg ultimately
  /// delivered. [leg] must be one of [kSendAttemptLegs]; an unrecognized leg is
  /// ignored (no bucket is invented). Captures attempts that FAILED before a
  /// later leg won, which the delivered-only transport mix cannot show.
  void recordAttempt({required String leg, required bool succeeded}) {
    if (!_attemptCounts.containsKey(leg)) {
      return;
    }
    _attemptCounts[leg] = _attemptCounts[leg]! + 1;
    if (!succeeded) {
      _attemptFailureCounts[leg] = _attemptFailureCounts[leg]! + 1;
    }
  }

  /// Record a single end-to-end send latency sample, bucketed by transport.
  /// [transport] is canonicalized; ignored if [latencyMs] is null/negative.
  void recordSendLatency({required String? transport, required int? latencyMs}) {
    if (latencyMs == null || latencyMs < 0) {
      return;
    }
    final bucket = _canonicalTransport(transport);
    final samples = _latency[bucket]!;
    if (samples.length < _maxSamplesPerTransport) {
      samples.add(latencyMs);
    } else {
      final index = _latencyWriteIndex[bucket]! % _maxSamplesPerTransport;
      samples[index] = latencyMs;
      _latencyWriteIndex[bucket] = index + 1;
    }
  }

  /// Replace the current LAN availability snapshot.
  void updateLanAvailability(LanAvailabilitySnapshot snapshot) {
    _lanAvailability = snapshot;
  }

  /// Record a DCUtR hole-punch attempt (holepunch:attempt from Go).
  void recordHolePunchAttempt() => _holePunchAttempts++;

  /// Record a DCUtR hole-punch success (holepunch:success from Go).
  void recordHolePunchSuccess() => _holePunchSuccesses++;

  /// Record a DCUtR hole-punch failure (holepunch:failure from Go).
  void recordHolePunchFailure() => _holePunchFailures++;

  /// Record a relay->direct connection upgrade (transport:upgraded from Go).
  void recordRelayToDirectUpgrade() => _relayToDirectUpgrades++;

  // ---- Reading (called from debug card / report) ----

  /// Count per canonical transport bucket. Keys are always all of
  /// [kTransportBuckets] (zero-filled).
  Map<String, int> transportMix() => Map<String, int>.from(_transportCounts);

  /// Count per fallback rung. Keys are always all of [kFallbackRungs]
  /// (zero-filled).
  Map<String, int> rungDistribution() => Map<String, int>.from(_rungCounts);

  /// Times each send leg was attempted. Keys are always all of
  /// [kSendAttemptLegs] (zero-filled).
  Map<String, int> attemptCounts() => Map<String, int>.from(_attemptCounts);

  /// Times each send leg was attempted and FAILED. Keys are always all of
  /// [kSendAttemptLegs] (zero-filled). `attemptCounts - attemptFailureCounts`
  /// is the per-leg success count.
  Map<String, int> attemptFailureCounts() =>
      Map<String, int>.from(_attemptFailureCounts);

  /// Latency stats per canonical transport bucket (all buckets present).
  Map<String, TransportLatencyStats> latencyByTransport() {
    return {
      for (final bucket in kTransportBuckets)
        bucket: _statsForSamples(_latency[bucket]!),
    };
  }

  /// Current LAN availability snapshot.
  LanAvailabilitySnapshot get lanAvailability => _lanAvailability;

  /// Total messages recorded via [recordTransport] this session.
  int get totalTransportSamples => _totalTransportSamples;

  /// DCUtR hole-punch attempts observed this session.
  int get holePunchAttempts => _holePunchAttempts;

  /// DCUtR hole-punch successes observed this session.
  int get holePunchSuccesses => _holePunchSuccesses;

  /// DCUtR hole-punch failures observed this session.
  int get holePunchFailures => _holePunchFailures;

  /// Relay->direct connection upgrades observed this session.
  int get relayToDirectUpgrades => _relayToDirectUpgrades;

  TransportLatencyStats _statsForSamples(List<int> samples) {
    final n = samples.length;
    if (n == 0) {
      return const TransportLatencyStats(
        sampleCount: 0,
        medianMs: null,
        p95Ms: null,
      );
    }
    final sorted = List<int>.from(samples)..sort();
    final medianIndex = (n - 1) ~/ 2;
    var p95Index = ((n - 1) * 95 / 100).ceil();
    if (p95Index > n - 1) {
      p95Index = n - 1;
    }
    return TransportLatencyStats(
      sampleCount: n,
      medianMs: sorted[medianIndex],
      p95Ms: sorted[p95Index],
    );
  }

  /// AC#5 baseline report. A single multi-line string of aggregate-only
  /// percentages, counts, and median ms — no identifiers.
  String baselineReport() {
    final n = _totalTransportSamples;
    final lines = <String>[];

    if (n == 0) {
      lines.add('Transport mix (N=0): no data');
    } else {
      final percentages = _normalizedPercentages(n);
      final mixParts = kTransportBuckets
          .map((bucket) => '${percentages[bucket]}% $bucket')
          .join(', ');
      lines.add('Transport mix (N=$n): $mixParts');
    }

    final latency = latencyByTransport();
    final latencyParts = kTransportBuckets.map((bucket) {
      final median = latency[bucket]!.medianMs;
      return '$bucket ${median == null ? '-' : '${median}ms'}';
    }).join(', ');
    lines.add('Median latency: $latencyParts');

    final rungParts = kFallbackRungs
        .map((rung) => '$rung ${_rungCounts[rung]}')
        .join(', ');
    lines.add('Fallback rungs: $rungParts');

    final attemptParts = kSendAttemptLegs
        .map((leg) => '$leg ${_attemptCounts[leg]}/${_attemptFailureCounts[leg]}')
        .join(', ');
    lines.add('Send attempts (tried/failed): $attemptParts');

    final lan = _lanAvailability;
    lines.add(
      'LAN: discovery ${lan.discoveryActive ? 'active' : 'inactive'}, '
      '${lan.discoveredPeerCount} peers'
      '${lan.suspectedPermissionDenied ? ', perm: suspected-denied' : ''}',
    );

    lines.add(
      'Hole punch (attempt/success/fail): '
      '$_holePunchAttempts/$_holePunchSuccesses/$_holePunchFailures, '
      'relay->direct upgrades: $_relayToDirectUpgrades',
    );

    return lines.join('\n');
  }

  /// Integer percentages per bucket that sum to exactly 100 (for N > 0).
  ///
  /// Floor each share, then add the rounding remainder to the largest bucket.
  Map<String, int> _normalizedPercentages(int total) {
    final result = <String, int>{};
    var allocated = 0;
    for (final bucket in kTransportBuckets) {
      final count = _transportCounts[bucket] ?? 0;
      final pct = (count * 100) ~/ total;
      result[bucket] = pct;
      allocated += pct;
    }
    final remainder = 100 - allocated;
    if (remainder != 0) {
      var largestBucket = kTransportBuckets.first;
      var largestCount = -1;
      for (final bucket in kTransportBuckets) {
        final count = _transportCounts[bucket] ?? 0;
        if (count > largestCount) {
          largestCount = count;
          largestBucket = bucket;
        }
      }
      result[largestBucket] = (result[largestBucket] ?? 0) + remainder;
    }
    return result;
  }

  /// Clears all counters/samples (test convenience; also usable for a debug
  /// "reset" button). Resets the LAN snapshot to empty.
  @visibleForTesting
  void reset() {
    for (final bucket in kTransportBuckets) {
      _transportCounts[bucket] = 0;
      _latency[bucket]!.clear();
      _latencyWriteIndex[bucket] = 0;
    }
    for (final rung in kFallbackRungs) {
      _rungCounts[rung] = 0;
    }
    for (final leg in kSendAttemptLegs) {
      _attemptCounts[leg] = 0;
      _attemptFailureCounts[leg] = 0;
    }
    _totalTransportSamples = 0;
    _holePunchAttempts = 0;
    _holePunchSuccesses = 0;
    _holePunchFailures = 0;
    _relayToDirectUpgrades = 0;
    _lanAvailability = LanAvailabilitySnapshot.empty;
  }
}
