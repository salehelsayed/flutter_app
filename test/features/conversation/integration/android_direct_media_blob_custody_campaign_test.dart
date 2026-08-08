import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_test/scripts/android_direct_media_blob_custody_campaign.dart';
import '../../../../integration_test/support/android_direct_media_blob_custody_evidence.dart';

const String _ciphertextSha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _fixtureIdentitySha256 =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _plaintextSha256 =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

void main() {
  late Directory temporary;
  late File artifact;
  late Map<String, String> environment;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync(
      'plan347_android_campaign_',
    );
    artifact = File('${temporary.path}/app-debug.apk')
      ..writeAsBytesSync(<int>[1, 2, 3, 4], flush: true);
    environment = <String, String>{
      'SIMS_ARTIFACT_PROFILE_ID': androidDirectMediaBlobCustodyBuildProfileId,
      'SIMS_PROOF_DIRECTORY': '${temporary.path}/proofs',
      'MKNOON_RELAY_ADDRESSES': '/ip4/192.0.2.10/tcp/40123/p2p/12D3KooWFixture',
      'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256':
          _fixtureIdentitySha256,
      'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_PROBE_URL':
          'http://192.0.2.10:40124/${'c' * 64}',
    };
  });

  tearDown(() {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  test('TC-347-09 exact hash-only evidence accepts the Android-pair proof', () {
    final validation = validateAndroidDirectMediaBlobCustodyEvidence(
      _validEvidence(),
    );
    expect(validation.ok, isTrue, reason: validation.detail);
  });

  test(
    'TC-347-09 rejects divergent bytes, false outcomes, and secret fields',
    () {
      final mutations = <Map<String, Object?>>[
        <String, Object?>{
          ..._validEvidence(),
          'receiverCiphertextSha256':
              'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        },
        <String, Object?>{..._validEvidence(), 'senderRestartObserved': false},
        <String, Object?>{
          ..._validEvidence(),
          'receiverReopenPlaintextSha256':
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        },
        <String, Object?>{..._validEvidence(), 'attachmentCount': 0},
        <String, Object?>{
          ..._validEvidence(),
          'ciphertextPath': '/data/user/0/private/blob',
        },
        <String, Object?>{
          ..._validEvidence(),
          'fixtureIdentitySha256': 'relay-peer-id',
        },
      ];

      for (final mutation in mutations) {
        expect(
          validateAndroidDirectMediaBlobCustodyEvidence(mutation).ok,
          isFalse,
          reason: '$mutation',
        );
      }
    },
  );

  test(
    'TC-347-09 injected device action writes one validator-bound durable proof',
    () async {
      var calls = 0;
      final result = await runAndroidDirectMediaBlobCustodyCampaign(
        devices: const <String>['pixel-usb', 'emulator-5554'],
        artifactPath: artifact.path,
        environment: environment,
        deviceDriver: (context) async {
          calls += 1;
          expect(context.physicalDeviceId, 'pixel-usb');
          expect(context.emulatorDeviceId, 'emulator-5554');
          expect(context.fixtureIdentitySha256, _fixtureIdentitySha256);
          expect(context.relayMultiaddr, environment['MKNOON_RELAY_ADDRESSES']);
          expect(
            context.fixtureProbeUrl,
            environment['MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_PROBE_URL'],
          );
          expect(context.artifact.path, artifact.absolute.path);
          return _validEvidence();
        },
      );

      expect(calls, 1);
      expect(result.processExitCode, 0);
      expect(result.json['status'], 'PASS');
      expect(result.json['assertionsAttempted'], 4);
      final envelope = result.json['artifactEvidence']! as Map<String, Object?>;
      final durable = jsonDecode(
        File(envelope['path']! as String).readAsStringSync(),
      );
      expect(durable, isA<Map>());
      final validation = validateAndroidDirectMediaBlobCustodyDurableArtifact(
        (durable! as Map).map<String, Object?>(
          (key, value) => MapEntry('$key', value),
        ),
      );
      expect(validation.ok, isTrue, reason: validation.detail);
    },
  );

  test(
    'TC-347-09 typed app-action prerequisite remains BLOCKED and cannot forge PASS',
    () async {
      final result = await runAndroidDirectMediaBlobCustodyCampaign(
        devices: const <String>['pixel-usb', 'emulator-5554'],
        artifactPath: artifact.path,
        environment: environment,
        deviceDriver: (_) async =>
            throw const AndroidDirectMediaBlobCustodyCampaignBlocked(
              'missingDriver',
              'test app action is unavailable',
            ),
      );

      expect(result.processExitCode, 78);
      expect(result.json['status'], 'BLOCKED');
      expect(result.json['blocker'], 'missingDriver');
      expect(
        Directory(environment['SIMS_PROOF_DIRECTORY']!).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'TC-347-09 wrong profile fails before the injected device action',
    () async {
      var called = false;
      final result = await runAndroidDirectMediaBlobCustodyCampaign(
        devices: const <String>['pixel-usb', 'emulator-5554'],
        artifactPath: artifact.path,
        environment: <String, String>{
          ...environment,
          'SIMS_ARTIFACT_PROFILE_ID': 'android.e2e.main',
        },
        deviceDriver: (_) async {
          called = true;
          return _validEvidence();
        },
      );

      expect(called, isFalse);
      expect(result.processExitCode, 78);
      expect(result.json['blocker'], 'missingArtifact');
    },
  );
}

Map<String, Object?> _validEvidence() => <String, Object?>{
  'schemaVersion': androidDirectMediaBlobCustodyEvidenceSchemaVersion,
  'scenarioId': androidDirectMediaBlobCustodyScenarioId,
  'senderRestartObserved': true,
  'attachmentCount': 1,
  'preparedCiphertextSha256': _ciphertextSha256,
  'reopenedCiphertextSha256': _ciphertextSha256,
  'receiverCiphertextSha256': _ciphertextSha256,
  'receiverReopenSha256': _ciphertextSha256,
  'receiverPlaintextSha256': _plaintextSha256,
  'receiverReopenPlaintextSha256': _plaintextSha256,
  'strictCommitmentVerified': true,
  'envelopeExpiryWithinBlobBound': true,
  'ackSourcePinned': true,
  'relayProtectedAbsentAfterAck': true,
  'fixtureIdentitySha256': _fixtureIdentitySha256,
};
