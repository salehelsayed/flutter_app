import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_notification_recovery_completion_criteria.dart';
import '../../tool/sims/artifact_evidence.dart';

const _physical = 'physical-393';
const _emulator = 'emulator-3930';
const _packageName = 'com.mknoon.app';
const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _timestamp = '2026-08-21T10:00:00.000Z';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('plan393-recovery-');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('TC-393-12 one controlled fixed-wake scenario is fail closed', () {
    final baselineJobs = parseAndroidCanonicalRecoveryJobIds(
      dump: _jobschedulerDump(<int>[12]),
      appPackage: _packageName,
    );
    final restartedJobs = parseAndroidCanonicalRecoveryJobIds(
      dump: _jobschedulerDump(<int>[12, 13]),
      appPackage: _packageName,
    );
    expect(baselineJobs, <int>{12});
    expect(restartedJobs.difference(baselineJobs), <int>{13});

    final valid = _fixture(directory);
    final accepted = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: valid.finalArtifact,
      expectedPhysicalDeviceId: _physical,
      expectedEmulatorDeviceId: _emulator,
      expectedApkSha256: _sha,
      expectedPackageName: _packageName,
    );
    expect(accepted.ok, isTrue, reason: accepted.detail);

    final mutations = <String, void Function(Map<String, dynamic>)>{
      'reused transition reaction': (raw) {
        raw['transitionB']['reactionIdSha256'] =
            raw['transitionA']['reactionIdSha256'];
      },
      'rich route substitution': (raw) {
        raw['transitionB']['routeAfter']['rich'] = 1;
        raw['transitionB']['richRouteDelta'] = 1;
      },
      'injected ingress substitution': (raw) {
        raw['transitionB']['productionFixedWakeIngress']['productionIngressInvoked'] =
            false;
      },
      'route left after unregister': (raw) {
        raw['cleanup']['absenceProbeRouteAfter']['opaque'] = 3;
      },
      'old assertion unmapped': (raw) {
        (raw['oldAssertionDisposition'] as List).removeLast();
      },
      'legacy relay token state': (raw) {
        raw['relay']['pushTokenState'] = 'absent';
      },
    };
    for (final entry in mutations.entries) {
      final fixture = _fixture(directory, suffix: entry.key.hashCode.abs());
      final raw = _read(fixture.rawArtifact);
      entry.value(raw);
      _write(fixture.rawArtifact, raw);
      final finalRoot = _read(fixture.finalArtifact);
      finalRoot['captureArtifactSha256'] = _digest(fixture.rawArtifact);
      _write(fixture.finalArtifact, finalRoot);
      final rejected = validateAndroidNotificationRecoveryCompletionArtifact(
        artifactFile: fixture.finalArtifact,
        expectedPhysicalDeviceId: _physical,
        expectedEmulatorDeviceId: _emulator,
        expectedApkSha256: _sha,
        expectedPackageName: _packageName,
      );
      expect(rejected.ok, isFalse, reason: entry.key);
    }

    final unrestored = _fixture(directory, suffix: 999);
    final finalRoot = _read(unrestored.finalArtifact);
    finalRoot['stateRestored'] = false;
    _write(unrestored.finalArtifact, finalRoot);
    expect(
      validateAndroidNotificationRecoveryCompletionArtifact(
        artifactFile: unrestored.finalArtifact,
      ).ok,
      isFalse,
    );
  });
}

String _jobschedulerDump(List<int> recoveryJobIds) {
  final jobs = <String>[
    for (final id in recoveryJobIds)
      '''
  JOB androidx.work.systemjobscheduler:u0a305/$id: hash$id #HeadlessCanonicalRecoveryWorker#@androidx.work.systemjobscheduler@com.mknoon.app/androidx.work.impl.background.systemjob.SystemJobService
    Source: uid=u0a305 user=0 pkg=com.mknoon.app
    JobInfo:
      Service: com.mknoon.app/androidx.work.impl.background.systemjob.SystemJobService
      Trace tag: HeadlessCanonicalRecoveryWorker
    Ready: ${id == 13 ? 'true' : 'false'}
''',
    '''
  JOB androidx.work.systemjobscheduler:u0a305/77: other #OtherWorker#@androidx.work.systemjobscheduler@com.mknoon.app/androidx.work.impl.background.systemjob.SystemJobService
    JobInfo:
      Service: com.mknoon.app/androidx.work.impl.background.systemjob.SystemJobService
''',
  ];
  return 'Registered 216 jobs:\n${jobs.join()}\nPending queue:\n  None\n';
}

final class _Fixture {
  const _Fixture({required this.rawArtifact, required this.finalArtifact});

  final File rawArtifact;
  final File finalArtifact;
}

_Fixture _fixture(Directory directory, {int suffix = 0}) {
  final prefix = 'f$suffix-';
  Map<String, Object?> ref(String name, [String contents = 'evidence']) {
    final file = File('${directory.path}/$prefix$name')
      ..writeAsStringSync('$contents\n', flush: true);
    final bytes = file.readAsBytesSync();
    return <String, Object?>{
      'path': file.uri.pathSegments.last,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
    };
  }

  Map<String, Object?> route(int opaque, int rich, String name) =>
      <String, Object?>{
        'opaque': opaque,
        'rich': rich,
        'evidence': ref('$name.metrics', 'process_start_time_seconds 1'),
      };

  Map<String, Object?> transition({
    required String lifecycle,
    required String digestChar,
    required int generation,
    required int beforeOpaque,
  }) {
    final value = <String, Object?>{
      'lifecycle': lifecycle,
      'targetMarkerSha256': _repeat(digestChar),
      'targetMessageIdSha256': _repeat(digestChar == 'b' ? 'c' : 'd'),
      'reactionIdSha256': _repeat(digestChar == 'b' ? 'e' : 'f'),
      'recoveryGeneration': generation,
      'routeBefore': route(beforeOpaque, 0, '$lifecycle-before'),
      'routeAfter': route(beforeOpaque + 1, 0, '$lifecycle-after'),
      'opaqueRouteDelta': 1,
      'richRouteDelta': 0,
      'productionFixedWakeIngress': <String, Object?>{
        'event': 'plan393_fixed_wake_ingress',
        'pid': 200 + generation,
        'generation': generation,
        'triggerKind': 'FIXED_WAKE',
        'genericMayHaveAlerted': false,
        'genericCardTag': 'mknoon_dropped_push_recovery',
        'genericCardId': 329,
        'genericCardRequestedSilent': true,
        'richFlutterFireDelegated': false,
        'productionIngressInvoked': true,
      },
      'genericCard': const <String, Object?>{
        'tag': 'mknoon_dropped_push_recovery',
        'id': 329,
        'observed': true,
        'requestedSilent': true,
      },
      'canonicalCard': <String, Object?>{
        'id': 700,
        'titleSha256': _repeat('1'),
        'bodySha256': _repeat('2'),
        'producer': 'direct_reaction',
        'sourceCustody': 'SQL_READY',
        'presentationOwner': 'INBOX_RECONCILER',
        'effectPhase': 'SETTLED',
        'settlement': const <String, Object?>{
          'sourceCustody': 'SQL_READY',
          'presentationOwner': 'INBOX_RECONCILER',
          'effectPhase': 'SETTLED',
          'presentationState': 'OS_POSTED',
        },
        'requestedSilent': false,
      },
      'genericCardRetiredAfterCanonical': true,
      'exactMarkerAcknowledgement': <String, Object?>{
        'event': 'plan393_recovery_generation_acknowledged',
        'pid': lifecycle == 'killed' ? 302 : 202,
        'generation': generation,
        'owner': lifecycle == 'killed' ? 'headless' : 'warm',
        'genericCardTag': 'mknoon_dropped_push_recovery',
        'genericCardId': 329,
        'genericCardRetired': true,
      },
      'duplicateCanonicalShowCount': 0,
      'requestedToneCount': 1,
      'richFlutterFireCallbackCount': 0,
      'notificationSnapshots': <Map<String, Object?>>[
        ref('$lifecycle-notifications-1.json'),
        ref('$lifecycle-notifications-2.json'),
      ],
      'runtimeEvidence': <Map<String, Object?>>[
        ref('$lifecycle-runtime-1.jsonl'),
        ref('$lifecycle-runtime-2.jsonl'),
      ],
      'relayJournal': ref('$lifecycle-relay.log'),
    };
    if (lifecycle == 'alive_backgrounded') {
      value['exactChatActivation'] = ref('transition-a-activation.json');
    } else {
      value.addAll(<String, Object?>{
        'processAbsentBeforeSend': true,
        'barrierArmReceipt': <String, Object?>{
          'status': 'PASS',
          'phase': 'arm-fixed-wake',
          'processDeathBarrierArmed': true,
          'productionIngressInvoked': false,
          'pendingGenerationBefore': null,
          'pendingGenerationAfter': null,
          'mainActivityLaunchCount': 0,
          'receiptSha256': _repeat('3'),
        },
        'firstWorkerPid': 301,
        'resumedWorkerPid': 302,
        'runAttemptCount': 1,
        'terminalOutcome': 'SUCCESS',
        'jobSchedulerBaseline': ref('jobs-baseline.txt'),
        'jobSchedulerAudit': ref('jobs-audit.txt'),
      });
    }
    return value;
  }

  final raw = <String, Object?>{
    'schema': androidNotificationRecoveryCompletionRawSchema,
    'version': 1,
    'scenario': androidNotificationRecoveryCompletionScenarioId,
    'status': 'passed',
    'recordedAt': _timestamp,
    'buildProfile': androidNotificationRecoveryCompletionBuildProfile,
    'buildCapability': androidNotificationRecoveryCompletionBuildCapability,
    'preparedArtifactSha256': _sha,
    'appPackage': _packageName,
    'topology': const <String, Object?>{
      'sender': <String, Object?>{
        'deviceId': _physical,
        'kind': 'physical',
        'role': 'sender',
      },
      'receiver': <String, Object?>{
        'deviceId': _emulator,
        'kind': 'emulator',
        'role': 'receiver',
      },
    },
    'relay': <String, Object?>{
      'revision': 'relay-server v1.10.0',
      'sha256': _repeat('4'),
      'selectedRouteCounter': 'relay_push_route_selected_total',
      'executionBoundary': 'ephemeral_production_redis_fixture',
      'backend': 'redis',
      'pushTokenState': 'encrypted',
      'wakeOutcomeLedger': 'redis',
      'provider': 'fcm',
    },
    'transitionA': transition(
      lifecycle: 'alive_backgrounded',
      digestChar: 'b',
      generation: 10,
      beforeOpaque: 5,
    ),
    'transitionB': transition(
      lifecycle: 'killed',
      digestChar: 'a',
      generation: 11,
      beforeOpaque: 6,
    ),
    'cleanup': <String, Object?>{
      'authenticatedRouteUnregister': true,
      'unregisterReceipt': ref('unregister.json'),
      'routeAbsentReadback': true,
      'absenceProbeReactionIdSha256': _repeat('5'),
      'absenceProbeRouteBefore': route(7, 0, 'cleanup-before'),
      'absenceProbeRouteAfter': route(7, 0, 'cleanup-after'),
      'absenceProbeRelayJournal': ref('cleanup-relay.log'),
      'postCampaignAppCardCount': 0,
      'localStateRestorationOwnedByParent': true,
    },
    'automation': const <String, Object?>{
      'manualUserTaps': 0,
      'notificationCardTaps': 0,
      'childBuildCount': 0,
      'mainActivityLaunchesDuringKilledRecovery': 0,
      'productionIngressInjectionCount': 0,
      'statePreparedByParent': true,
    },
    'assertions': androidNotificationRecoveryCompletionAssertions,
    'oldAssertionDisposition': androidNotificationRecoveryDisposition,
    'redaction': const <String, Object?>{
      'providerTokensPersisted': false,
      'privateKeysPersisted': false,
      'rawPeerIdsPersisted': false,
      'messagePlaintextPersisted': false,
    },
  };
  final rawFile = File('${directory.path}/${prefix}raw.json');
  _write(rawFile, raw);
  final finalEvidence = writeSimsArtifactEvidenceSync(
    directory: directory,
    capabilityId: androidNotificationRecoveryCompletionCapabilityId,
    validatorIds: const <String>[
      androidNotificationRecoveryCompletionValidator,
    ],
    payload: <String, Object?>{
      'status': 'passed',
      'recordedAt': _timestamp,
      'campaignSchema': androidNotificationRecoveryCompletionCampaignSchema,
      'scenarioIds': const <String>[
        androidNotificationRecoveryCompletionScenarioId,
      ],
      'criteria': androidNotificationRecoveryCompletionAssertions,
      'targetIds': const <String>[_physical, _emulator],
      'targetKinds': const <String>['physical', 'emulator'],
      'buildProfile': androidNotificationRecoveryCompletionBuildProfile,
      'buildCapability': androidNotificationRecoveryCompletionBuildCapability,
      'preparedArtifactEnvironment':
          androidNotificationRecoveryCompletionArtifactEnvironment,
      'preparedArtifactSha256': _sha,
      'captureRoot': directory.absolute.path,
      'captureArtifactPath': rawFile.absolute.path,
      'captureArtifactSha256': _digest(rawFile),
      'childBuildCount': 0,
      'manualTaps': 0,
      'notificationCardTaps': 0,
      'mainActivityLaunchesDuringKilledRecovery': 0,
      'authenticatedRouteUnregister': true,
      'routeAbsentReadback': true,
      'stateRestored': true,
      'postRestoreAppCardCount': 0,
    },
  );
  return _Fixture(
    rawArtifact: rawFile,
    finalArtifact: File(finalEvidence.path),
  );
}

Map<String, dynamic> _read(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();

void _write(File file, Map<String, Object?> value) {
  file.writeAsStringSync('${jsonEncode(value)}\n', flush: true);
}

String _digest(File file) => sha256.convert(file.readAsBytesSync()).toString();

String _repeat(String value) => List<String>.filled(64, value).join();
