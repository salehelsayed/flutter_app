import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_notification_projection_android_criteria.dart';

const String _packageName = 'com.example.plan330fixture';
const String _physicalDeviceId = 'test-physical-android';
const String _emulatorDeviceId = 'test-emulator-android';
const String _groupAName = 'Plan330A-ABC123';
const String _groupBName = 'Plan330B-XYZ789';
const int _groupANotificationId = 101;
const int _groupBNotificationId = 202;

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'plan330_projection_validator_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'accepts exactly two content cards plus an Android auto-group summary',
    () async {
      final artifact = await _writeValidArtifact(temporaryDirectory);

      final validation =
          await validateGroupNotificationProjectionAndroidArtifact(
            artifactFile: artifact,
            expectedPhysicalDeviceId: _physicalDeviceId,
            expectedEmulatorDeviceId: _emulatorDeviceId,
          );

      expect(validation.failures, isEmpty, reason: validation.detail);
      expect(validation.ok, isTrue);
    },
  );

  test(
    'accepts Plan 393 exact-route activation cancellation before read',
    () async {
      final artifact = await _writeValidArtifact(
        temporaryDirectory,
        activationCancelFirst: true,
      );

      final validation =
          await validateGroupNotificationProjectionAndroidArtifact(
            artifactFile: artifact,
            expectedPhysicalDeviceId: _physicalDeviceId,
            expectedEmulatorDeviceId: _emulatorDeviceId,
          );

      expect(validation.failures, isEmpty, reason: validation.detail);
      expect(validation.ok, isTrue);
    },
  );

  test('rejects a third non-summary content card', () async {
    final artifact = await _writeValidArtifact(
      temporaryDirectory,
      includeThirdContentCard: true,
    );

    final validation = await validateGroupNotificationProjectionAndroidArtifact(
      artifactFile: artifact,
      expectedPhysicalDeviceId: _physicalDeviceId,
      expectedEmulatorDeviceId: _emulatorDeviceId,
    );

    expect(validation.ok, isFalse);
    expect(validation.failures, const <String>[
      r'$.readProjection.beforeNotificationDump must contain exactly one '
          'stable group-A card and one stable group-B card',
    ]);
  });

  test('rejects the legacy kind-wide conversation-read cancellation', () async {
    final artifact = await _writeValidArtifact(
      temporaryDirectory,
      cancelReason: 'conversation_read',
    );

    final validation = await validateGroupNotificationProjectionAndroidArtifact(
      artifactFile: artifact,
      expectedPhysicalDeviceId: _physicalDeviceId,
      expectedEmulatorDeviceId: _emulatorDeviceId,
    );

    expect(validation.ok, isFalse);
    expect(validation.failures, const <String>[
      r'$.readProjection.readFlowLog lacks committed read, '
          'in-coordinator unread-zero recheck, and exact activation/read '
          'generation cancellation',
    ]);
  });
}

Future<File> _writeValidArtifact(
  Directory directory, {
  bool includeThirdContentCard = false,
  String cancelReason = 'conversation_acknowledged',
  bool activationCancelFirst = false,
}) async {
  final beforeNotifications = await _writeEvidence(
    directory,
    'before_notifications.txt',
    _notificationDump(
      groupABody: 'Alice: synthetic message A',
      includeThirdContentCard: includeThirdContentCard,
    ),
  );
  final afterNotifications = await _writeEvidence(
    directory,
    'after_notifications.txt',
    _afterReadNotificationDump(),
  );
  final beforeUi = await _writeEvidence(
    directory,
    'before_ui.xml',
    '<hierarchy>\n'
        '  <node content-desc="Open group $_groupAName, 1 unread message" />\n'
        '  <node content-desc="Open group $_groupBName, 1 unread message" />\n'
        '</hierarchy>\n',
  );
  final afterUi = await _writeEvidence(
    directory,
    'after_ui.xml',
    '<hierarchy>\n'
        '  <node content-desc="Open group $_groupAName" />\n'
        '  <node content-desc="Open group $_groupBName, 1 unread message" />\n'
        '</hierarchy>\n',
  );
  final readFlow = await _writeEvidence(
    directory,
    'read_flow.log',
    '${activationCancelFirst ? 'NOTIFICATION_DISMISSED {"reason":"$cancelReason","id":$_groupANotificationId}\n' : ''}'
        'GROUP_MESSAGES_DB_MARK_READ_SUCCESS {"count":1}\n'
        'GROUP_MESSAGES_DB_COUNT_UNREAD_SUCCESS {"count":0}\n'
        '${activationCancelFirst ? '' : 'NOTIFICATION_DISMISSED {"reason":"$cancelReason","id":$_groupANotificationId}\n'}',
  );
  final killedPhotoTargetDigest = _digest('d');
  final killedPhotoNotifications = await _writeEvidence(
    directory,
    'killed_photo_notifications.txt',
    _notificationDump(groupABody: 'Alice: Photo'),
  );
  final killedPhotoFlow = await _writeEvidence(
    directory,
    'killed_photo_flow.log',
    'PUSH_BACKGROUND_MESSAGE_RECEIVED '
        '{"dataKeys":["type","groupId","ciphertext"]}\n'
        'PUSH_ANDROID_DATA_DECRYPT_OK {"kind":"group_message"}\n'
        'PUSH_BACKGROUND_NOTIFICATION_SHOWN {"silent":false}\n',
  );
  final killedPhotoReceipt = await _writeJsonEvidence(
    directory,
    'killed_photo_author_receipt.json',
    <String, Object?>{
      'schema': groupNotificationProjectionKilledPhotoReceiptSchema,
      'kind': 'photo',
      'mediaType': 'image',
      'ownerLane': 'group',
      'attachmentCount': 1,
      'targetMessageIdSha256': killedPhotoTargetDigest,
      'publicationCommitted': true,
    },
  );

  const kinds = <(String, String, String)>[
    ('photo', 'image', 'photo'),
    ('video', 'video', 'video'),
    ('voiceMessage', 'audio', 'voice message'),
  ];
  final observations = <Map<String, Object?>>[];
  for (var index = 0; index < kinds.length; index += 1) {
    final kind = kinds[index];
    final targetDigest = _digest('${index + 1}');
    final notificationDump = await _writeEvidence(
      directory,
      'reaction_${kind.$1}_notifications.txt',
      _notificationDump(groupABody: 'Alice reacted to your ${kind.$3}'),
    );
    final targetReceipt = await _writeJsonEvidence(
      directory,
      'reaction_${kind.$1}_target.json',
      <String, Object?>{
        'schema': groupNotificationProjectionTargetReceiptSchema,
        'kind': kind.$1,
        'mediaType': kind.$2,
        'ownerLane': 'group',
        'attachmentCount': 1,
        'targetMessageIdSha256': targetDigest,
        'reactionCommitted': true,
      },
    );
    observations.add(<String, Object?>{
      'kind': kind.$1,
      'mediaType': kind.$2,
      'ownerLane': 'group',
      'attachmentCount': 1,
      'targetMessageIdSha256': targetDigest,
      'notificationDump': notificationDump,
      'targetReceipt': targetReceipt,
    });
  }

  final commandJournal = await _writeJsonEvidence(
    directory,
    'command_journal.json',
    <String, Object?>{
      'schema': groupNotificationProjectionCommandJournalSchema,
      'commands': <Map<String, Object?>>[
        _command(
          stage: 'read_projection',
          target: _physicalDeviceId,
          action: 'tap',
          semanticTarget: 'Open group $_groupAName',
        ),
        _command(
          stage: 'read_projection',
          target: _physicalDeviceId,
          action: 'wait_unread_zero',
          semanticTarget: 'Open group $_groupAName',
        ),
        _command(
          stage: 'read_projection',
          target: _physicalDeviceId,
          action: 'dumpsys_notification',
          semanticTarget: 'after_read_zero',
        ),
        _command(
          stage: 'killed_photo_projection',
          target: _physicalDeviceId,
          action: 'verify_process_absent',
          semanticTarget: 'physical_recipient_before_killed_jpeg',
        ),
        _command(
          stage: 'killed_photo_projection',
          target: _emulatorDeviceId,
          action: 'send_fixed_group_jpeg',
          semanticTarget: 'emulator_author_to_killed_physical_recipient',
        ),
        _command(
          stage: 'killed_photo_projection',
          target: _physicalDeviceId,
          action: 'dumpsys_notification',
          semanticTarget: 'killed_group_photo_card',
        ),
        for (final kind in kinds)
          _command(
            stage: 'reaction_projection',
            target: _emulatorDeviceId,
            action: 'react_to_group_media',
            semanticTarget: kind.$1,
          ),
      ],
    },
  );

  final artifact = <String, Object?>{
    'schema': groupNotificationProjectionArtifactSchema,
    'version': 1,
    'capabilityId': groupNotificationProjectionCapabilityId,
    'scenario': groupNotificationProjectionScenarioId,
    'recordedAt': '2026-08-03T12:00:00.000Z',
    'build': <String, Object?>{
      'profile': 'android.production_fcm',
      'provenance': 'central_prebuilt',
      'apkSha256': _digest('c'),
      'childBuildCount': 0,
      'packageName': _packageName,
    },
    'topology': <String, Object?>{
      'physical': <String, Object?>{
        'deviceId': _physicalDeviceId,
        'platform': 'android',
        'kind': 'physical',
      },
      'emulator': <String, Object?>{
        'deviceId': _emulatorDeviceId,
        'platform': 'android',
        'kind': 'emulator',
      },
    },
    'fixture': <String, Object?>{
      'groupAName': _groupAName,
      'groupBName': _groupBName,
      'groupAIdSha256': _digest('a'),
      'groupBIdSha256': _digest('b'),
      'actorName': 'Alice',
      'locale': 'en',
    },
    'readProjection': <String, Object?>{
      'navigation': 'in_app_group_list',
      'unreadBefore': 1,
      'unreadAfter': 0,
      'commitObserved': true,
      'notificationTapCount': 0,
      'groupANotificationId': _groupANotificationId,
      'groupBNotificationId': _groupBNotificationId,
      'beforeNotificationDump': beforeNotifications,
      'afterNotificationDump': afterNotifications,
      'beforeUiDump': beforeUi,
      'afterUiDump': afterUi,
      'readFlowLog': readFlow,
    },
    'killedPhoto': <String, Object?>{
      'kind': 'photo',
      'mediaType': 'image',
      'senderRole': 'emulator_author',
      'recipientRole': 'killed_physical',
      'recipientProcessAbsentBeforeSend': true,
      'targetMessageIdSha256': killedPhotoTargetDigest,
      'relayBranch': 'full_ciphertext',
      'stableGroupANotificationId': _groupANotificationId,
      'notificationDump': killedPhotoNotifications,
      'flowLog': killedPhotoFlow,
      'authorReceipt': killedPhotoReceipt,
    },
    'reactionProjection': <String, Object?>{
      'stableGroupANotificationId': _groupANotificationId,
      'duplicateCount': 0,
      'observations': observations,
    },
    'automation': <String, Object?>{
      'manualTaps': 0,
      'notificationCardTaps': 0,
      'commandJournal': commandJournal,
    },
  };
  final artifactFile = File(
    '${directory.path}${Platform.pathSeparator}artifact.json',
  );
  await artifactFile.writeAsString(jsonEncode(artifact), flush: true);
  return artifactFile;
}

String _notificationDump({
  required String groupABody,
  bool includeThirdContentCard = false,
}) {
  return '''
Active Notifications:
  NotificationRecord(0x0: pkg=$_packageName user=UserHandle{0} id=0 tag=0|$_packageName|g:Aggregate_AlertingSection importance=4)
    flags=AUTO_CANCEL|LOCAL_ONLY|GROUP_SUMMARY|AUTOGROUP_SUMMARY
    android.title=null
    android.text=null
  NotificationRecord(0x1: pkg=$_packageName user=UserHandle{0} id=$_groupANotificationId tag=null importance=4)
    flags=AUTO_CANCEL
    android.title=$_groupAName
    android.text=$groupABody
  NotificationRecord(0x2: pkg=$_packageName user=UserHandle{0} id=$_groupBNotificationId tag=null importance=4)
    flags=AUTO_CANCEL
    android.title=$_groupBName
    android.text=Alice: synthetic message B
${includeThirdContentCard ? '''  NotificationRecord(0x3: pkg=$_packageName user=UserHandle{0} id=303 tag=null importance=4)
    flags=AUTO_CANCEL
    android.title=Plan330C-EXTRA1
    android.text=Alice: synthetic extra message
''' : ''}Ranking Config:
''';
}

String _afterReadNotificationDump() =>
    '''
Active Notifications:
  NotificationRecord(0x2: pkg=$_packageName user=UserHandle{0} id=$_groupBNotificationId tag=null importance=4)
    flags=AUTO_CANCEL
    android.title=$_groupBName
    android.text=Alice: synthetic message B
Ranking Config:
''';

Map<String, Object?> _command({
  required String stage,
  required String target,
  required String action,
  required String semanticTarget,
}) {
  return <String, Object?>{
    'stage': stage,
    'target': target,
    'action': action,
    'semanticTarget': semanticTarget,
    'recordedAt': '2026-08-03T12:00:00.000Z',
  };
}

Future<Map<String, Object?>> _writeJsonEvidence(
  Directory directory,
  String filename,
  Map<String, Object?> value,
) {
  return _writeEvidence(directory, filename, '${jsonEncode(value)}\n');
}

Future<Map<String, Object?>> _writeEvidence(
  Directory directory,
  String filename,
  String contents,
) async {
  final bytes = utf8.encode(contents);
  final file = File('${directory.path}${Platform.pathSeparator}$filename');
  await file.writeAsBytes(bytes, flush: true);
  return <String, Object?>{
    'path': filename,
    'sha256': sha256.convert(bytes).toString(),
  };
}

String _digest(String character) => List<String>.filled(64, character).join();
