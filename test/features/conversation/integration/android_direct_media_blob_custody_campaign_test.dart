import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_test/scripts/android_direct_media_blob_custody_campaign.dart';
import '../../../../integration_test/scripts/android_direct_media_blob_custody_device_action.dart';
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

  test('host retains bounded voice disposition before app restoration', () {
    for (final result in [
      'success',
      'invalidRecording',
      'uploadFailed',
      'uploadQueued',
      'sendFailed',
    ]) {
      for (final returnedMessage in [false, true]) {
        for (final uploadLeaseHeld in [false, true]) {
          expect(
            androidDirectMediaVoiceSendFailureDetails({
              'voiceSendResult': result,
              'voiceSendReturnedMessage': returnedMessage,
              'voiceSendUploadLeaseHeld': uploadLeaseHeld,
              'messageId': 'must-not-appear',
              'error': 'must-not-appear',
            }),
            '; voiceSendResult=$result; '
            'voiceSendReturnedMessage=$returnedMessage; '
            'voiceSendUploadLeaseHeld=$uploadLeaseHeld',
          );
        }
      }
    }
  });

  test('host excludes malformed or absent voice observation values', () {
    expect(androidDirectMediaVoiceSendFailureDetails({}), isEmpty);
    for (final invalid in <Map<String, Object?>>[
      {'voiceSendResult': 'sendFailed\nprivate-content'},
      {
        'voiceSendResult': 'sendFailed',
        'voiceSendReturnedMessage': 'private-content',
        'voiceSendUploadLeaseHeld': true,
      },
      {'voiceSendUploadLeaseHeld': false},
    ]) {
      expect(
        androidDirectMediaVoiceSendFailureDetails(invalid),
        '; voiceObservation=invalid',
      );
    }
  });

  test(
    'contact commands survive old pollers and complete in replacement processes',
    () async {
      final oldRunning = [true, true];
      final staged = [false, false];
      final completed = [false, false];
      final consumedByOldProcess = <int>[];
      AndroidDirectMediaContactEndpoint endpoint(int index) => (
        stopAndWait: () async {
          oldRunning[index] = false;
        },
        stage: () async {
          staged[index] = true;
          // A live poller consumes and deletes its command before awaiting P2P.
          if (oldRunning[index]) {
            staged[index] = false;
            consumedByOldProcess.add(index);
          }
        },
        start: () async {
          if (staged[index]) {
            staged[index] = false;
            completed[index] = true;
          }
        },
        waitForResult: () async {
          if (!completed[index]) {
            throw StateError('stale receipt from killed poller');
          }
        },
      );
      await exchangeAndroidDirectMediaContacts(
        sender: endpoint(0),
        receiver: endpoint(1),
      );
      expect(consumedByOldProcess, isEmpty);
      expect(completed, [true, true]);
      expect(staged, [false, false]);
    },
  );

  test(
    'failed process-stop verification leaves both contact commands unstaged',
    () async {
      final failure = StateError('receiver process still present');
      final staged = <int>[];
      final started = <int>[];
      AndroidDirectMediaContactEndpoint endpoint(int index) => (
        stopAndWait: () async {
          if (index == 1) throw failure;
        },
        stage: () async {
          staged.add(index);
        },
        start: () async {
          started.add(index);
        },
        waitForResult: () async {},
      );
      await expectLater(
        exchangeAndroidDirectMediaContacts(
          sender: endpoint(0),
          receiver: endpoint(1),
        ),
        throwsA(same(failure)),
      );
      expect(staged, isEmpty);
      expect(started, isEmpty);
    },
  );

  for (final oldActionFails in [false, true]) {
    test(
      'initial media handoff excludes old-process work (prompt failure: $oldActionFails)',
      () async {
        var oldRunning = true;
        var requestStaged = false;
        var oldEffects = 0;
        var replacementEffects = 0;
        await launchAndroidDirectMediaInitialAction(
          stopAndWait: () async {
            oldRunning = false;
          },
          stage: () async {
            requestStaged = true;
            if (oldRunning) {
              oldEffects++;
              // A prompt failure runs the old dispatcher's config cleanup.
              if (oldActionFails) requestStaged = false;
            }
          },
          start: () async {
            if (requestStaged) replacementEffects++;
          },
        );
        expect(requestStaged, isTrue);
        expect(oldEffects, 0);
        expect(replacementEffects, 1);
      },
    );
  }

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
