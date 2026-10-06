import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_sound_descriptor.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

SimsRuntimeInvocation invocation({
  String scenario = notificationSoundJourney,
  String role = 'alice',
  String fixture = 'run',
}) => SimsRuntimeInvocation(
  schema: simsRuntimeConfigSchema,
  profileId: 'android.e2e.production',
  scenarioId: scenario,
  role: role,
  runId: 'run',
  nonce: 'nonce',
  values: {'fixtureId': fixture},
);
void main() {
  test(
    'nine exact encrypted projection fixtures preserve original dimensions',
    () {
      final claims = ProductionSoundDescriptorClaims();
      for (var n = 5; n <= 13; n++) {
        final a = claims.claim(invocation(), 'S$n');
        expect(a.messageId, 'notification-run-s$n-message');
        expect(a.size, 4096);
        expect(a.contentHash, '${n - 4}' * 64);
        expect(a.encryptionScheme, 'blob_aes_256_gcm_v1');
        expect(a.localPath, 'media/notification_sound/s$n');
        expect(a.width, a.mediaType == 'audio' ? null : 640);
        expect(a.durationMs, a.mediaType == 'image' ? null : 3200);
        expect(() => claims.claim(invocation(), 'S$n'), throwsStateError);
      }
    },
  );
  for (final bad in [
    invocation(scenario: notificationOpenJourney),
    invocation(role: 'bob'),
    invocation(fixture: 'other'),
  ]) {
    test(
      'rejects foreign descriptor claim ${bad.scenarioId}/${bad.role}/${bad.values}',
      () {
        expect(
          () => ProductionSoundDescriptorClaims().claim(bad, 'S5'),
          throwsStateError,
        );
      },
    );
  }
  for (final id in ['S1', 'S4', 'S14', 'S05', 's5', '5', 'S5.0']) {
    test('rejects unsupported descriptor $id', () {
      expect(
        () => ProductionSoundDescriptorClaims().claim(invocation(), id),
        throwsStateError,
      );
    });
  }
}
