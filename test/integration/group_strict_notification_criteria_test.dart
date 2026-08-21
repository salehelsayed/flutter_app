import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_strict_notification_criteria.dart';

const _physical = 'usb-android-393';
const _emulator = 'emulator-5554';
const _package = 'com.mknoon.app';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('plan393_strict_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('TC-393-08 strict notification artifact is fail closed', () async {
    final artifact = await _writeArtifact(directory);
    final accepted = await validateGroupStrictNotificationArtifact(
      artifactFile: artifact,
      expectedPhysicalDeviceId: _physical,
      expectedEmulatorDeviceId: _emulator,
      expectedApkSha256: _digest('apk'),
      expectedPackageName: _package,
    );
    expect(accepted.ok, isTrue, reason: accepted.detail);

    final decoded = Map<String, Object?>.from(
      jsonDecode(await artifact.readAsString()) as Map,
    );
    final reaction = Map<String, Object?>.from(decoded['reaction']! as Map);
    reaction['attemptedDelta'] = 0;
    decoded['reaction'] = reaction;
    await artifact.writeAsString(jsonEncode(decoded));
    final rejected = await validateGroupStrictNotificationArtifact(
      artifactFile: artifact,
      expectedPhysicalDeviceId: _physical,
      expectedEmulatorDeviceId: _emulator,
      expectedApkSha256: _digest('apk'),
      expectedPackageName: _package,
    );
    expect(rejected.ok, isFalse);
    expect(rejected.detail, contains(r'$.reaction.attemptedDelta mismatch'));
  });
}

Future<File> _writeArtifact(Directory directory) async {
  final refs = <String, Map<String, Object?>>{};
  for (final name in const <String>[
    'exact_flow.log',
    'exact_notification.log',
    'killed_flow.log',
    'killed_notification.log',
    'reaction_flow.log',
    'reaction_notification.log',
    'relay.log',
    'metrics_baseline.log',
    'metrics_before_killed.log',
    'metrics_before_reaction.log',
    'metrics_final.log',
    'commands.json',
  ]) {
    refs[name] = await _evidence(directory, name, 'evidence=$name\n');
  }
  final first = _digest('first');
  final finalDigest = _digest('final');
  final artifact = <String, Object?>{
    'schema': groupStrictNotificationArtifactSchema,
    'version': groupStrictNotificationArtifactVersion,
    'scenario': groupStrictNotificationScenarioId,
    'status': 'passed',
    'appPackage': _package,
    'preparedArtifactSha256': _digest('apk'),
    'topology': <String, Object?>{
      'physical': <String, Object?>{
        'deviceId': _physical,
        'kind': 'physical',
        'platform': 'android',
      },
      'emulator': <String, Object?>{
        'deviceId': _emulator,
        'kind': 'emulator',
        'platform': 'android',
      },
    },
    'authority': <String, Object?>{
      'groupName': 'Plan393S-ABC12345',
      'steps': <Map<String, Object?>>[
        _authorityStep('physical', 'author_authority', first, 'a'),
        _authorityStep('emulator', 'install_authority', first, 'a'),
        _authorityStep('emulator', 'author_authority', finalDigest, 'b'),
        _authorityStep('physical', 'install_authority', finalDigest, 'b'),
      ],
      'firstAuthorityDigest': first,
      'finalAuthorityDigest': finalDigest,
      'bothDevicesInstalledFinalAuthority': true,
      'revokedHistoricalDevices': 2,
    },
    'exactChat': _transition(
      marker: 'exact',
      processAbsent: false,
      cardCount: 0,
      notificationId: null,
      flow: 'suppressed',
      flowRef: refs['exact_flow.log']!,
      notificationRef: refs['exact_notification.log']!,
    ),
    'killedMessage': _transition(
      marker: 'killed',
      processAbsent: true,
      cardCount: 1,
      notificationId: 393,
      flow: 'received_decrypt_shown',
      flowRef: refs['killed_flow.log']!,
      notificationRef: refs['killed_notification.log']!,
    ),
    'reaction': <String, Object?>{
      ..._transition(
        marker: 'target',
        processAbsent: true,
        cardCount: 1,
        notificationId: 393,
        flow: 'received_decrypt_shown',
        flowRef: refs['reaction_flow.log']!,
        notificationRef: refs['reaction_notification.log']!,
      ),
      'typedReactionCopy': true,
    },
    'relay': <String, Object?>{
      'revision': 'plan393-test',
      'sha256': _digest('relay'),
      'journal': refs['relay.log'],
      'metricsBaseline': refs['metrics_baseline.log'],
      'metricsBeforeKilled': refs['metrics_before_killed.log'],
      'metricsBeforeReaction': refs['metrics_before_reaction.log'],
      'metricsFinal': refs['metrics_final.log'],
    },
    'automation': <String, Object?>{
      'manualTaps': 0,
      'notificationCardTaps': 0,
      'childBuildCount': 0,
      'statePreparedByParent': true,
      'commandJournal': refs['commands.json'],
    },
    'redaction': <String, Object?>{
      'tokensPersisted': false,
      'privateKeysPersisted': false,
      'authorityTransferPersisted': false,
      'rawPeerIdsPersisted': false,
    },
  };
  final output = File('${directory.path}/strict.json');
  await output.writeAsString(jsonEncode(artifact));
  return output;
}

Map<String, Object?> _authorityStep(
  String role,
  String phase,
  String digest,
  String event,
) => <String, Object?>{
  'role': role,
  'phase': phase,
  'authorityDigest': digest,
  'authorityEventAt': '2026-08-21T00:00:00.000Z',
  'authorityEventIdSha256': _digest(event),
  'keyEpoch': 1,
};

Map<String, Object?> _transition({
  required String marker,
  required bool processAbsent,
  required int cardCount,
  required int? notificationId,
  required String flow,
  required Map<String, Object?> flowRef,
  required Map<String, Object?> notificationRef,
}) => <String, Object?>{
  'markerSha256': _digest(marker),
  'processAbsentBeforeSend': processAbsent,
  'attemptedDelta': 1,
  'cardCount': cardCount,
  'notificationId': notificationId,
  'flow': flow,
  'flowEvidence': flowRef,
  'notificationEvidence': notificationRef,
};

Future<Map<String, Object?>> _evidence(
  Directory directory,
  String name,
  String content,
) async {
  final file = File('${directory.path}/$name');
  final bytes = utf8.encode(content);
  await file.writeAsBytes(bytes);
  return <String, Object?>{
    'path': name,
    'sha256': sha256.convert(bytes).toString(),
    'bytes': bytes.length,
  };
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
