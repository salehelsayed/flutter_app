import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../domain/call_video_quality_policy.dart';

/// Normalizes the pinned native SDK's microsecond timestamps and current
/// sender/transport feedback. No transport identifiers leave this boundary.
final class CallVideoQualityStatsSampler {
  double? _lastTimestamp;
  Map<String, (double, int)> _audio = {};
  static const _maximumGapUs = 2000000;

  CallVideoQualityFeedback sample(
    Iterable<webrtc.StatsReport> reports, {
    required bool videoSending,
    String? videoTrackId,
  }) {
    final values = reports.toList(growable: false);
    double? timestamp;
    for (final report in values) {
      final value = report.timestamp;
      if (value.isFinite &&
          value >= 0 &&
          (timestamp == null || value > timestamp)) {
        timestamp = value;
      }
    }
    if (timestamp == null ||
        (_lastTimestamp != null && timestamp <= _lastTimestamp!)) {
      return CallVideoQualityFeedback.unknown;
    }
    _lastTimestamp = timestamp;
    bool fresh(webrtc.StatsReport report) =>
        report.timestamp.isFinite &&
        report.timestamp >= 0 &&
        timestamp! - report.timestamp <= _maximumGapUs;
    final current = {for (final r in values.where(fresh)) r.id: r};
    final selected = <String>{};
    for (final report in current.values) {
      if (report.type != 'transport') continue;
      final id = report.values['selectedCandidatePairId'];
      if (id is String && id.isNotEmpty) selected.add(id);
    }
    final pair = selected.length == 1 ? current[selected.single] : null;
    final available =
        pair?.type == 'candidate-pair' && pair?.values['state'] == 'succeeded'
        ? _bitrate(pair!.values['availableOutgoingBitrate'])
        : null;

    final nextAudio = <String, (double, int)>{};
    var allAudioMeasured = true;
    var audioBits = 0;
    for (final report in current.values) {
      if (!_outbound(report, 'audio')) continue;
      final bytes = _integer(report.values['bytesSent']);
      if (bytes == null) {
        allAudioMeasured = false;
        continue;
      }
      nextAudio[report.id] = (report.timestamp, bytes);
      final previous = _audio[report.id];
      if (previous == null ||
          report.timestamp <= previous.$1 ||
          report.timestamp - previous.$1 > _maximumGapUs ||
          bytes < previous.$2) {
        allAudioMeasured = false;
        continue;
      }
      // Android getTimestampUs and iOS timestamp_us pass through the pinned SDK.
      audioBits +=
          ((bytes - previous.$2) *
                  8 *
                  1000000 /
                  (report.timestamp - previous.$1))
              .ceil();
    }
    _audio = nextAudio;
    final audio = allAudioMeasured && nextAudio.isNotEmpty ? audioBits : null;

    var limitation = CallVideoQualityLimitation.unknown;
    if (videoSending && videoTrackId != null) {
      final reasons = <CallVideoQualityLimitation>[];
      for (final report in current.values) {
        if (!_outbound(report, 'video')) continue;
        final source = current[report.values['mediaSourceId']];
        final track =
            report.values['trackIdentifier'] ??
            (source?.type == 'media-source'
                ? source?.values['trackIdentifier']
                : null);
        if (track != videoTrackId) continue;
        reasons.add(switch (report.values['qualityLimitationReason']) {
          'none' => CallVideoQualityLimitation.none,
          'bandwidth' => CallVideoQualityLimitation.bandwidth,
          'cpu' => CallVideoQualityLimitation.cpu,
          _ => CallVideoQualityLimitation.unknown,
        });
      }
      if (reasons.contains(CallVideoQualityLimitation.cpu)) {
        limitation = CallVideoQualityLimitation.cpu;
      } else if (reasons.contains(CallVideoQualityLimitation.bandwidth)) {
        limitation = CallVideoQualityLimitation.bandwidth;
      } else if (reasons.isNotEmpty &&
          reasons.every(
            (reason) => reason == CallVideoQualityLimitation.none,
          )) {
        limitation = CallVideoQualityLimitation.none;
      }
    } else if (!videoSending && available != null && audio != null) {
      // A paused camera has no fresh encoder feedback. Only fresh transport and
      // audio progress can qualify its conservative recovery window.
      limitation = CallVideoQualityLimitation.none;
    }
    return CallVideoQualityFeedback(
      limitation: limitation,
      availableOutgoingBitrateBps: available,
      audioBitrateBps: audio,
    );
  }

  static bool _outbound(webrtc.StatsReport report, String kind) =>
      report.type == 'outbound-rtp' &&
      report.values['isRemote'] != true &&
      report.values['active'] != false &&
      (report.values['kind'] ?? report.values['mediaType']) == kind;

  static int? _integer(Object? value) =>
      value is num &&
          value.isFinite &&
          value >= 0 &&
          value == value.truncateToDouble()
      ? value.toInt()
      : null;

  static int? _bitrate(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value.floor() : null;

  void reset() {
    _lastTimestamp = null;
    _audio = {};
  }
}
