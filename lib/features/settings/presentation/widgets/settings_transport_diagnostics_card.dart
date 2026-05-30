import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';

/// Debug-only, read-only diagnostics card that renders the current session's
/// aggregate transport metrics from [TransportMetrics].
///
/// Privacy: this surface bypasses the flow-event sanitizer, so it renders ONLY
/// aggregate counters/ratios/latencies — never peer IDs, message content, or
/// per-conversation data. All values come from [TransportMetrics] getters, which
/// are aggregate-only by construction.
class SettingsTransportDiagnosticsCard extends StatefulWidget {
  final TransportMetrics metrics;

  const SettingsTransportDiagnosticsCard({super.key, required this.metrics});

  @override
  State<SettingsTransportDiagnosticsCard> createState() =>
      _SettingsTransportDiagnosticsCardState();
}

class _SettingsTransportDiagnosticsCardState
    extends State<SettingsTransportDiagnosticsCard> {
  // Snapshot of the metrics taken on init / refresh. Metrics are mutated
  // externally (send/receive paths), so we re-read on explicit refresh.
  late Map<String, int> _transportMix;
  late int _totalSamples;
  late Map<String, int> _rungs;
  late Map<String, TransportLatencyStats> _latency;
  late LanAvailabilitySnapshot _lan;
  late String _report;

  @override
  void initState() {
    super.initState();
    _readMetrics();
  }

  void _readMetrics() {
    _transportMix = widget.metrics.transportMix();
    _totalSamples = widget.metrics.totalTransportSamples;
    _rungs = widget.metrics.rungDistribution();
    _latency = widget.metrics.latencyByTransport();
    _lan = widget.metrics.lanAvailability;
    _report = widget.metrics.baselineReport();
  }

  void _refresh() {
    setState(_readMetrics);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'TRANSPORT DIAGNOSTICS (SESSION)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.88,
                color: Color.fromRGBO(255, 255, 255, 0.4),
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: const Color.fromRGBO(255, 255, 255, 0.08),
                  border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Session-scoped, aggregate-only transport census. '
                            'No identifiers leave the device.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Color.fromRGBO(255, 255, 255, 0.65),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          key: const ValueKey(
                            'settings-transport-debug-refresh',
                          ),
                          onTap: _refresh,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: const Color.fromRGBO(255, 255, 255, 0.08),
                              border: Border.all(
                                color: const Color.fromRGBO(
                                  255,
                                  255,
                                  255,
                                  0.12,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.refresh,
                              size: 16,
                              color: Color.fromRGBO(255, 255, 255, 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Transport mix
                    _SectionLabel('Transport mix (N=$_totalSamples)'),
                    const SizedBox(height: 6),
                    ...kTransportBuckets.map(
                      (bucket) => _MetricRow(
                        label: bucket,
                        value: '${_transportMix[bucket] ?? 0}',
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Fallback rungs
                    const _SectionLabel('Fallback rungs'),
                    const SizedBox(height: 6),
                    ...kFallbackRungs.map(
                      (rung) => _MetricRow(
                        label: rung,
                        value: '${_rungs[rung] ?? 0}',
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Latency per transport
                    const _SectionLabel('Latency (median / p95)'),
                    const SizedBox(height: 6),
                    ...kTransportBuckets.map((bucket) {
                      final stats =
                          _latency[bucket] ??
                          const TransportLatencyStats(
                            sampleCount: 0,
                            medianMs: null,
                            p95Ms: null,
                          );
                      final value = stats.sampleCount == 0
                          ? '-'
                          : '${stats.medianMs}ms / ${stats.p95Ms}ms'
                                ' (n=${stats.sampleCount})';
                      return _MetricRow(label: bucket, value: value);
                    }),

                    const SizedBox(height: 14),

                    // LAN availability
                    const _SectionLabel('LAN'),
                    const SizedBox(height: 6),
                    _MetricRow(
                      label: 'discovery',
                      value: _lan.discoveryActive ? 'active' : 'inactive',
                    ),
                    _MetricRow(
                      label: 'peers',
                      value: '${_lan.discoveredPeerCount}',
                    ),
                    // P4: heuristic only (zero peers for >=12s while discovery
                    // active) — never authoritative; iOS has no permission API.
                    _MetricRow(
                      label: 'permission',
                      value: _lan.suspectedPermissionDenied
                          ? 'suspected-denied'
                          : 'ok',
                    ),

                    const SizedBox(height: 14),

                    // Baseline report (copyable)
                    const _SectionLabel('Baseline report'),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color.fromRGBO(255, 255, 255, 0.04),
                        border: Border.all(
                          color: const Color.fromRGBO(255, 255, 255, 0.08),
                        ),
                      ),
                      child: SelectableText(
                        _report,
                        key: const ValueKey(
                          'settings-transport-debug-report',
                        ),
                        style: const TextStyle(
                          fontFamily: 'SF Mono',
                          fontFamilyFallback: ['Fira Code', 'monospace'],
                          fontSize: 11,
                          height: 1.5,
                          color: Color.fromRGBO(255, 255, 255, 0.8),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: _DebugActionButton(
                        buttonKey: const ValueKey(
                          'settings-transport-debug-refresh-button',
                        ),
                        label: 'Refresh',
                        color: const Color(0xFF14B8A6),
                        onTap: _refresh,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color.fromRGBO(255, 255, 255, 0.9),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'SF Mono',
              fontFamilyFallback: ['Fira Code', 'monospace'],
              fontSize: 11,
              color: Color.fromRGBO(255, 255, 255, 0.6),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'SF Mono',
              fontFamilyFallback: ['Fira Code', 'monospace'],
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color.fromRGBO(255, 255, 255, 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugActionButton extends StatelessWidget {
  final Key buttonKey;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DebugActionButton({
    required this.buttonKey,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
