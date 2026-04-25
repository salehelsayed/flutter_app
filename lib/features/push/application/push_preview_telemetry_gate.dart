const pushNseDecryptOkEvent = 'PUSH_NSE_DECRYPT_OK';
const pushNseDecryptFailEvent = 'PUSH_NSE_DECRYPT_FAIL';
const pushNseTimeoutEvent = 'PUSH_NSE_TIMEOUT';
const pushAndroidDataDecryptOkEvent = 'PUSH_ANDROID_DATA_DECRYPT_OK';
const pushAndroidDataDecryptFailEvent = 'PUSH_ANDROID_DATA_DECRYPT_FAIL';

const pushPreviewDegradeRateBlockThreshold = 0.03;

const pushPreviewDegradeRateExcludedReasons = {
  'client_pre_decrypt',
  'keychain_locked',
  'migration_pending',
};

const _denominatorEvents = {
  pushNseDecryptOkEvent,
  pushNseDecryptFailEvent,
  pushNseTimeoutEvent,
  pushAndroidDataDecryptOkEvent,
  pushAndroidDataDecryptFailEvent,
};

const _numeratorEvents = {
  pushNseDecryptFailEvent,
  pushNseTimeoutEvent,
  pushAndroidDataDecryptFailEvent,
};

class PushPreviewTelemetryEvent {
  final String event;
  final String? reason;

  const PushPreviewTelemetryEvent(this.event, {this.reason});

  factory PushPreviewTelemetryEvent.fromFlowPayload(
    Map<String, dynamic> payload,
  ) {
    final details = payload['details'];
    return PushPreviewTelemetryEvent(
      payload['event']?.toString() ?? '',
      reason: details is Map ? details['reason']?.toString() : null,
    );
  }
}

class PushPreviewDegradeRateResult {
  final int numerator;
  final int denominator;
  final double blockThreshold;

  const PushPreviewDegradeRateResult({
    required this.numerator,
    required this.denominator,
    this.blockThreshold = pushPreviewDegradeRateBlockThreshold,
  });

  double get rate {
    if (denominator == 0) {
      return 0;
    }
    return numerator / denominator;
  }

  bool get blocksRelease => denominator > 0 && rate > blockThreshold;
}

PushPreviewDegradeRateResult calculatePushPreviewDegradeRate(
  Iterable<PushPreviewTelemetryEvent> events, {
  Set<String> excludedReasons = pushPreviewDegradeRateExcludedReasons,
  double blockThreshold = pushPreviewDegradeRateBlockThreshold,
}) {
  var numerator = 0;
  var denominator = 0;

  for (final event in events) {
    if (!_denominatorEvents.contains(event.event)) {
      continue;
    }
    if (event.reason != null && excludedReasons.contains(event.reason)) {
      continue;
    }

    denominator += 1;
    if (_numeratorEvents.contains(event.event)) {
      numerator += 1;
    }
  }

  return PushPreviewDegradeRateResult(
    numerator: numerator,
    denominator: denominator,
    blockThreshold: blockThreshold,
  );
}
