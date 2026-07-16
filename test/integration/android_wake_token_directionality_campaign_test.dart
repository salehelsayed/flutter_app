import 'dart:io';

import 'package:flutter_app/core/debug/wake_token_directionality_e2e.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_wake_token_directionality_campaign.dart';
import '../../tool/sims/device_criteria.dart';

const _artifactDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _wakeDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, Object?> _issuer() => <String, Object?>{
  'schema': wakeTokenEndpointResultSchema,
  'scenario': wakeTokenDirectionalityScenarioId,
  'buildProfile': wakeTokenDirectionalityProfileId,
  'role': wakeTokenIssuerRole,
  'stepId': wakeTokenIssuerStepId('run-wake-1'),
  'runId': 'run-wake-1',
  'nonce': 'issuer-nonce-1',
  'status': 'complete',
  'success': true,
  'registeredTokenSha256': _wakeDigest,
  'registerRelayAccepted': true,
  'registeredMemberCount': 1,
};

Map<String, Object?> _presenter() => <String, Object?>{
  'schema': wakeTokenEndpointResultSchema,
  'scenario': wakeTokenDirectionalityScenarioId,
  'buildProfile': wakeTokenDirectionalityProfileId,
  'role': wakeTokenPresenterRole,
  'stepId': wakeTokenPresenterStepId('run-wake-1'),
  'runId': 'run-wake-1',
  'nonce': 'presenter-nonce-1',
  'status': 'complete',
  'success': true,
  'storedTokenSha256': _wakeDigest,
  'attachedTokenSha256': _wakeDigest,
  'receivedStorePersisted': true,
  'inboxStoreAccepted': true,
  'inboxStoreStatus': 'stored',
};

Map<String, Object?> _aggregate({
  Map<String, Object?>? issuer,
  Map<String, Object?>? presenter,
}) => aggregateAndroidWakeTokenDirectionalityEvidence(
  issuerEndpoint: issuer ?? _issuer(),
  presenterEndpoint: presenter ?? _presenter(),
  runId: 'run-wake-1',
  issuerNonce: 'issuer-nonce-1',
  presenterNonce: 'presenter-nonce-1',
  artifactSha256: _artifactDigest,
  physicalDeviceId: 'pixel-physical',
  emulatorDeviceId: 'emulator-5554',
);

void main() {
  test('binds three independent matching hashes into passing evidence', () {
    final proof = _aggregate();

    expect(validateWakeTokenArtifact(proof).ok, isTrue);
    expect(proof['registeredTokenSha256'], _wakeDigest);
    expect(proof['storedTokenSha256'], _wakeDigest);
    expect(proof['attachedTokenSha256'], _wakeDigest);
    expect(proof['childFlutterBuilds'], 0);
  });

  test('rejects a stale endpoint tuple or direction mismatch', () {
    final stale = _issuer()..['nonce'] = 'stale-nonce';
    expect(() => _aggregate(issuer: stale), throwsFormatException);

    final mismatch = _presenter()..['attachedTokenSha256'] = _artifactDigest;
    expect(() => _aggregate(presenter: mismatch), throwsFormatException);
  });

  test('rejects secret-bearing endpoint fields recursively', () {
    for (final forbidden in <String>['rawToken', 'secret', 'wakeToken']) {
      final endpoint = _presenter()..[forbidden] = 'must-not-cross-host';
      expect(() => _aggregate(presenter: endpoint), throwsFormatException);
    }
  });

  test('host campaign uses the guarded central APK and never builds an app', () {
    final source = File(
      'integration_test/scripts/android_wake_token_directionality_campaign.dart',
    ).readAsStringSync();

    expect(source, contains('stateGuard.prepareFreshInstall('));
    expect(source, contains('artifact: artifact'));
    expect(source, contains('stateGuard.restoreAll()'));
    expect(source, isNot(contains("'pm', 'clear'")));
    expect(source, contains('wakeTokenDirectionalityProfileId'));
    expect(source, isNot(contains('flutter build')));
    expect(source, isNot(contains('flutter drive')));
  });
}
