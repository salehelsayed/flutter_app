import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'reaction_notification_proof_support.dart'
    show extractActiveContentNotificationCards;

const String groupNotificationProjectionCapabilityId =
    'groups.notification_projection_durability';
const String groupNotificationProjectionScenarioId =
    'android_group_notification_projection_durability';
const String groupNotificationProjectionArtifactSchema =
    'mknoon.plan330.android-group-notification-projection.v1';
const String groupNotificationProjectionTargetReceiptSchema =
    'mknoon.plan330.group-media-reaction-target.v1';
const String groupNotificationProjectionKilledPhotoReceiptSchema =
    'mknoon.plan393.group-killed-photo-author.v1';
const String groupNotificationProjectionCommandJournalSchema =
    'mknoon.plan330.android-command-journal.v1';
const String plan330PhysicalAndroidDeviceId = '21071FDF600CSC';
const String plan330AndroidEmulatorDeviceId = 'emulator-5554';

const List<String> groupNotificationProjectionCriteria = <String>[
  'groups.two_group_read_zero_exact_cancel',
  'groups.killed_group_photo_message',
  'groups.group_reaction_photo_semantic_kind',
  'groups.group_reaction_video_semantic_kind',
  'groups.group_reaction_voice_message_semantic_kind',
  'groups.group_projection_stable_single_card',
];

final class GroupNotificationProjectionArtifactValidation {
  GroupNotificationProjectionArtifactValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

/// Validates the Plan-330 Android proof without trusting normalized booleans.
///
/// Every OS/UI/flow claim is bound to a content-addressed raw capture next to
/// [artifactFile]. Notification identity and localized media-kind copy are
/// recomputed from those captures. A legacy group-reaction artifact therefore
/// cannot satisfy this contract merely by adding Plan-330 marker fields.
Future<GroupNotificationProjectionArtifactValidation>
validateGroupNotificationProjectionAndroidArtifact({
  required File artifactFile,
  String expectedPhysicalDeviceId = plan330PhysicalAndroidDeviceId,
  String expectedEmulatorDeviceId = plan330AndroidEmulatorDeviceId,
  String? expectedApkSha256,
  String? expectedPackageName,
}) async {
  final failures = <String>[];
  if (!_isRegularFile(artifactFile)) {
    return GroupNotificationProjectionArtifactValidation(<String>[
      'proof artifact is not a regular file: ${artifactFile.path}',
    ]);
  }

  final artifact = _decodeObject(
    await artifactFile.readAsString(),
    r'$',
    failures,
  );
  if (artifact == null) {
    return GroupNotificationProjectionArtifactValidation(failures);
  }
  _expectExactKeys(
    artifact,
    const <String>{
      'schema',
      'version',
      'capabilityId',
      'scenario',
      'recordedAt',
      'build',
      'topology',
      'fixture',
      'readProjection',
      'killedPhoto',
      'reactionProjection',
      'automation',
    },
    r'$',
    failures,
  );
  _expectValue(
    artifact,
    'schema',
    groupNotificationProjectionArtifactSchema,
    r'$',
    failures,
  );
  _expectValue(artifact, 'version', 1, r'$', failures);
  _expectValue(
    artifact,
    'capabilityId',
    groupNotificationProjectionCapabilityId,
    r'$',
    failures,
  );
  _expectValue(
    artifact,
    'scenario',
    groupNotificationProjectionScenarioId,
    r'$',
    failures,
  );
  _expectUtcTimestamp(artifact['recordedAt'], r'$.recordedAt', failures);

  final build = _object(artifact['build'], r'$.build', failures);
  String packageName = '';
  if (build != null) {
    _expectExactKeys(
      build,
      const <String>{
        'profile',
        'provenance',
        'apkSha256',
        'childBuildCount',
        'packageName',
      },
      r'$.build',
      failures,
    );
    _expectValue(
      build,
      'profile',
      'android.production_fcm',
      r'$.build',
      failures,
    );
    _expectValue(build, 'provenance', 'central_prebuilt', r'$.build', failures);
    _expectValue(build, 'childBuildCount', 0, r'$.build', failures);
    final apkSha = _requiredString(build, 'apkSha256', r'$.build', failures);
    if (!_isSha256(apkSha)) {
      failures.add(r'$.build.apkSha256 must be a lowercase SHA-256 digest');
    }
    if (expectedApkSha256 != null && apkSha != expectedApkSha256) {
      failures.add(r'$.build.apkSha256 does not bind the prepared APK');
    }
    packageName =
        _requiredString(build, 'packageName', r'$.build', failures) ?? '';
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$').hasMatch(packageName)) {
      failures.add(r'$.build.packageName is not a safe Android package');
    }
    if (expectedPackageName != null && packageName != expectedPackageName) {
      failures.add(r'$.build.packageName does not match the prepared app');
    }
  }

  _validateTopology(
    artifact['topology'],
    expectedPhysicalDeviceId: expectedPhysicalDeviceId,
    expectedEmulatorDeviceId: expectedEmulatorDeviceId,
    failures: failures,
  );

  final fixture = _object(artifact['fixture'], r'$.fixture', failures);
  String groupAName = '';
  String groupBName = '';
  String actorName = '';
  String locale = '';
  if (fixture != null) {
    _expectExactKeys(
      fixture,
      const <String>{
        'groupAName',
        'groupBName',
        'groupAIdSha256',
        'groupBIdSha256',
        'actorName',
        'locale',
      },
      r'$.fixture',
      failures,
    );
    groupAName =
        _requiredString(fixture, 'groupAName', r'$.fixture', failures) ?? '';
    groupBName =
        _requiredString(fixture, 'groupBName', r'$.fixture', failures) ?? '';
    actorName =
        _requiredString(fixture, 'actorName', r'$.fixture', failures) ?? '';
    locale = _requiredString(fixture, 'locale', r'$.fixture', failures) ?? '';
    if (!RegExp(r'^Plan330A-[A-Za-z0-9]{6,32}$').hasMatch(groupAName)) {
      failures.add(r'$.fixture.groupAName is not a disposable A fixture');
    }
    if (!RegExp(r'^Plan330B-[A-Za-z0-9]{6,32}$').hasMatch(groupBName) ||
        groupAName == groupBName) {
      failures.add(r'$.fixture.groupBName is not a distinct B fixture');
    }
    if (actorName != 'Alice') {
      failures.add(r'$.fixture.actorName must bind the disposable Alice role');
    }
    if (!const <String>{'ar', 'de', 'en'}.contains(locale)) {
      failures.add(r'$.fixture.locale must be ar, de, or en');
    }
    for (final key in const <String>['groupAIdSha256', 'groupBIdSha256']) {
      if (!_isSha256(fixture[key])) {
        failures.add(
          r'$.fixture.'
          '$key must be a SHA-256 digest',
        );
      }
    }
    if (fixture['groupAIdSha256'] == fixture['groupBIdSha256']) {
      failures.add(r'$.fixture group identity digests must differ');
    }
  }

  final read = _object(
    artifact['readProjection'],
    r'$.readProjection',
    failures,
  );
  int? groupANotificationId;
  int? groupBNotificationId;
  if (read != null) {
    _expectExactKeys(
      read,
      const <String>{
        'navigation',
        'unreadBefore',
        'unreadAfter',
        'commitObserved',
        'notificationTapCount',
        'groupANotificationId',
        'groupBNotificationId',
        'beforeNotificationDump',
        'afterNotificationDump',
        'beforeUiDump',
        'afterUiDump',
        'readFlowLog',
      },
      r'$.readProjection',
      failures,
    );
    _expectValue(
      read,
      'navigation',
      'in_app_group_list',
      r'$.readProjection',
      failures,
    );
    _expectValue(read, 'unreadBefore', 1, r'$.readProjection', failures);
    _expectValue(read, 'unreadAfter', 0, r'$.readProjection', failures);
    _expectValue(read, 'commitObserved', true, r'$.readProjection', failures);
    _expectValue(
      read,
      'notificationTapCount',
      0,
      r'$.readProjection',
      failures,
    );
    groupANotificationId = _positiveInt(
      read['groupANotificationId'],
      r'$.readProjection.groupANotificationId',
      failures,
    );
    groupBNotificationId = _positiveInt(
      read['groupBNotificationId'],
      r'$.readProjection.groupBNotificationId',
      failures,
    );
    if (groupANotificationId != null &&
        groupANotificationId == groupBNotificationId) {
      failures.add(r'$.readProjection notification ids must differ');
    }

    final beforeNotifications = await _readEvidence(
      read['beforeNotificationDump'],
      artifactFile: artifactFile,
      path: r'$.readProjection.beforeNotificationDump',
      failures: failures,
    );
    final afterNotifications = await _readEvidence(
      read['afterNotificationDump'],
      artifactFile: artifactFile,
      path: r'$.readProjection.afterNotificationDump',
      failures: failures,
    );
    final beforeUi = await _readEvidence(
      read['beforeUiDump'],
      artifactFile: artifactFile,
      path: r'$.readProjection.beforeUiDump',
      failures: failures,
    );
    final afterUi = await _readEvidence(
      read['afterUiDump'],
      artifactFile: artifactFile,
      path: r'$.readProjection.afterUiDump',
      failures: failures,
    );
    final readFlow = await _readEvidence(
      read['readFlowLog'],
      artifactFile: artifactFile,
      path: r'$.readProjection.readFlowLog',
      failures: failures,
    );

    if (beforeNotifications != null &&
        groupANotificationId != null &&
        groupBNotificationId != null) {
      final cards = _activeAppCards(
        beforeNotifications,
        packageName,
        r'$.readProjection.beforeNotificationDump',
        failures,
      );
      _expectExactTwoGroupCards(
        cards,
        groupAName: groupAName,
        groupBName: groupBName,
        groupANotificationId: groupANotificationId,
        groupBNotificationId: groupBNotificationId,
        path: r'$.readProjection.beforeNotificationDump',
        failures: failures,
      );
    }
    if (afterNotifications != null && groupBNotificationId != null) {
      final cards = _activeAppCards(
        afterNotifications,
        packageName,
        r'$.readProjection.afterNotificationDump',
        failures,
      );
      if (cards.length != 1 ||
          cards.single.id != groupBNotificationId ||
          cards.single.title != groupBName ||
          cards.any(
            (card) =>
                card.id == groupANotificationId || card.title == groupAName,
          )) {
        failures.add(
          r'$.readProjection.afterNotificationDump must contain only the '
          'unchanged group-B card',
        );
      }
    }
    if (beforeUi != null &&
        (!beforeUi.contains('Open group $groupAName, 1 unread message') ||
            !beforeUi.contains('Open group $groupBName, 1 unread message'))) {
      failures.add(
        r'$.readProjection.beforeUiDump lacks both unread-one group nodes',
      );
    }
    final groupAStillUnread = RegExp(
      'Open group ${RegExp.escape(groupAName)}, [1-9][0-9]* unread messages?',
    ).hasMatch(afterUi ?? '');
    if (afterUi != null &&
        (!afterUi.contains('Open group $groupAName') ||
            groupAStillUnread ||
            !afterUi.contains('Open group $groupBName, 1 unread message'))) {
      failures.add(
        r'$.readProjection.afterUiDump does not prove A=0 while B=1',
      );
    }
    if (readFlow != null && groupANotificationId != null) {
      final lines = readFlow.split('\n');
      final markReadIndex = lines.indexWhere(
        (line) =>
            line.contains('GROUP_MESSAGES_DB_MARK_READ_SUCCESS') &&
            RegExp(r'"count"\s*:\s*[1-9][0-9]*').hasMatch(line),
      );
      final unreadZeroIndex = lines.indexWhere(
        (line) =>
            line.contains('GROUP_MESSAGES_DB_COUNT_UNREAD_SUCCESS') &&
            RegExp(r'"count"\s*:\s*0').hasMatch(line),
        markReadIndex < 0 ? 0 : markReadIndex + 1,
      );
      final exactCancelIndex = lines.indexWhere(
        (line) =>
            line.contains('NOTIFICATION_DISMISSED') &&
            RegExp(
              r'"reason"\s*:\s*"conversation_acknowledged"',
            ).hasMatch(line) &&
            RegExp(
              '"id"\\s*:\\s*${RegExp.escape('$groupANotificationId')}',
            ).hasMatch(line),
      );
      if (markReadIndex < 0 ||
          unreadZeroIndex <= markReadIndex ||
          exactCancelIndex < 0) {
        failures.add(
          r'$.readProjection.readFlowLog lacks committed read, '
          'in-coordinator unread-zero recheck, and exact activation/read '
          'generation cancellation',
        );
      }
      if (readFlow.contains('NOTIFICATION_TAPPED')) {
        failures.add(
          r'$.readProjection.readFlowLog contains a forbidden notification tap',
        );
      }
    }
  }

  final killedPhoto = _object(
    artifact['killedPhoto'],
    r'$.killedPhoto',
    failures,
  );
  if (killedPhoto != null) {
    _expectExactKeys(
      killedPhoto,
      const <String>{
        'kind',
        'mediaType',
        'senderRole',
        'recipientRole',
        'recipientProcessAbsentBeforeSend',
        'targetMessageIdSha256',
        'relayBranch',
        'stableGroupANotificationId',
        'notificationDump',
        'flowLog',
        'authorReceipt',
      },
      r'$.killedPhoto',
      failures,
    );
    _expectValue(killedPhoto, 'kind', 'photo', r'$.killedPhoto', failures);
    _expectValue(killedPhoto, 'mediaType', 'image', r'$.killedPhoto', failures);
    _expectValue(
      killedPhoto,
      'senderRole',
      'emulator_author',
      r'$.killedPhoto',
      failures,
    );
    _expectValue(
      killedPhoto,
      'recipientRole',
      'killed_physical',
      r'$.killedPhoto',
      failures,
    );
    _expectValue(
      killedPhoto,
      'recipientProcessAbsentBeforeSend',
      true,
      r'$.killedPhoto',
      failures,
    );
    _expectValue(
      killedPhoto,
      'stableGroupANotificationId',
      groupANotificationId,
      r'$.killedPhoto',
      failures,
    );
    final targetDigest = _requiredString(
      killedPhoto,
      'targetMessageIdSha256',
      r'$.killedPhoto',
      failures,
    );
    if (!_isSha256(targetDigest)) {
      failures.add(
        r'$.killedPhoto.targetMessageIdSha256 must be a SHA-256 digest',
      );
    }
    final relayBranch = _requiredString(
      killedPhoto,
      'relayBranch',
      r'$.killedPhoto',
      failures,
    );
    if (!const <String>{
      'full_ciphertext',
      'preview_unavailable',
    }.contains(relayBranch)) {
      failures.add(
        r'$.killedPhoto.relayBranch must be full_ciphertext or '
        'preview_unavailable',
      );
    }

    final notificationDump = await _readEvidence(
      killedPhoto['notificationDump'],
      artifactFile: artifactFile,
      path: r'$.killedPhoto.notificationDump',
      failures: failures,
    );
    if (notificationDump != null &&
        groupANotificationId != null &&
        groupBNotificationId != null) {
      _expectExactTwoGroupCards(
        _activeAppCards(
          notificationDump,
          packageName,
          r'$.killedPhoto.notificationDump',
          failures,
        ),
        groupAName: groupAName,
        groupBName: groupBName,
        groupANotificationId: groupANotificationId,
        groupBNotificationId: groupBNotificationId,
        path: r'$.killedPhoto.notificationDump',
        failures: failures,
      );
    }

    final flowLog = await _readEvidence(
      killedPhoto['flowLog'],
      artifactFile: artifactFile,
      path: r'$.killedPhoto.flowLog',
      failures: failures,
    );
    if (flowLog != null) {
      final lines = flowLog.split('\n');
      final received = lines
          .asMap()
          .entries
          .where(
            (entry) => entry.value.contains('PUSH_BACKGROUND_MESSAGE_RECEIVED'),
          )
          .toList(growable: false);
      final shownIndex = lines.indexWhere(
        (line) => line.contains('PUSH_BACKGROUND_NOTIFICATION_SHOWN'),
      );
      final receivedIndex = received.length == 1 ? received.single.key : -1;
      final receivedLine = received.length == 1 ? received.single.value : '';
      final branchMatches = switch (relayBranch) {
        'full_ciphertext' =>
          receivedLine.contains('ciphertext') &&
              !receivedLine.contains('preview_unavailable'),
        'preview_unavailable' =>
          receivedLine.contains('preview_unavailable') &&
              !receivedLine.contains('ciphertext'),
        _ => false,
      };
      final decryptIndex = lines.indexWhere(
        (line) => line.contains('PUSH_ANDROID_DATA_DECRYPT_OK'),
        receivedIndex < 0 ? 0 : receivedIndex + 1,
      );
      if (receivedIndex < 0 ||
          shownIndex <= receivedIndex ||
          !branchMatches ||
          (relayBranch == 'full_ciphertext' &&
              (decryptIndex <= receivedIndex || decryptIndex >= shownIndex))) {
        failures.add(
          r'$.killedPhoto.flowLog lacks one killed-photo received-to-shown '
          'flow bound to its exact relay branch',
        );
      }
    }

    final authorReceipt = await _readEvidence(
      killedPhoto['authorReceipt'],
      artifactFile: artifactFile,
      path: r'$.killedPhoto.authorReceipt',
      failures: failures,
    );
    if (authorReceipt != null) {
      final receipt = _decodeObject(
        authorReceipt,
        r'$.killedPhoto.authorReceipt',
        failures,
      );
      if (receipt != null) {
        _expectExactKeys(
          receipt,
          const <String>{
            'schema',
            'kind',
            'mediaType',
            'ownerLane',
            'attachmentCount',
            'targetMessageIdSha256',
            'publicationCommitted',
          },
          r'$.killedPhoto.authorReceipt',
          failures,
        );
        _expectValue(
          receipt,
          'schema',
          groupNotificationProjectionKilledPhotoReceiptSchema,
          r'$.killedPhoto.authorReceipt',
          failures,
        );
        _expectValue(
          receipt,
          'targetMessageIdSha256',
          targetDigest,
          r'$.killedPhoto.authorReceipt',
          failures,
        );
        _expectValue(
          receipt,
          'publicationCommitted',
          true,
          r'$.killedPhoto.authorReceipt',
          failures,
        );
      }
    }
  }

  final reaction = _object(
    artifact['reactionProjection'],
    r'$.reactionProjection',
    failures,
  );
  if (reaction != null) {
    _expectExactKeys(
      reaction,
      const <String>{
        'stableGroupANotificationId',
        'duplicateCount',
        'observations',
      },
      r'$.reactionProjection',
      failures,
    );
    _expectValue(
      reaction,
      'stableGroupANotificationId',
      groupANotificationId,
      r'$.reactionProjection',
      failures,
    );
    _expectValue(
      reaction,
      'duplicateCount',
      0,
      r'$.reactionProjection',
      failures,
    );
    final observations = reaction['observations'];
    const expectedKinds = <String>['photo', 'video', 'voiceMessage'];
    const expectedMediaTypes = <String>['image', 'video', 'audio'];
    if (observations is! List || observations.length != expectedKinds.length) {
      failures.add(
        r'$.reactionProjection.observations must contain photo, video, and '
        'voiceMessage exactly once in order',
      );
    } else {
      final targetDigests = <String>{};
      for (var index = 0; index < expectedKinds.length; index += 1) {
        final path = '\$.reactionProjection.observations[$index]';
        final observation = _object(observations[index], path, failures);
        if (observation == null) continue;
        _expectExactKeys(
          observation,
          const <String>{
            'kind',
            'mediaType',
            'ownerLane',
            'attachmentCount',
            'targetMessageIdSha256',
            'notificationDump',
            'targetReceipt',
          },
          path,
          failures,
        );
        final kind = expectedKinds[index];
        final mediaType = expectedMediaTypes[index];
        _expectValue(observation, 'kind', kind, path, failures);
        _expectValue(observation, 'mediaType', mediaType, path, failures);
        _expectValue(observation, 'ownerLane', 'group', path, failures);
        _expectValue(observation, 'attachmentCount', 1, path, failures);
        final targetDigest = _requiredString(
          observation,
          'targetMessageIdSha256',
          path,
          failures,
        );
        if (!_isSha256(targetDigest)) {
          failures.add('$path.targetMessageIdSha256 must be a SHA-256 digest');
        } else if (!targetDigests.add(targetDigest!)) {
          failures.add('$path.targetMessageIdSha256 must be unique');
        }

        final targetReceipt = await _readEvidence(
          observation['targetReceipt'],
          artifactFile: artifactFile,
          path: '$path.targetReceipt',
          failures: failures,
        );
        if (targetReceipt != null) {
          _validateTargetReceipt(
            targetReceipt,
            kind: kind,
            mediaType: mediaType,
            targetMessageIdSha256: targetDigest ?? '',
            path: '$path.targetReceipt',
            failures: failures,
          );
        }

        final notificationDump = await _readEvidence(
          observation['notificationDump'],
          artifactFile: artifactFile,
          path: '$path.notificationDump',
          failures: failures,
        );
        if (notificationDump != null &&
            groupANotificationId != null &&
            groupBNotificationId != null) {
          final cards = _activeAppCards(
            notificationDump,
            packageName,
            '$path.notificationDump',
            failures,
          );
          _expectExactTwoGroupCards(
            cards,
            groupAName: groupAName,
            groupBName: groupBName,
            groupANotificationId: groupANotificationId,
            groupBNotificationId: groupBNotificationId,
            path: '$path.notificationDump',
            failures: failures,
          );
          final groupACards = cards
              .where((card) => card.title == groupAName)
              .toList(growable: false);
          final expectedBody = _localizedReactionBody(
            locale: locale,
            actorName: actorName,
            kind: kind,
            failures: failures,
          );
          if (groupACards.length != 1 ||
              expectedBody == null ||
              groupACards.single.body != expectedBody) {
            failures.add(
              '$path.notificationDump lacks exact localized $kind reaction '
              'copy on the one stable group-A card',
            );
          }
        }
      }
    }
  }

  _validateAutomation(
    artifact['automation'],
    artifactFile: artifactFile,
    physicalDeviceId: expectedPhysicalDeviceId,
    emulatorDeviceId: expectedEmulatorDeviceId,
    groupAName: groupAName,
    failures: failures,
  );
  return GroupNotificationProjectionArtifactValidation(failures);
}

void _validateTopology(
  Object? value, {
  required String expectedPhysicalDeviceId,
  required String expectedEmulatorDeviceId,
  required List<String> failures,
}) {
  final topology = _object(value, r'$.topology', failures);
  if (topology == null) return;
  _expectExactKeys(
    topology,
    const <String>{'physical', 'emulator'},
    r'$.topology',
    failures,
  );
  for (final entry in <(String, String, String)>[
    ('physical', expectedPhysicalDeviceId, 'physical'),
    ('emulator', expectedEmulatorDeviceId, 'emulator'),
  ]) {
    final path = '\$.topology.${entry.$1}';
    final target = _object(topology[entry.$1], path, failures);
    if (target == null) continue;
    _expectExactKeys(
      target,
      const <String>{'deviceId', 'platform', 'kind'},
      path,
      failures,
    );
    _expectValue(target, 'deviceId', entry.$2, path, failures);
    _expectValue(target, 'platform', 'android', path, failures);
    _expectValue(target, 'kind', entry.$3, path, failures);
  }
}

Future<void> _validateAutomation(
  Object? value, {
  required File artifactFile,
  required String physicalDeviceId,
  required String emulatorDeviceId,
  required String groupAName,
  required List<String> failures,
}) async {
  final automation = _object(value, r'$.automation', failures);
  if (automation == null) return;
  _expectExactKeys(
    automation,
    const <String>{'manualTaps', 'notificationCardTaps', 'commandJournal'},
    r'$.automation',
    failures,
  );
  _expectValue(automation, 'manualTaps', 0, r'$.automation', failures);
  _expectValue(
    automation,
    'notificationCardTaps',
    0,
    r'$.automation',
    failures,
  );
  final text = await _readEvidence(
    automation['commandJournal'],
    artifactFile: artifactFile,
    path: r'$.automation.commandJournal',
    failures: failures,
  );
  if (text == null) return;
  final journal = _decodeObject(text, r'$.automation.commandJournal', failures);
  if (journal == null) return;
  _expectExactKeys(
    journal,
    const <String>{'schema', 'commands'},
    r'$.automation.commandJournal',
    failures,
  );
  _expectValue(
    journal,
    'schema',
    groupNotificationProjectionCommandJournalSchema,
    r'$.automation.commandJournal',
    failures,
  );
  final commands = journal['commands'];
  if (commands is! List || commands.isEmpty) {
    failures.add(r'$.automation.commandJournal.commands must be non-empty');
    return;
  }
  var openedGroupAInAppAt = -1;
  var unreadZeroObservedAt = -1;
  var postReadNotificationDumpAt = -1;
  var killedRecipientAbsentAt = -1;
  var killedPhotoSentAt = -1;
  var killedPhotoCardAt = -1;
  final reactedKinds = <String>{};
  for (var index = 0; index < commands.length; index += 1) {
    final path = '\$.automation.commandJournal.commands[$index]';
    final command = _object(commands[index], path, failures);
    if (command == null) continue;
    _expectExactKeys(
      command,
      const <String>{
        'stage',
        'target',
        'action',
        'semanticTarget',
        'recordedAt',
      },
      path,
      failures,
    );
    final stage = '${command['stage'] ?? ''}';
    final target = '${command['target'] ?? ''}';
    final action = '${command['action'] ?? ''}';
    final semanticTarget = '${command['semanticTarget'] ?? ''}';
    _expectUtcTimestamp(command['recordedAt'], '$path.recordedAt', failures);
    if (stage == 'read_projection' &&
        target == physicalDeviceId &&
        action == 'tap' &&
        semanticTarget == 'Open group $groupAName') {
      openedGroupAInAppAt = index;
    }
    if (stage == 'read_projection' &&
        target == physicalDeviceId &&
        action == 'wait_unread_zero' &&
        semanticTarget == 'Open group $groupAName') {
      unreadZeroObservedAt = index;
    }
    if (stage == 'read_projection' &&
        target == physicalDeviceId &&
        action == 'dumpsys_notification' &&
        semanticTarget == 'after_read_zero') {
      postReadNotificationDumpAt = index;
    }
    if (stage == 'reaction_projection' &&
        target == emulatorDeviceId &&
        action == 'react_to_group_media' &&
        const <String>{
          'photo',
          'video',
          'voiceMessage',
        }.contains(semanticTarget)) {
      reactedKinds.add(semanticTarget);
    }
    if (stage == 'killed_photo_projection' &&
        target == physicalDeviceId &&
        action == 'verify_process_absent' &&
        semanticTarget == 'physical_recipient_before_killed_jpeg') {
      killedRecipientAbsentAt = index;
    }
    if (stage == 'killed_photo_projection' &&
        target == emulatorDeviceId &&
        action == 'send_fixed_group_jpeg' &&
        semanticTarget == 'emulator_author_to_killed_physical_recipient') {
      killedPhotoSentAt = index;
    }
    if (stage == 'killed_photo_projection' &&
        target == physicalDeviceId &&
        action == 'dumpsys_notification' &&
        semanticTarget == 'killed_group_photo_card') {
      killedPhotoCardAt = index;
    }
    if (action == 'tap_notification' ||
        stage.contains('notification_shade') ||
        semanticTarget.contains('notification card')) {
      failures.add('$path records a forbidden notification-card action');
    }
  }
  if (openedGroupAInAppAt < 0 ||
      unreadZeroObservedAt <= openedGroupAInAppAt ||
      postReadNotificationDumpAt <= unreadZeroObservedAt) {
    failures.add(
      r'$.automation.commandJournal lacks ordered in-app group-A navigation, '
      'committed unread-zero wait, and post-commit notification dump',
    );
  }
  if (reactedKinds.length != 3) {
    failures.add(
      r'$.automation.commandJournal lacks automated photo/video/voice '
      'reaction actions',
    );
  }
  if (killedRecipientAbsentAt < 0 ||
      killedPhotoSentAt <= killedRecipientAbsentAt ||
      killedPhotoCardAt <= killedPhotoSentAt) {
    failures.add(
      r'$.automation.commandJournal lacks ordered killed-recipient, fixed '
      'JPEG send, and group-photo card evidence',
    );
  }
}

void _validateTargetReceipt(
  String text, {
  required String kind,
  required String mediaType,
  required String targetMessageIdSha256,
  required String path,
  required List<String> failures,
}) {
  final receipt = _decodeObject(text, path, failures);
  if (receipt == null) return;
  _expectExactKeys(
    receipt,
    const <String>{
      'schema',
      'kind',
      'mediaType',
      'ownerLane',
      'attachmentCount',
      'targetMessageIdSha256',
      'reactionCommitted',
    },
    path,
    failures,
  );
  _expectValue(
    receipt,
    'schema',
    groupNotificationProjectionTargetReceiptSchema,
    path,
    failures,
  );
  _expectValue(receipt, 'kind', kind, path, failures);
  _expectValue(receipt, 'mediaType', mediaType, path, failures);
  _expectValue(receipt, 'ownerLane', 'group', path, failures);
  _expectValue(receipt, 'attachmentCount', 1, path, failures);
  _expectValue(
    receipt,
    'targetMessageIdSha256',
    targetMessageIdSha256,
    path,
    failures,
  );
  _expectValue(receipt, 'reactionCommitted', true, path, failures);
}

String? _localizedReactionBody({
  required String locale,
  required String actorName,
  required String kind,
  required List<String> failures,
}) {
  final arbFile = File('lib/l10n/app_$locale.arb');
  if (!_isRegularFile(arbFile)) {
    failures.add('localized ARB is unavailable for $locale');
    return null;
  }
  final arb = _decodeObject(
    arbFile.readAsStringSync(),
    'lib/l10n/app_$locale.arb',
    failures,
  );
  if (arb == null) return null;
  final targetKey = switch (kind) {
    'photo' => 'notification_group_reaction_target_photo',
    'video' => 'notification_group_reaction_target_video',
    'voiceMessage' => 'notification_group_reaction_target_voice_message',
    _ => '',
  };
  final target = arb[targetKey];
  final template = arb['notification_group_reaction_actor'];
  if (target is! String ||
      target.trim().isEmpty ||
      template is! String ||
      !template.contains('{actorName}') ||
      !template.contains('{targetKind}')) {
    failures.add('localized reaction keys are malformed for $locale/$kind');
    return null;
  }
  return template
      .replaceAll('{actorName}', actorName)
      .replaceAll('{targetKind}', target);
}

final class _NotificationCard {
  const _NotificationCard({
    required this.id,
    required this.title,
    required this.body,
  });

  final int id;
  final String title;
  final String body;
}

List<_NotificationCard> _activeAppCards(
  String dump,
  String packageName,
  String path,
  List<String> failures,
) {
  if (!dump.contains('NotificationRecord(') || packageName.isEmpty) {
    failures.add('$path is not a raw Android notification dump');
    return const <_NotificationCard>[];
  }
  final cards = <_NotificationCard>[];
  final contentCards = extractActiveContentNotificationCards(
    dump,
    packageName: packageName,
  );
  for (final card in contentCards) {
    final id = card.id;
    final title = card.title;
    final body = card.body;
    if (id == null || id <= 0 || title.isEmpty || body.isEmpty) {
      failures.add('$path contains a malformed app notification record');
      continue;
    }
    cards.add(_NotificationCard(id: id, title: title, body: body));
  }
  return cards;
}

void _expectExactTwoGroupCards(
  List<_NotificationCard> cards, {
  required String groupAName,
  required String groupBName,
  required int groupANotificationId,
  required int groupBNotificationId,
  required String path,
  required List<String> failures,
}) {
  final a = cards
      .where(
        (card) => card.id == groupANotificationId && card.title == groupAName,
      )
      .toList(growable: false);
  final b = cards
      .where(
        (card) => card.id == groupBNotificationId && card.title == groupBName,
      )
      .toList(growable: false);
  if (cards.length != 2 || a.length != 1 || b.length != 1) {
    failures.add(
      '$path must contain exactly one stable group-A card and one stable '
      'group-B card',
    );
  }
}

Future<String?> _readEvidence(
  Object? value, {
  required File artifactFile,
  required String path,
  required List<String> failures,
}) async {
  final reference = _object(value, path, failures);
  if (reference == null) return null;
  _expectExactKeys(reference, const <String>{'path', 'sha256'}, path, failures);
  final relative = _requiredString(reference, 'path', path, failures);
  final expectedSha = _requiredString(reference, 'sha256', path, failures);
  if (relative == null || expectedSha == null) return null;
  if (relative.startsWith('/') ||
      relative.startsWith('~') ||
      relative.split(RegExp(r'[/\\]')).contains('..')) {
    failures.add('$path.path must be a safe relative artifact path');
    return null;
  }
  if (!_isSha256(expectedSha)) {
    failures.add('$path.sha256 must be a lowercase SHA-256 digest');
    return null;
  }
  final root = artifactFile.parent.absolute.resolveSymbolicLinksSync();
  final candidate = File(
    '${artifactFile.parent.path}${Platform.pathSeparator}$relative',
  ).absolute;
  if (FileSystemEntity.typeSync(candidate.path, followLinks: false) !=
      FileSystemEntityType.file) {
    failures.add('$path.path is not a regular non-symlink evidence file');
    return null;
  }
  final resolved = candidate.resolveSymbolicLinksSync();
  if (!resolved.startsWith('$root${Platform.pathSeparator}')) {
    failures.add('$path.path escapes the proof directory');
    return null;
  }
  final bytes = await File(resolved).readAsBytes();
  if (bytes.isEmpty || bytes.length > 4 * 1024 * 1024) {
    failures.add('$path evidence must be non-empty and at most 4 MiB');
    return null;
  }
  final actualSha = sha256.convert(bytes).toString();
  if (actualSha != expectedSha) {
    failures.add('$path evidence SHA-256 mismatch');
    return null;
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    failures.add('$path evidence is not UTF-8 text');
    return null;
  }
}

Map<String, Object?>? _decodeObject(
  String text,
  String path,
  List<String> failures,
) {
  try {
    return _object(jsonDecode(text), path, failures);
  } on FormatException catch (error) {
    failures.add('$path is invalid JSON: ${error.message}');
    return null;
  }
}

Map<String, Object?>? _object(
  Object? value,
  String path,
  List<String> failures,
) {
  if (value is! Map) {
    failures.add('$path must be an object');
    return null;
  }
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
  List<String> failures,
) {
  final actual = value.keys.toSet();
  if (actual.length != expected.length ||
      !actual.containsAll(expected) ||
      !expected.containsAll(actual)) {
    failures.add('$path keys must be exactly ${expected.toList()..sort()}');
  }
}

void _expectValue(
  Map<String, Object?> value,
  String key,
  Object? expected,
  String path,
  List<String> failures,
) {
  if (value[key] != expected) {
    failures.add('$path.$key must equal $expected');
  }
}

String? _requiredString(
  Map<String, Object?> value,
  String key,
  String path,
  List<String> failures,
) {
  final item = value[key];
  if (item is! String || item.trim().isEmpty || item != item.trim()) {
    failures.add('$path.$key must be a trimmed non-empty string');
    return null;
  }
  return item;
}

int? _positiveInt(Object? value, String path, List<String> failures) {
  if (value is! int || value <= 0) {
    failures.add('$path must be a positive integer');
    return null;
  }
  return value;
}

void _expectUtcTimestamp(Object? value, String path, List<String> failures) {
  final text = value is String ? value : null;
  final timestamp = text == null ? null : DateTime.tryParse(text);
  if (timestamp == null ||
      text == null ||
      !text.endsWith('Z') ||
      !timestamp.isUtc) {
    failures.add('$path must be an ISO-8601 UTC timestamp');
  }
}

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isRegularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
    FileSystemEntityType.file;
