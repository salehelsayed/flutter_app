import 'dart:async';

import 'package:flutter_app/core/notifications/automatic_recovery_notification_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 12, 9, 50);
  const wire =
      '{"type":"chat_message","version":"2","id":"original",'
      '"senderPeerId":"sender","encrypted":{"kem":"k","ciphertext":"bytes","nonce":"n"}}';

  test('only automatic initial messages older than 24 hours are quiet', () {
    for (final age in [
      const Duration(hours: 23),
      const Duration(hours: 24),
      const Duration(hours: 24, microseconds: 1),
      const Duration(days: 3),
    ]) {
      for (final manual in [false, true]) {
        final quiet = runWithAutomaticRecoveryNotificationPolicy(
          originalTimestamp: now.subtract(age).toIso8601String(),
          now: now,
          manualRetry: manual,
          action: () => quietRecoveryForEnvelope(wire),
        );
        expect(quiet, !manual && age > const Duration(hours: 24));
      }
    }
    expect(quietRecoveryForEnvelope(wire), isFalse);
  });

  test('invalid and future original timestamps do not fabricate old age', () {
    for (final timestamp in [
      'invalid',
      now.add(const Duration(days: 1)).toIso8601String(),
    ]) {
      expect(
        runWithAutomaticRecoveryNotificationPolicy(
          originalTimestamp: timestamp,
          now: now,
          action: () => quietRecoveryForEnvelope(wire),
        ),
        isFalse,
      );
    }
  });

  test(
    'scope excludes edits and controls and survives awaits without leaking',
    () async {
      final old = now.subtract(const Duration(days: 3)).toIso8601String();
      final gate = Completer<void>();
      final quietFuture = runWithAutomaticRecoveryNotificationPolicy(
        originalTimestamp: old,
        now: now,
        action: () async {
          await gate.future;
          expect(quietRecoveryForEnvelope(wire), isTrue);
          expect(
            quietRecoveryForEnvelope(
              wire.replaceFirst('"id":', '"eventId":"edit","id":'),
            ),
            isFalse,
          );
          expect(quietRecoveryForEnvelope('{"type":"call_invite"}'), isFalse);
          await runWithAutomaticRecoveryNotificationPolicy(
            originalTimestamp: old,
            now: now,
            manualRetry: true,
            action: () async {
              await Future<void>.value();
              expect(quietRecoveryForEnvelope(wire), isFalse);
            },
          );
          expect(quietRecoveryForEnvelope(wire), isTrue);
        },
      );
      expect(quietRecoveryForEnvelope(wire), isFalse);
      gate.complete();
      await quietFuture;
      expect(quietRecoveryForEnvelope(wire), isFalse);
    },
  );
}
