import 'package:flutter_app/features/push/application/push_preview_telemetry_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculatePushPreviewDegradeRate', () {
    test('counts real decrypt failures across iOS and Android', () {
      final result = calculatePushPreviewDegradeRate([
        const PushPreviewTelemetryEvent(pushNseDecryptOkEvent),
        const PushPreviewTelemetryEvent(pushAndroidDataDecryptOkEvent),
        const PushPreviewTelemetryEvent(
          pushNseDecryptFailEvent,
          reason: 'corrupt_payload',
        ),
        const PushPreviewTelemetryEvent(
          pushAndroidDataDecryptFailEvent,
          reason: 'missing_key',
        ),
        const PushPreviewTelemetryEvent(pushNseTimeoutEvent, reason: 'timeout'),
      ]);

      expect(result.numerator, 3);
      expect(result.denominator, 5);
      expect(result.rate, 0.6);
      expect(result.blocksRelease, isTrue);
    });

    test(
      'excludes expected rollout fallback reasons from numerator and denominator',
      () {
        final result = calculatePushPreviewDegradeRate([
          const PushPreviewTelemetryEvent(pushNseDecryptOkEvent),
          const PushPreviewTelemetryEvent(
            pushNseDecryptFailEvent,
            reason: 'client_pre_decrypt',
          ),
          const PushPreviewTelemetryEvent(
            pushAndroidDataDecryptFailEvent,
            reason: 'keychain_locked',
          ),
          const PushPreviewTelemetryEvent(
            pushNseTimeoutEvent,
            reason: 'migration_pending',
          ),
          const PushPreviewTelemetryEvent(
            pushAndroidDataDecryptFailEvent,
            reason: 'decrypt_error',
          ),
        ]);

        expect(result.numerator, 1);
        expect(result.denominator, 2);
        expect(result.rate, 0.5);
      },
    );

    test('applies the 3 percent block threshold', () {
      final result = calculatePushPreviewDegradeRate([
        for (var i = 0; i < 97; i++)
          const PushPreviewTelemetryEvent(pushNseDecryptOkEvent),
        for (var i = 0; i < 3; i++)
          const PushPreviewTelemetryEvent(
            pushAndroidDataDecryptFailEvent,
            reason: 'decrypt_error',
          ),
      ]);

      expect(result.rate, 0.03);
      expect(result.blocksRelease, isFalse);

      final blocked = calculatePushPreviewDegradeRate([
        for (var i = 0; i < 96; i++)
          const PushPreviewTelemetryEvent(pushNseDecryptOkEvent),
        for (var i = 0; i < 4; i++)
          const PushPreviewTelemetryEvent(
            pushAndroidDataDecryptFailEvent,
            reason: 'decrypt_error',
          ),
      ]);

      expect(blocked.rate, 0.04);
      expect(blocked.blocksRelease, isTrue);
    });

    test(
      'builds events from flow payloads without depending on extra metadata',
      () {
        final result = calculatePushPreviewDegradeRate([
          PushPreviewTelemetryEvent.fromFlowPayload({
            'event': pushAndroidDataDecryptFailEvent,
            'details': {'kind': 'chat', 'reason': 'decrypt_error'},
          }),
          PushPreviewTelemetryEvent.fromFlowPayload({
            'event': pushAndroidDataDecryptOkEvent,
            'details': {'kind': 'group'},
          }),
        ]);

        expect(result.numerator, 1);
        expect(result.denominator, 2);
      },
    );
  });
}
