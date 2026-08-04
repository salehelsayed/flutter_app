import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_notification_recovery_completion_criteria.dart';
import '../../tool/sims/artifact_evidence.dart';

const _packageName = 'com.mknoon.app';
const _timestamp = '2026-08-03T10:00:00.000Z';
const _apkSha256 =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('plan331-validator-');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('accepts only the complete two-role content-addressed campaign', () {
    final artifact = _buildArtifact(directory);

    final validation = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: artifact,
      expectedApkSha256: _apkSha256,
      expectedPackageName: _packageName,
    );

    expect(validation.ok, isTrue, reason: validation.detail);
  });

  test('rejects forbidden process control even after digest recomputation', () {
    final artifact = _buildArtifact(directory);
    final aggregate = _readObject(artifact);
    final scenarios = aggregate['scenarios']! as List<dynamic>;
    final headless = scenarios.cast<Map<String, dynamic>>().firstWhere(
      (scenario) => scenario['id'] == 'headless_direct_group_recovery',
    );
    final evidence = headless['evidence']! as Map<String, dynamic>;
    final commandRef = evidence['commandJournal']! as Map<String, dynamic>;
    final commandFile = File('${directory.path}/${commandRef['path']}');
    final journal = _readObject(commandFile);
    (journal['commands']! as List<dynamic>).add(<String, Object?>{
      'phase': 'termination',
      'device': headless['receiverDeviceId'],
      'args': <String>['shell', 'am', 'force-stop', _packageName],
      'exitCode': 0,
      'stdoutEmpty': true,
      'capturedAt': _timestamp,
    });
    _rewriteEvidence(commandFile, journal, commandRef);
    _rewriteJson(artifact, aggregate);

    final validation = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: artifact,
    );

    expect(validation.ok, isFalse);
    expect(validation.detail, contains('forbidden process stop/card tap'));
  });

  test('rejects relabeling synthetic identity mutation as ordinary relay', () {
    final artifact = _buildArtifact(directory);
    final aggregate = _readObject(artifact);
    final scenarios = aggregate['scenarios']! as List<dynamic>;
    final synthetic = scenarios.cast<Map<String, dynamic>>().firstWhere(
      (scenario) => scenario['id'] == 'synthetic_outer_id_removal',
    );
    final evidence = synthetic['evidence']! as Map<String, dynamic>;
    final receiptRef = evidence['receipt']! as Map<String, dynamic>;
    final receiptFile = File('${directory.path}/${receiptRef['path']}');
    final receipt = _readObject(receiptFile);
    (receipt['facts']! as Map<String, dynamic>)['ordinaryRelayClaim'] = true;
    _rewriteEvidence(receiptFile, receipt, receiptRef);
    _rewriteJson(artifact, aggregate);

    final validation = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: artifact,
    );

    expect(validation.ok, isFalse);
    expect(validation.detail, contains('ordinaryRelayClaim'));
  });

  test('rejects a stale receipt nonce against the captured host broadcast', () {
    final artifact = _buildArtifact(directory);
    final aggregate = _readObject(artifact);
    final scenarios = aggregate['scenarios']! as List<dynamic>;
    final scenario = scenarios.cast<Map<String, dynamic>>().first;
    final evidence = scenario['evidence']! as Map<String, dynamic>;
    final receiptRef = evidence['receipt']! as Map<String, dynamic>;
    final receiptFile = File('${directory.path}/${receiptRef['path']}');
    final receipt = _readObject(receiptFile);
    receipt['nonce'] = 'nonce-from-an-older-run';
    _rewriteEvidence(receiptFile, receipt, receiptRef);
    _rewriteJson(artifact, aggregate);

    final validation = validateAndroidNotificationRecoveryCompletionArtifact(
      artifactFile: artifact,
    );

    expect(validation.ok, isFalse);
    expect(validation.detail, contains('recovery broadcast'));
  });
}

File _buildArtifact(Directory directory) {
  final scenarios = <Map<String, Object?>>[];
  for (final receiver in const <String>[
    plan331PhysicalAndroidDeviceId,
    plan331AndroidEmulatorDeviceId,
  ]) {
    final sender = receiver == plan331PhysicalAndroidDeviceId
        ? plan331AndroidEmulatorDeviceId
        : plan331PhysicalAndroidDeviceId;
    for (final scenarioId in androidNotificationRecoveryCompletionScenarioIds) {
      final runId =
          'run-${scenarioId.replaceAll('_', '-')}-${receiver.replaceAll(':', '-')}';
      final nonce = 'nonce-$scenarioId';
      final stem = '${receiver.replaceAll(':', '_')}-$scenarioId';
      final receipt = <String, Object?>{
        'schema': androidNotificationRecoveryCompletionReceiptSchema,
        'scenarioId': scenarioId,
        'runId': runId,
        'nonce': nonce,
        'status': 'passed',
        'receiverDeviceId': receiver,
        'senderDeviceId': sender,
        'facts': _facts(scenarioId),
      };
      final evidence = <String, Object?>{
        'receipt': _writeEvidence(
          directory,
          '$stem-receipt.json',
          jsonEncode(receipt),
        ),
        'flowLog': _writeEvidence(
          directory,
          '$stem-flow.log',
          '$runId\n${_flow(scenarioId)}',
        ),
        'notificationDump': _writeEvidence(
          directory,
          '$stem-notification.txt',
          'NotificationRecord pkg=$_packageName android.messages '
              'number=7 mNumber=7',
        ),
        'activityDump': _writeEvidence(
          directory,
          '$stem-activity.txt',
          'mResumedActivity: launcher/.HomeActivity',
        ),
        'relayJournal': _writeEvidence(
          directory,
          '$stem-relay.log',
          scenarioId == 'synthetic_outer_id_removal'
              ? 'test-only mutation has no ordinary relay claim'
              : '$runId relay inbox push FCM accepted',
        ),
        'commandJournal': _writeEvidence(
          directory,
          '$stem-commands.json',
          jsonEncode(_commands(scenarioId, runId, nonce, receiver)),
        ),
      };
      if (scenarioId == 'localized_recovery_copy') {
        evidence.addAll(<String, Object?>{
          'localeEnDump': _writeEvidence(
            directory,
            '$stem-locale-en.txt',
            'mknoon_dropped_push_recovery Message recovery '
                'Messages may be waiting',
          ),
          'localeDeDump': _writeEvidence(
            directory,
            '$stem-locale-de.txt',
            'mknoon_dropped_push_recovery Nachrichtenwiederherstellung '
                'Möglicherweise warten Nachrichten',
          ),
          'localeArDump': _writeEvidence(
            directory,
            '$stem-locale-ar.txt',
            'mknoon_dropped_push_recovery استرداد الرسائل '
                'قد تكون هناك رسائل بانتظار الاسترداد',
          ),
          'localeFallbackDump': _writeEvidence(
            directory,
            '$stem-locale-fallback.txt',
            'mknoon_dropped_push_recovery Message recovery '
                'Messages may be waiting',
          ),
        });
      }
      scenarios.add(<String, Object?>{
        'id': scenarioId,
        'mode': scenarioId == 'synthetic_outer_id_removal'
            ? 'test_only_transport_mutation'
            : 'real_relay',
        'receiverDeviceId': receiver,
        'senderDeviceId': sender,
        'evidence': evidence,
      });
    }
  }
  final proof = writeSimsArtifactEvidenceSync(
    directory: directory,
    capabilityId: androidNotificationRecoveryCompletionCapabilityId,
    validatorIds: const <String>[
      androidNotificationRecoveryCompletionValidator,
    ],
    payload: <String, Object?>{
      'campaignSchema': androidNotificationRecoveryCompletionCampaignSchema,
      'status': 'passed',
      'recordedAt': _timestamp,
      'buildProfile': 'android.production_fcm',
      'preparedArtifactSha256': _apkSha256,
      'packageName': _packageName,
      'childBuildCount': 0,
      'manualTaps': 0,
      'notificationCardTaps': 0,
      'headlessActivityLaunchCount': 0,
      'forbiddenProcessStopCount': 0,
      'platforms': const <String>['android'],
      'physicalDeviceId': plan331PhysicalAndroidDeviceId,
      'emulatorDeviceId': plan331AndroidEmulatorDeviceId,
      'scenarios': scenarios,
    },
  );
  return File(proof.path);
}

Map<String, Object?> _commands(
  String scenarioId,
  String runId,
  String nonce,
  String receiver,
) => <String, Object?>{
  'schema': androidNotificationRecoveryCompletionCommandSchema,
  'scenarioId': scenarioId,
  'runId': runId,
  'nonce': nonce,
  'commands': scenarioId == 'headless_direct_group_recovery'
      ? <Map<String, Object?>>[
          _command(receiver, 'termination', <String>[
            'shell',
            'input',
            'keyevent',
            'KEYCODE_HOME',
          ]),
          _command(receiver, 'termination', <String>[
            'shell',
            'am',
            'kill',
            _packageName,
          ]),
          _command(receiver, 'termination', <String>[
            'shell',
            'pidof',
            _packageName,
          ], stdoutEmpty: true),
          _command(receiver, 'headless', <String>[
            'shell',
            'am',
            'broadcast',
            '-a',
            'com.mknoon.app.debug.NOTIFICATION_RECOVERY_COMPLETION',
            '-p',
            _packageName,
            '--es',
            'scenarioId',
            scenarioId,
            '--es',
            'runId',
            runId,
            '--es',
            'nonce',
            nonce,
          ]),
        ]
      : <Map<String, Object?>>[
          _command(receiver, 'headless', <String>[
            'shell',
            'am',
            'broadcast',
            '-a',
            'com.mknoon.app.debug.NOTIFICATION_RECOVERY_COMPLETION',
            '-p',
            _packageName,
            '--es',
            'scenarioId',
            scenarioId,
            '--es',
            'runId',
            runId,
            '--es',
            'nonce',
            nonce,
          ]),
          _command(receiver, 'capture', const <String>[
            'shell',
            'dumpsys',
            'notification',
          ]),
        ],
};

Map<String, Object?> _command(
  String device,
  String phase,
  List<String> args, {
  bool stdoutEmpty = true,
}) => <String, Object?>{
  'phase': phase,
  'device': device,
  'args': args,
  'exitCode': 0,
  'stdoutEmpty': stdoutEmpty,
  'capturedAt': _timestamp,
};

Map<String, Object?> _facts(String scenarioId) => switch (scenarioId) {
  'headless_direct_group_recovery' => <String, Object?>{
    'generation': 1,
    'directRowsRecovered': 1,
    'groupRowsRecovered': 1,
    'directCards': 1,
    'groupCards': 1,
    'generationAcknowledged': true,
    'duplicateCount': 0,
    'activityLaunchesBeforeAck': 0,
  },
  'foreground_handoff_new_generation' => <String, Object?>{
    'firstGeneration': 1,
    'newerGeneration': 2,
    'soleOwner': true,
    'staleCompletionRejected': true,
    'newerGenerationAcknowledged': true,
    'duplicateCount': 0,
  },
  'direct_custody_recovery' => <String, Object?>{
    'eventKinds': const <String>[
      'text',
      'photo',
      'video',
      'voiceMessage',
      'reactionAdd',
    ],
    'firstShowFailureInjected': true,
    'readyCustodyRetained': true,
    'restartRetryCount': 1,
    'duplicateCount': 0,
  },
  'synthetic_outer_id_removal' => <String, Object?>{
    'label': 'test_only_outer_id_removal',
    'ordinaryRelayClaim': false,
    'authenticCiphertextRetained': true,
    'authenticatedInnerIdentityPromoted': true,
    'exactClaimAndReadFence': true,
    'identityFreeFallbackSilent': true,
  },
  'history_registration_health' => <String, Object?>{
    'historyLineCount': 5,
    'totalUnreadCount': 7,
    'androidNumber': 7,
    'stableConversationCardCount': 2,
    'healthPhases': const <String>[
      'healthy',
      'transient',
      'thresholdWarning',
      'permissionDenied',
      'retrying',
      'healthy',
    ],
    'warningActionAutomated': true,
    'warningClearedLive': true,
  },
  'localized_recovery_copy' => <String, Object?>{
    'locales': const <String>['en', 'de', 'ar', 'unsupported-default'],
    'stableChannelId': true,
    'importancePreserved': true,
    'unsupportedLocaleUsedDefault': true,
  },
  _ => throw ArgumentError.value(scenarioId),
};

String _flow(String scenarioId) => switch (scenarioId) {
  'headless_direct_group_recovery' => <String>[
    'RECOVERY_GENERATION_COMMITTED',
    'CANONICAL_RECOVERY_HEADLESS_STARTED',
    'DIRECT_INBOX_DRAIN_EXHAUSTED',
    'GROUP_INBOX_DRAIN_EXHAUSTED',
    'NOTIFICATION_SETTLEMENT_COMPLETE',
    'RECOVERY_GENERATION_ACKNOWLEDGED',
  ].join('\n'),
  'foreground_handoff_new_generation' => <String>[
    'RECOVERY_OWNER_DRAINING',
    'FOREGROUND_HANDOFF_ACQUIRED',
    'STALE_RECOVERY_COMPLETION_REJECTED',
    'NEWER_RECOVERY_GENERATION_ACKNOWLEDGED',
  ].join('\n'),
  'synthetic_outer_id_removal' =>
    'TEST_ONLY_OUTER_ID_REMOVAL authenticated exact claim',
  _ => 'PLAN331_SCENARIO_COMPLETED $scenarioId',
};

Map<String, Object?> _writeEvidence(
  Directory directory,
  String name,
  String value,
) {
  final file = File('${directory.path}/$name');
  file.writeAsStringSync('$value\n');
  final bytes = file.readAsBytesSync();
  return <String, Object?>{
    'path': name,
    'sha256': sha256.convert(bytes).toString(),
    'bytes': bytes.length,
  };
}

Map<String, dynamic> _readObject(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();

void _rewriteEvidence(
  File file,
  Map<String, dynamic> value,
  Map<String, dynamic> reference,
) {
  _rewriteJson(file, value);
  final bytes = file.readAsBytesSync();
  reference['sha256'] = sha256.convert(bytes).toString();
  reference['bytes'] = bytes.length;
}

void _rewriteJson(File file, Map<String, dynamic> value) {
  file.writeAsStringSync('${jsonEncode(value)}\n', flush: true);
}
