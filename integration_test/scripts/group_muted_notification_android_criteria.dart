import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'reaction_notification_proof_support.dart'
    show extractActiveContentNotificationCards;

const String groupMutedNotificationCapabilityId =
    'groups.muted_notification_campaign';

/// Kept `const` so they can be used in const contexts and in the proof test's
/// `test()` name. `group_muted_notification_criteria_test.dart` pins each one
/// against the matching source scenario in the shared criteria file, so the
/// hand-written equality Plan 330 left unenforced cannot silently drift here.
const String groupMutedMessageSuppressionScenarioId =
    'android_group_muted_message_suppression';
const String groupMutedReactionBackgroundScenarioId =
    'android_group_muted_reaction_background_suppression';

/// Plan 384 (G19). Deliberately shares neither a prefix nor the
/// `_message_unread_lifecycle` suffix with the two muted ids: the Plan-257
/// runner selects proof rows with an anchored `--name`, and the shared capture
/// driver routes any id carrying that suffix into the reaction grammar.
const String groupTextKilledAppCardScenarioId =
    'android_group_text_killed_app_card';
const String groupMutedNotificationArtifactSchema =
    'mknoon.plan379.android-group-muted-notification.v1';
const String groupKilledTextCardArtifactSchema =
    'mknoon.plan384.android-group-text-killed-app-card.v1';
const String groupMutedNotificationCommandJournalSchema =
    'mknoon.plan379.android-command-journal.v1';
const String plan379PhysicalAndroidDeviceId = '21071FDF600CSC';
const String plan379AndroidEmulatorDeviceId = 'emulator-5554';

const List<String> groupMutedNotificationCriteria = <String>[
  'groups.muted_live_message_no_card',
  'groups.muted_background_reaction_no_card',
  'groups.muted_unread_preserved',
  'groups.muted_excluded_from_canonical_badge',
  'groups.muted_delivery_unharmed',
  'groups.killed_app_group_text_card',
];

/// The ids this lane owns, in runner declaration order.
///
/// No id is a prefix of another: the Plan-257 runner selects proof rows with
/// an anchored `--name`, and a prefix pair is exactly what made `--plain-name`
/// run two blocks against one artifact. Plan 384's id is appended LAST so the
/// shipped pair's declaration order — and the shell census pinned against it —
/// stays byte-stable.
const List<String> groupMutedNotificationScenarioIds = <String>[
  groupMutedMessageSuppressionScenarioId,
  groupMutedReactionBackgroundScenarioId,
  groupTextKilledAppCardScenarioId,
];

// ---------------------------------------------------------------------------
// Capture input — the single shape both the device capture stages and the host
// fixtures feed into [buildGroupMutedNotificationArtifact].
// ---------------------------------------------------------------------------

final class GroupMutedNotificationBuildInput {
  const GroupMutedNotificationBuildInput({
    required this.apkSha256,
    required this.packageName,
  });

  final String apkSha256;
  final String packageName;

  GroupMutedNotificationBuildInput copyWith({
    String? apkSha256,
    String? packageName,
  }) => GroupMutedNotificationBuildInput(
    apkSha256: apkSha256 ?? this.apkSha256,
    packageName: packageName ?? this.packageName,
  );
}

final class GroupMutedNotificationTopologyInput {
  const GroupMutedNotificationTopologyInput({
    required this.physicalDeviceId,
    required this.emulatorDeviceId,
  });

  final String physicalDeviceId;
  final String emulatorDeviceId;

  GroupMutedNotificationTopologyInput copyWith({
    String? physicalDeviceId,
    String? emulatorDeviceId,
  }) => GroupMutedNotificationTopologyInput(
    physicalDeviceId: physicalDeviceId ?? this.physicalDeviceId,
    emulatorDeviceId: emulatorDeviceId ?? this.emulatorDeviceId,
  );
}

final class GroupMutedNotificationFixtureInput {
  const GroupMutedNotificationFixtureInput({
    required this.mutedGroupName,
    required this.controlGroupName,
    required this.mutedGroupIdSha256,
    required this.controlGroupIdSha256,
    required this.actorName,
  });

  final String mutedGroupName;
  final String controlGroupName;

  /// Already hashed: the in-app probe never returns a raw conversation id, so
  /// the capture only ever holds digests.
  final String mutedGroupIdSha256;
  final String controlGroupIdSha256;
  final String actorName;

  GroupMutedNotificationFixtureInput copyWith({
    String? mutedGroupName,
    String? controlGroupName,
    String? mutedGroupIdSha256,
    String? controlGroupIdSha256,
    String? actorName,
  }) => GroupMutedNotificationFixtureInput(
    mutedGroupName: mutedGroupName ?? this.mutedGroupName,
    controlGroupName: controlGroupName ?? this.controlGroupName,
    mutedGroupIdSha256: mutedGroupIdSha256 ?? this.mutedGroupIdSha256,
    controlGroupIdSha256: controlGroupIdSha256 ?? this.controlGroupIdSha256,
    actorName: actorName ?? this.actorName,
  );
}

final class GroupMutedProjectionInput {
  const GroupMutedProjectionInput({
    required this.groupIsMuted,
    required this.underTestMarker,
    required this.underTestMessageIdSha256,
    required this.underTestReadAtNull,
    required this.mutedCardCount,
    required this.unreadBaseline,
    required this.unreadAfter,
    required this.persistedRowObserved,
    required this.reactionRowsObserved,
    required this.badgeAvailable,
    required this.badgeIncludesMutedGroup,
    required this.badgeIncludesControlGroup,
    required this.badgeGroupIdentityCount,
    required this.notificationDump,
    required this.sqlcipherObservation,
  });

  final bool groupIsMuted;
  final String underTestMarker;

  /// Already hashed, for the same reason as the group digests above.
  final String underTestMessageIdSha256;
  final bool underTestReadAtNull;
  final int mutedCardCount;
  final int unreadBaseline;
  final int unreadAfter;
  final bool persistedRowObserved;

  /// Reaction rows the probe observed in the group under test. The FCM lane
  /// proves a reaction landed; the live lane proves a message landed.
  final int reactionRowsObserved;
  final bool badgeAvailable;
  final bool badgeIncludesMutedGroup;
  final bool badgeIncludesControlGroup;
  final int badgeGroupIdentityCount;

  /// Raw `dumpsys notification --noredact` text captured after the
  /// message/reaction under test landed.
  final String notificationDump;

  /// Raw `mknoon.plan257.sqlcipher-observation.v1` JSON echoed by the in-app
  /// probe. Bound to the summary fields below so a hand-edited summary alone
  /// cannot pass.
  final String sqlcipherObservation;

  GroupMutedProjectionInput copyWith({
    bool? groupIsMuted,
    String? underTestMarker,
    String? underTestMessageIdSha256,
    bool? underTestReadAtNull,
    int? mutedCardCount,
    int? unreadBaseline,
    int? unreadAfter,
    bool? persistedRowObserved,
    int? reactionRowsObserved,
    bool? badgeAvailable,
    bool? badgeIncludesMutedGroup,
    bool? badgeIncludesControlGroup,
    int? badgeGroupIdentityCount,
    String? notificationDump,
    String? sqlcipherObservation,
  }) => GroupMutedProjectionInput(
    groupIsMuted: groupIsMuted ?? this.groupIsMuted,
    underTestMarker: underTestMarker ?? this.underTestMarker,
    underTestMessageIdSha256:
        underTestMessageIdSha256 ?? this.underTestMessageIdSha256,
    underTestReadAtNull: underTestReadAtNull ?? this.underTestReadAtNull,
    mutedCardCount: mutedCardCount ?? this.mutedCardCount,
    unreadBaseline: unreadBaseline ?? this.unreadBaseline,
    unreadAfter: unreadAfter ?? this.unreadAfter,
    persistedRowObserved: persistedRowObserved ?? this.persistedRowObserved,
    reactionRowsObserved: reactionRowsObserved ?? this.reactionRowsObserved,
    badgeAvailable: badgeAvailable ?? this.badgeAvailable,
    badgeIncludesMutedGroup:
        badgeIncludesMutedGroup ?? this.badgeIncludesMutedGroup,
    badgeIncludesControlGroup:
        badgeIncludesControlGroup ?? this.badgeIncludesControlGroup,
    badgeGroupIdentityCount:
        badgeGroupIdentityCount ?? this.badgeGroupIdentityCount,
    notificationDump: notificationDump ?? this.notificationDump,
    sqlcipherObservation: sqlcipherObservation ?? this.sqlcipherObservation,
  );
}

final class GroupMutedControlInput {
  const GroupMutedControlInput({
    required this.controlMarker,
    required this.preMuteCardGroup,
    required this.preMuteCardCount,
    required this.preMuteNotificationDump,
    required this.postMuteCardCount,
    required this.postMuteNotificationDump,
  });

  final String controlMarker;

  /// `muted` for the live lane (the pre-mute card is posted by the
  /// group-to-be-muted itself) and `control` for the background lane (the
  /// baseline card belongs to the always-unmuted control group).
  final String preMuteCardGroup;
  final int preMuteCardCount;
  final String preMuteNotificationDump;
  final int postMuteCardCount;
  final String postMuteNotificationDump;

  GroupMutedControlInput copyWith({
    String? controlMarker,
    String? preMuteCardGroup,
    int? preMuteCardCount,
    String? preMuteNotificationDump,
    int? postMuteCardCount,
    String? postMuteNotificationDump,
  }) => GroupMutedControlInput(
    controlMarker: controlMarker ?? this.controlMarker,
    preMuteCardGroup: preMuteCardGroup ?? this.preMuteCardGroup,
    preMuteCardCount: preMuteCardCount ?? this.preMuteCardCount,
    preMuteNotificationDump:
        preMuteNotificationDump ?? this.preMuteNotificationDump,
    postMuteCardCount: postMuteCardCount ?? this.postMuteCardCount,
    postMuteNotificationDump:
        postMuteNotificationDump ?? this.postMuteNotificationDump,
  );
}

final class GroupMutedBackgroundDeliveryInput {
  const GroupMutedBackgroundDeliveryInput({
    required this.recipientProcessState,
    required this.mutedFcmMessageId,
    required this.controlFcmMessageId,
    required this.suppressionReason,
    required this.backgroundFlowLog,
  });

  final String recipientProcessState;
  final String mutedFcmMessageId;
  final String controlFcmMessageId;

  /// Recorded, never pinned: production `type=='group_reaction'` traffic is
  /// intercepted before the fallback resolver, so its suppression collapses
  /// into the catch-all reason rather than `muted`.
  final String suppressionReason;
  final String backgroundFlowLog;

  GroupMutedBackgroundDeliveryInput copyWith({
    String? recipientProcessState,
    String? mutedFcmMessageId,
    String? controlFcmMessageId,
    String? suppressionReason,
    String? backgroundFlowLog,
  }) => GroupMutedBackgroundDeliveryInput(
    recipientProcessState: recipientProcessState ?? this.recipientProcessState,
    mutedFcmMessageId: mutedFcmMessageId ?? this.mutedFcmMessageId,
    controlFcmMessageId: controlFcmMessageId ?? this.controlFcmMessageId,
    suppressionReason: suppressionReason ?? this.suppressionReason,
    backgroundFlowLog: backgroundFlowLog ?? this.backgroundFlowLog,
  );
}

final class GroupMutedNotificationCaptureInput {
  const GroupMutedNotificationCaptureInput({
    required this.scenario,
    required this.recordedAt,
    required this.build,
    required this.topology,
    required this.fixture,
    required this.mutedProjection,
    required this.control,
    required this.commandJournal,
    this.backgroundDelivery,
  });

  final String scenario;
  final String recordedAt;
  final GroupMutedNotificationBuildInput build;
  final GroupMutedNotificationTopologyInput topology;
  final GroupMutedNotificationFixtureInput fixture;
  final GroupMutedProjectionInput mutedProjection;
  final GroupMutedControlInput control;
  final String commandJournal;
  final GroupMutedBackgroundDeliveryInput? backgroundDelivery;

  GroupMutedNotificationCaptureInput copyWith({
    String? scenario,
    String? recordedAt,
    GroupMutedNotificationBuildInput? build,
    GroupMutedNotificationTopologyInput? topology,
    GroupMutedNotificationFixtureInput? fixture,
    GroupMutedProjectionInput? mutedProjection,
    GroupMutedControlInput? control,
    String? commandJournal,
    GroupMutedBackgroundDeliveryInput? backgroundDelivery,
  }) => GroupMutedNotificationCaptureInput(
    scenario: scenario ?? this.scenario,
    recordedAt: recordedAt ?? this.recordedAt,
    build: build ?? this.build,
    topology: topology ?? this.topology,
    fixture: fixture ?? this.fixture,
    mutedProjection: mutedProjection ?? this.mutedProjection,
    control: control ?? this.control,
    commandJournal: commandJournal ?? this.commandJournal,
    backgroundDelivery: backgroundDelivery ?? this.backgroundDelivery,
  );
}

// ---------------------------------------------------------------------------
// Shared artifact builder.
// ---------------------------------------------------------------------------

/// Writes every raw evidence blob next to the artifact and returns the artifact
/// map that references them by relative path + SHA-256.
///
/// Device capture stages and host fixtures both go through here, so a host
/// negative is always the happy artifact with exactly one input changed — a
/// validator that merely recognized hand-written fixtures could not pass the
/// host suite.
Future<Map<String, Object?>> buildGroupMutedNotificationArtifact({
  required Directory proofDirectory,
  required GroupMutedNotificationCaptureInput input,
}) async {
  if (!proofDirectory.existsSync()) {
    await proofDirectory.create(recursive: true);
  }

  Future<Map<String, Object?>> evidence(String name, String contents) async {
    final relative = '${input.scenario}_$name';
    final file = File(
      '${proofDirectory.path}${Platform.pathSeparator}$relative',
    );
    final bytes = utf8.encode(contents);
    await file.writeAsBytes(bytes, flush: true);
    return <String, Object?>{
      'path': relative,
      'sha256': sha256.convert(bytes).toString(),
    };
  }

  final projection = input.mutedProjection;
  final control = input.control;
  final delivery = input.backgroundDelivery;

  return <String, Object?>{
    'schema': groupMutedNotificationArtifactSchema,
    'version': 1,
    'capabilityId': groupMutedNotificationCapabilityId,
    'scenario': input.scenario,
    'recordedAt': input.recordedAt,
    'build': <String, Object?>{
      'profile': 'android.production_fcm',
      'provenance': 'central_prebuilt',
      'apkSha256': input.build.apkSha256,
      'childBuildCount': 0,
      'packageName': input.build.packageName,
    },
    'topology': <String, Object?>{
      'physical': <String, Object?>{
        'deviceId': input.topology.physicalDeviceId,
        'platform': 'android',
        'kind': 'physical',
      },
      'emulator': <String, Object?>{
        'deviceId': input.topology.emulatorDeviceId,
        'platform': 'android',
        'kind': 'emulator',
      },
    },
    'fixture': <String, Object?>{
      'mutedGroupName': input.fixture.mutedGroupName,
      'controlGroupName': input.fixture.controlGroupName,
      'mutedGroupIdSha256': input.fixture.mutedGroupIdSha256,
      'controlGroupIdSha256': input.fixture.controlGroupIdSha256,
      'actorName': input.fixture.actorName,
    },
    'mutedProjection': <String, Object?>{
      'groupIsMuted': projection.groupIsMuted,
      'underTestMarker': projection.underTestMarker,
      'underTestMessageIdSha256': projection.underTestMessageIdSha256,
      'underTestReadAtNull': projection.underTestReadAtNull,
      'mutedCardCount': projection.mutedCardCount,
      'unreadBaseline': projection.unreadBaseline,
      'unreadAfter': projection.unreadAfter,
      'persistedRowObserved': projection.persistedRowObserved,
      'reactionRowsObserved': projection.reactionRowsObserved,
      'badge': <String, Object?>{
        'available': projection.badgeAvailable,
        'includesMutedGroup': projection.badgeIncludesMutedGroup,
        'includesControlGroup': projection.badgeIncludesControlGroup,
        'groupIdentityCount': projection.badgeGroupIdentityCount,
      },
      'notificationDump': await evidence(
        'muted_notification_dump.txt',
        projection.notificationDump,
      ),
      'sqlcipherObservation': await evidence(
        'sqlcipher_observation.json',
        projection.sqlcipherObservation,
      ),
    },
    'control': <String, Object?>{
      'controlMarker': control.controlMarker,
      'preMuteCardGroup': control.preMuteCardGroup,
      'preMuteCardCount': control.preMuteCardCount,
      'preMuteNotificationDump': await evidence(
        'pre_mute_notification_dump.txt',
        control.preMuteNotificationDump,
      ),
      'postMuteCardCount': control.postMuteCardCount,
      'postMuteNotificationDump': await evidence(
        'post_mute_notification_dump.txt',
        control.postMuteNotificationDump,
      ),
    },
    if (delivery != null)
      'backgroundDelivery': <String, Object?>{
        'recipientProcessState': delivery.recipientProcessState,
        'mutedFcmMessageIdSha256': _sha256Text(delivery.mutedFcmMessageId),
        'controlFcmMessageIdSha256': _sha256Text(delivery.controlFcmMessageId),
        'suppressionReason': delivery.suppressionReason,
        'backgroundFlowLog': await evidence(
          'background_flow.log',
          delivery.backgroundFlowLog,
        ),
      },
    'automation': <String, Object?>{
      'manualTaps': 0,
      'notificationCardTaps': 0,
      'commandJournal': await evidence(
        'command_journal.json',
        input.commandJournal,
      ),
    },
  };
}

/// Builds and writes `<scenario>.json` into [proofDirectory].
Future<File> writeGroupMutedNotificationArtifact({
  required Directory proofDirectory,
  required GroupMutedNotificationCaptureInput input,
}) async {
  final artifact = await buildGroupMutedNotificationArtifact(
    proofDirectory: proofDirectory,
    input: input,
  );
  final file = File(
    '${proofDirectory.path}${Platform.pathSeparator}${input.scenario}.json',
  );
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(artifact),
    flush: true,
  );
  return file;
}

// ---------------------------------------------------------------------------
// Validator.
// ---------------------------------------------------------------------------

final class GroupMutedNotificationArtifactValidation {
  GroupMutedNotificationArtifactValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

/// Validates a Plan-379 muted-group Android proof.
///
/// Deliberately does NOT reuse the Plan-257 reaction grammar: that validator
/// hard-requires a non-zero unread count, per-branch notification cards, and
/// relay/provider `[PUSH] … sent to` lines. This lane asserts the negation of
/// the first two and never reads relay push grammar at all — the relay has no
/// mute knowledge, so delivery is proven at the recipient boundary.
///
/// Every summary boolean is re-derived from a content-addressed raw capture
/// stored next to [artifactFile]: a summary claiming "zero cards" while the raw
/// dump still shows one is rejected.
Future<GroupMutedNotificationArtifactValidation>
validateGroupMutedNotificationAndroidArtifact({
  required File artifactFile,
  String expectedPhysicalDeviceId = plan379PhysicalAndroidDeviceId,
  String expectedEmulatorDeviceId = plan379AndroidEmulatorDeviceId,
  String? expectedApkSha256,
  String? expectedPackageName,
}) async {
  final failures = <String>[];
  if (!_isRegularFile(artifactFile)) {
    return GroupMutedNotificationArtifactValidation(<String>[
      'proof artifact is not a regular file: ${artifactFile.path}',
    ]);
  }

  final artifact = _decodeObject(
    await artifactFile.readAsString(),
    r'$',
    failures,
  );
  if (artifact == null) {
    return GroupMutedNotificationArtifactValidation(failures);
  }

  final scenario = artifact['scenario'];
  final isBackgroundLane = scenario == groupMutedReactionBackgroundScenarioId;
  if (scenario != groupMutedMessageSuppressionScenarioId && !isBackgroundLane) {
    failures.add(r'$.scenario is not a Plan 379 muted scenario');
    return GroupMutedNotificationArtifactValidation(failures);
  }

  _expectExactKeys(
    artifact,
    <String>{
      'schema',
      'version',
      'capabilityId',
      'scenario',
      'recordedAt',
      'build',
      'topology',
      'fixture',
      'mutedProjection',
      'control',
      if (isBackgroundLane) 'backgroundDelivery',
      'automation',
    },
    r'$',
    failures,
  );
  _expectValue(
    artifact,
    'schema',
    groupMutedNotificationArtifactSchema,
    r'$',
    failures,
  );
  _expectValue(artifact, 'version', 1, r'$', failures);
  _expectValue(
    artifact,
    'capabilityId',
    groupMutedNotificationCapabilityId,
    r'$',
    failures,
  );
  _expectUtcTimestamp(artifact['recordedAt'], r'$.recordedAt', failures);

  final packageName = _validateBuild(
    artifact['build'],
    expectedApkSha256: expectedApkSha256,
    expectedPackageName: expectedPackageName,
    failures: failures,
  );
  _validateTopology(
    artifact['topology'],
    expectedPhysicalDeviceId: expectedPhysicalDeviceId,
    expectedEmulatorDeviceId: expectedEmulatorDeviceId,
    failures: failures,
  );

  final fixture = _object(artifact['fixture'], r'$.fixture', failures);
  var mutedGroupName = '';
  var controlGroupName = '';
  if (fixture != null) {
    _expectExactKeys(
      fixture,
      const <String>{
        'mutedGroupName',
        'controlGroupName',
        'mutedGroupIdSha256',
        'controlGroupIdSha256',
        'actorName',
      },
      r'$.fixture',
      failures,
    );
    mutedGroupName =
        _requiredString(fixture, 'mutedGroupName', r'$.fixture', failures) ??
        '';
    controlGroupName =
        _requiredString(fixture, 'controlGroupName', r'$.fixture', failures) ??
        '';
    if (!RegExp(r'^Plan379M-[A-Za-z0-9]{6,32}$').hasMatch(mutedGroupName)) {
      failures.add(r'$.fixture.mutedGroupName is not a disposable M fixture');
    }
    if (!RegExp(r'^Plan379C-[A-Za-z0-9]{6,32}$').hasMatch(controlGroupName) ||
        mutedGroupName == controlGroupName) {
      failures.add(
        r'$.fixture.controlGroupName is not a distinct control fixture',
      );
    }
    _requiredString(fixture, 'actorName', r'$.fixture', failures);
    for (final key in const <String>[
      'mutedGroupIdSha256',
      'controlGroupIdSha256',
    ]) {
      if (!_isSha256(fixture[key])) {
        failures.add(
          r'$.fixture.'
          '$key must be a SHA-256 digest',
        );
      }
    }
    if (fixture['mutedGroupIdSha256'] == fixture['controlGroupIdSha256']) {
      failures.add(r'$.fixture group identity digests must differ');
    }
  }

  await _validateMutedProjection(
    artifact['mutedProjection'],
    artifactFile: artifactFile,
    packageName: packageName,
    mutedGroupName: mutedGroupName,
    controlGroupName: controlGroupName,
    isBackgroundLane: isBackgroundLane,
    failures: failures,
  );

  await _validateControl(
    artifact['control'],
    artifactFile: artifactFile,
    packageName: packageName,
    mutedGroupName: mutedGroupName,
    controlGroupName: controlGroupName,
    expectedPreMuteCardGroup: isBackgroundLane ? 'control' : 'muted',
    failures: failures,
  );

  if (isBackgroundLane) {
    await _validateBackgroundDelivery(
      artifact['backgroundDelivery'],
      artifactFile: artifactFile,
      failures: failures,
    );
  } else if (artifact.containsKey('backgroundDelivery')) {
    failures.add(
      r'$.backgroundDelivery must be absent on the live suppression lane',
    );
  }

  await _validateAutomation(
    artifact['automation'],
    artifactFile: artifactFile,
    controlGroupName: controlGroupName,
    requireControlVisit: !isBackgroundLane,
    failures: failures,
  );

  return GroupMutedNotificationArtifactValidation(failures);
}

String _validateBuild(
  Object? value, {
  required String? expectedApkSha256,
  required String? expectedPackageName,
  required List<String> failures,
}) {
  final build = _object(value, r'$.build', failures);
  if (build == null) return '';
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
  final packageName =
      _requiredString(build, 'packageName', r'$.build', failures) ?? '';
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$').hasMatch(packageName)) {
    failures.add(r'$.build.packageName is not a safe Android package');
  }
  if (expectedPackageName != null && packageName != expectedPackageName) {
    failures.add(r'$.build.packageName does not match the prepared app');
  }
  return packageName;
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

Future<void> _validateMutedProjection(
  Object? value, {
  required File artifactFile,
  required String packageName,
  required String mutedGroupName,
  required String controlGroupName,
  required bool isBackgroundLane,
  required List<String> failures,
}) async {
  const path = r'$.mutedProjection';
  final projection = _object(value, path, failures);
  if (projection == null) return;
  _expectExactKeys(
    projection,
    const <String>{
      'groupIsMuted',
      'underTestMarker',
      'underTestMessageIdSha256',
      'underTestReadAtNull',
      'mutedCardCount',
      'unreadBaseline',
      'unreadAfter',
      'persistedRowObserved',
      'reactionRowsObserved',
      'badge',
      'notificationDump',
      'sqlcipherObservation',
    },
    path,
    failures,
  );

  if (projection['groupIsMuted'] != true) {
    failures.add(
      '$path.groupIsMuted must be true — a false or absent value means the '
      'Group Info mute toggle never landed, so nothing below proves mute',
    );
  }
  final marker = _requiredString(projection, 'underTestMarker', path, failures);
  if (!_isSha256(projection['underTestMessageIdSha256'])) {
    failures.add('$path.underTestMessageIdSha256 must be a SHA-256 digest');
  }
  // Lane-aware: the live lane's message under test is INCOMING, so unread
  // must grow and read_at must stay NULL. The FCM lane reacts to a message the
  // recipient itself authored, so neither applies there — it proves a reaction
  // row landed instead. Applying the live rules to both would make the FCM
  // lane unpassable for a correct capture.
  if (!isBackgroundLane && projection['underTestReadAtNull'] != true) {
    failures.add(
      '$path.underTestReadAtNull must be true — the suppressed message must '
      'keep read_at NULL',
    );
  }
  final reactionRows = projection['reactionRowsObserved'];
  if (reactionRows is! int || reactionRows < 0) {
    failures.add('$path.reactionRowsObserved must be a non-negative integer');
  } else if (isBackgroundLane && reactionRows < 1) {
    failures.add(
      '$path.reactionRowsObserved must be at least 1 — the suppressed '
      'reaction must still be persisted',
    );
  }
  _expectValue(projection, 'mutedCardCount', 0, path, failures);
  if (projection['persistedRowObserved'] != true) {
    failures.add('$path.persistedRowObserved must be true');
  }

  final baseline = projection['unreadBaseline'];
  final after = projection['unreadAfter'];
  if (baseline is! int || baseline < 0) {
    failures.add('$path.unreadBaseline must be a non-negative integer');
  }
  if (after is! int) {
    failures.add('$path.unreadAfter must be an integer');
  }
  if (baseline is int && after is int) {
    if (after < baseline) {
      failures.add(
        '$path unread regressed below the pre-send baseline '
        '($after is less than $baseline)',
      );
    } else if (!isBackgroundLane && after <= baseline) {
      failures.add(
        '$path unread must grow past the pre-send baseline '
        '($after is not greater than $baseline)',
      );
    }
  }

  final badge = _object(projection['badge'], '$path.badge', failures);
  if (badge != null) {
    _expectExactKeys(
      badge,
      const <String>{
        'available',
        'includesMutedGroup',
        'includesControlGroup',
        'groupIdentityCount',
      },
      '$path.badge',
      failures,
    );
    if (badge['available'] != true) {
      failures.add(
        '$path.badge.available must be true — an unavailable badge projection '
        'cannot prove exclusion',
      );
    }
    if (badge['includesMutedGroup'] != false) {
      failures.add('$path.badge.includesMutedGroup must be false');
    }
    if (badge['includesControlGroup'] != true) {
      failures.add(
        '$path.badge.includesControlGroup must be true — losing the unmuted '
        'control group would mean the badge projection is empty, not excluding',
      );
    }
    final identityCount = badge['groupIdentityCount'];
    if (identityCount is! int || identityCount < 1) {
      failures.add('$path.badge.groupIdentityCount must be a positive integer');
    }
  }

  final dump = await _readEvidence(
    projection['notificationDump'],
    artifactFile: artifactFile,
    path: '$path.notificationDump',
    failures: failures,
  );
  if (dump != null && packageName.isNotEmpty) {
    if (!dump.contains('NotificationRecord(')) {
      failures.add(
        '$path.notificationDump is not a raw Android notification dump',
      );
    } else {
      final cards = extractActiveContentNotificationCards(
        dump,
        packageName: packageName,
      );
      final offending = cards
          .where(
            (card) =>
                card.title == mutedGroupName ||
                (marker != null &&
                    marker.isNotEmpty &&
                    (card.title.contains(marker) ||
                        card.body.contains(marker))),
          )
          .toList(growable: false);
      if (offending.isNotEmpty) {
        failures.add(
          '$path.notificationDump raw records still show '
          '${offending.length} card(s) for the muted group or the message '
          'under test, so the zero-card summary is not truthful',
        );
      }
      final controlCards = cards
          .where((card) => card.title == controlGroupName)
          .toList(growable: false);
      if (controlCards.isEmpty) {
        failures.add(
          '$path.notificationDump contains no unmuted control card, so an '
          'empty or wrong-package dump would read as suppression',
        );
      }
    }
  }

  final observationText = await _readEvidence(
    projection['sqlcipherObservation'],
    artifactFile: artifactFile,
    path: '$path.sqlcipherObservation',
    failures: failures,
  );
  if (observationText != null) {
    const observationPath = '$path.sqlcipherObservation';
    final observation = _decodeObject(
      observationText,
      observationPath,
      failures,
    );
    if (observation != null) {
      _expectValue(
        observation,
        'schema',
        'mknoon.plan257.sqlcipher-observation.v1',
        observationPath,
        failures,
      );
      if (observation['groupIsMuted'] != true) {
        failures.add(
          '$observationPath.groupIsMuted must be true in the raw probe '
          'observation backing the summary',
        );
      }
      if (observation['unreadCount'] != projection['unreadAfter']) {
        failures.add(
          '$observationPath.unreadCount does not match '
          '$path.unreadAfter',
        );
      }
      final badgeState = _object(
        observation['canonicalBadgeState'],
        '$observationPath.canonicalBadgeState',
        failures,
      );
      if (badgeState != null) {
        if (badgeState['available'] != true) {
          failures.add(
            '$observationPath.canonicalBadgeState.available must be true',
          );
        }
        if (badgeState['includesObservedGroup'] != false) {
          failures.add(
            '$observationPath.canonicalBadgeState still includes the muted '
            'group in the badge projection',
          );
        }
      }
    }
  }
}

Future<void> _validateControl(
  Object? value, {
  required File artifactFile,
  required String packageName,
  required String mutedGroupName,
  required String controlGroupName,
  required String expectedPreMuteCardGroup,
  required List<String> failures,
}) async {
  const path = r'$.control';
  final control = _object(value, path, failures);
  if (control == null) return;
  _expectExactKeys(
    control,
    const <String>{
      'controlMarker',
      'preMuteCardGroup',
      'preMuteCardCount',
      'preMuteNotificationDump',
      'postMuteCardCount',
      'postMuteNotificationDump',
    },
    path,
    failures,
  );
  _requiredString(control, 'controlMarker', path, failures);
  _expectValue(
    control,
    'preMuteCardGroup',
    expectedPreMuteCardGroup,
    path,
    failures,
  );
  // At least one, not exactly one: the FCM lane's control group legitimately
  // holds a baseline message card AND a reaction card. What this control must
  // prove is that the notification lane was alive, which >= 1 captures. The
  // muted side stays exact (zero) — that is the assertion under test.
  _expectAtLeast(control, 'preMuteCardCount', 1, path, failures);
  _expectAtLeast(control, 'postMuteCardCount', 1, path, failures);

  final baselineGroupName = expectedPreMuteCardGroup == 'muted'
      ? mutedGroupName
      : controlGroupName;
  final preDump = await _readEvidence(
    control['preMuteNotificationDump'],
    artifactFile: artifactFile,
    path: '$path.preMuteNotificationDump',
    failures: failures,
  );
  if (preDump != null && packageName.isNotEmpty) {
    final cards = extractActiveContentNotificationCards(
      preDump,
      packageName: packageName,
    ).where((card) => card.title == baselineGroupName).toList(growable: false);
    if (cards.length != 1) {
      failures.add(
        '$path.preMuteNotificationDump must show exactly one baseline card '
        'for $baselineGroupName, proving the lane, package, and parser were '
        'live before the suppression window',
      );
    }
  }

  final postDump = await _readEvidence(
    control['postMuteNotificationDump'],
    artifactFile: artifactFile,
    path: '$path.postMuteNotificationDump',
    failures: failures,
  );
  if (postDump != null && packageName.isNotEmpty) {
    final cards = extractActiveContentNotificationCards(
      postDump,
      packageName: packageName,
    );
    final controlCards = cards
        .where((card) => card.title == controlGroupName)
        .toList(growable: false);
    if (controlCards.length != 1) {
      failures.add(
        '$path.postMuteNotificationDump must show exactly one control card '
        'for $controlGroupName inside the suppression window — without it a '
        'dead notification lane is indistinguishable from mute',
      );
    }
    if (cards.any((card) => card.title == mutedGroupName)) {
      failures.add(
        '$path.postMuteNotificationDump still shows a muted-group card',
      );
    }
  }
}

Future<void> _validateBackgroundDelivery(
  Object? value, {
  required File artifactFile,
  required List<String> failures,
}) async {
  const path = r'$.backgroundDelivery';
  final delivery = _object(value, path, failures);
  if (delivery == null) return;
  _expectExactKeys(
    delivery,
    const <String>{
      'recipientProcessState',
      'mutedFcmMessageIdSha256',
      'controlFcmMessageIdSha256',
      'suppressionReason',
      'backgroundFlowLog',
    },
    path,
    failures,
  );
  final processState = delivery['recipientProcessState'];
  if (processState != 'backgrounded' && processState != 'terminated') {
    failures.add(
      '$path.recipientProcessState must be backgrounded or terminated — a '
      'foregrounded recipient does not exercise the FCM isolate',
    );
  }
  final mutedDigest = delivery['mutedFcmMessageIdSha256'];
  final controlDigest = delivery['controlFcmMessageIdSha256'];
  for (final entry in <(String, Object?)>[
    ('mutedFcmMessageIdSha256', mutedDigest),
    ('controlFcmMessageIdSha256', controlDigest),
  ]) {
    if (!_isSha256(entry.$2)) {
      failures.add('$path.${entry.$1} must be a SHA-256 digest');
    }
  }
  if (mutedDigest == controlDigest) {
    failures.add('$path muted and control push digests must differ');
  }
  final reason = _requiredString(delivery, 'suppressionReason', path, failures);

  final log = await _readEvidence(
    delivery['backgroundFlowLog'],
    artifactFile: artifactFile,
    path: '$path.backgroundFlowLog',
    failures: failures,
  );
  if (log == null) return;

  final receivedDigests = _flowEventMessageDigests(
    log,
    'PUSH_BACKGROUND_MESSAGE_RECEIVED',
  );
  for (final entry in <(String, Object?)>[
    ('muted', mutedDigest),
    ('control', controlDigest),
  ]) {
    if (entry.$2 is String && !receivedDigests.contains(entry.$2)) {
      failures.add(
        '$path.backgroundFlowLog lacks a PUSH_BACKGROUND_MESSAGE_RECEIVED '
        'event for the ${entry.$1} push — without both, the background '
        'isolate is not proven to have run',
      );
    }
  }

  // The FIRST post-kill wake spawns the background isolate and opens SQLCipher
  // from cold. Measured on the pinned Pixel (2026-08-18, both campaign runs)
  // that open is still in flight 2.1s after the wake, past the 2s
  // `display_eligibility` phase budget, so the push exits at
  // PUSH_BACKGROUND_STORAGE_DEFERRED UPSTREAM of the mute gate and presents
  // nothing. A graded push in that position is silent for a reason that has
  // nothing to do with mute, so the lane must land a throwaway warm-up first.
  if (receivedDigests.length < 3) {
    failures.add(
      '$path.backgroundFlowLog records ${receivedDigests.length} post-kill '
      'wakes; the lane must land a warm-up wake BEFORE both graded pushes so '
      'neither absorbs the cold-start storage deferral',
    );
  }
  if (receivedDigests.isNotEmpty && mutedDigest == receivedDigests.first) {
    failures.add(
      '$path the muted push is the FIRST post-kill wake, so its silence is the '
      'cold-start storage deferral rather than mute',
    );
  }
  if (receivedDigests.isNotEmpty && controlDigest == receivedDigests.first) {
    failures.add(
      '$path the unmuted control push is the FIRST post-kill wake, so it '
      'cannot show the background path is able to present a card',
    );
  }

  final suppressedDigests = _flowEventMessageDigests(
    log,
    'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
  );
  if (mutedDigest is String && !suppressedDigests.contains(mutedDigest)) {
    failures.add(
      '$path.backgroundFlowLog lacks a PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED '
      'event bound to the muted push message id',
    );
  }

  // Post-Plan-383 the killed-app path really does present a card, so the
  // pipeline-health control is bound to its OWN push rather than inferred from
  // a card that could have been posted before the window opened.
  final shownDigests = _flowEventMessageDigests(
    log,
    'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
  );
  if (controlDigest is String && !shownDigests.contains(controlDigest)) {
    failures.add(
      '$path.backgroundFlowLog lacks a PUSH_BACKGROUND_NOTIFICATION_SHOWN '
      'event bound to the unmuted control push, so the control card is not '
      'attributable to the push under observation',
    );
  }
  if (mutedDigest is String && shownDigests.contains(mutedDigest)) {
    failures.add('$path.backgroundFlowLog presented a card for the muted push');
  }
  if (controlDigest is String && suppressedDigests.contains(controlDigest)) {
    failures.add(
      '$path.backgroundFlowLog suppressed the unmuted control push, so the '
      'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED evidence does not attribute to '
      'mute',
    );
  }
  if (reason != null && !log.contains(reason)) {
    failures.add(
      '$path.suppressionReason is not present in the raw background flow log',
    );
  }
}

Future<void> _validateAutomation(
  Object? value, {
  required File artifactFile,
  required String controlGroupName,
  required bool requireControlVisit,
  required List<String> failures,
}) async {
  const path = r'$.automation';
  final automation = _object(value, path, failures);
  if (automation == null) return;
  _expectExactKeys(
    automation,
    const <String>{'manualTaps', 'notificationCardTaps', 'commandJournal'},
    path,
    failures,
  );
  _expectValue(automation, 'manualTaps', 0, path, failures);
  _expectValue(automation, 'notificationCardTaps', 0, path, failures);

  final text = await _readEvidence(
    automation['commandJournal'],
    artifactFile: artifactFile,
    path: '$path.commandJournal',
    failures: failures,
  );
  if (text == null) return;
  final journal = _decodeObject(text, '$path.commandJournal', failures);
  if (journal == null) return;
  _expectExactKeys(
    journal,
    const <String>{'schema', 'commands'},
    '$path.commandJournal',
    failures,
  );
  _expectValue(
    journal,
    'schema',
    groupMutedNotificationCommandJournalSchema,
    '$path.commandJournal',
    failures,
  );
  final commands = journal['commands'];
  if (commands is! List || commands.isEmpty) {
    failures.add('$path.commandJournal.commands must be non-empty');
    return;
  }

  var muteToggleAt = -1;
  var controlVisitAt = -1;
  for (var index = 0; index < commands.length; index += 1) {
    final commandPath = '$path.commandJournal.commands[$index]';
    final command = _object(commands[index], commandPath, failures);
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
      commandPath,
      failures,
    );
    final stage = '${command['stage'] ?? ''}';
    final action = '${command['action'] ?? ''}';
    final semanticTarget = '${command['semanticTarget'] ?? ''}';
    _expectUtcTimestamp(
      command['recordedAt'],
      '$commandPath.recordedAt',
      failures,
    );
    if (stage == 'mute_toggle' &&
        action == 'tap' &&
        semanticTarget == 'Mute Notifications') {
      muteToggleAt = index;
    }
    if (stage == 'control_visit' &&
        action == 'tap' &&
        semanticTarget == 'Open group $controlGroupName') {
      controlVisitAt = index;
    }
    if (action == 'tap_notification' ||
        stage.contains('notification_shade') ||
        semanticTarget.contains('notification card')) {
      failures.add('$commandPath records a forbidden notification-card action');
    }
  }
  if (muteToggleAt < 0) {
    failures.add(
      '$path.commandJournal lacks the automated Group Info mute toggle',
    );
  }
  if (requireControlVisit && controlVisitAt <= muteToggleAt) {
    failures.add(
      '$path.commandJournal lacks the post-mute unmuted-control visit that '
      'overwrites the conversation tracker, so a visibility-suppression '
      'confound would be indistinguishable from mute',
    );
  }
}

/// Raw `messageId` values carried by each named flow event, in log order.
///
/// Order matters: the FIRST `PUSH_BACKGROUND_MESSAGE_RECEIVED` after a kill is
/// the wake that pays the isolate's cold first-touch warm-up, and a push in that
/// position proves nothing about display policy (see
/// [resolveMutedBackgroundPushBinding]).
List<String> flowEventMessageIdsInOrder(String log, String eventName) {
  final ids = <String>[];
  for (final line in log.split('\n')) {
    if (!line.contains(eventName)) continue;
    final match = RegExp(r'"messageId"\s*:\s*"([^"]+)"').firstMatch(line);
    if (match == null) continue;
    final id = match.group(1)!;
    if (!ids.contains(id)) ids.add(id);
  }
  return List<String>.unmodifiable(ids);
}

/// SHA-256 digests of the `messageId` carried by each named flow event, in log
/// order and deduplicated.
List<String> _flowEventMessageDigests(String log, String eventName) =>
    flowEventMessageIdsInOrder(
      log,
      eventName,
    ).map(_sha256Text).toList(growable: false);

/// The three post-kill wakes the muted background lane grades, resolved from
/// the recipient's own raw flow log.
///
/// [warmupFcmMessageId] is the cold-start absorber: on a killed app the first
/// FCM wake spawns the background isolate cold, and its first-touch warm-up
/// (ART profile install, Go-runtime dlopen, first encrypted-store open) can
/// outrun the 2s `display_eligibility` phase budget, so that push exits at
/// `PUSH_BACKGROUND_STORAGE_DEFERRED` UPSTREAM of the mute gate. It is
/// deliberately not graded.
final class MutedBackgroundPushBinding {
  const MutedBackgroundPushBinding({
    required this.warmupFcmMessageId,
    required this.mutedFcmMessageId,
    required this.controlFcmMessageId,
  });

  final String warmupFcmMessageId;
  final String mutedFcmMessageId;
  final String controlFcmMessageId;
}

/// Binds the muted and unmuted-control pushes, or returns null when the log
/// cannot distinguish them.
///
/// Fails closed rather than guessing: the caller turns null into a capture
/// failure carrying the raw counts. Neither graded push may be the warm-up,
/// the muted push must be the one the mute gate suppressed, and the control
/// push must be the one the presenter actually showed.
MutedBackgroundPushBinding? resolveMutedBackgroundPushBinding(String flowLog) {
  final received = flowEventMessageIdsInOrder(
    flowLog,
    'PUSH_BACKGROUND_MESSAGE_RECEIVED',
  );
  if (received.length < 3) return null;
  final warmup = received.first;
  final graded = received.skip(1).toSet();

  final suppressed = flowEventMessageIdsInOrder(
    flowLog,
    'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
  ).where(graded.contains).toList(growable: false);
  if (suppressed.isEmpty) return null;
  final muted = suppressed.first;

  final shown = flowEventMessageIdsInOrder(
    flowLog,
    'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
  ).where((id) => graded.contains(id) && id != muted).toList(growable: false);
  if (shown.isEmpty) return null;

  return MutedBackgroundPushBinding(
    warmupFcmMessageId: warmup,
    mutedFcmMessageId: muted,
    controlFcmMessageId: shown.last,
  );
}

// ---------------------------------------------------------------------------
// Shared low-level helpers (mirrors of the Plan-330 lane's private helpers).
// ---------------------------------------------------------------------------

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
  if (sha256.convert(bytes).toString() != expectedSha) {
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

void _expectAtLeast(
  Map<String, Object?> value,
  String key,
  int minimum,
  String path,
  List<String> failures,
) {
  final actual = value[key];
  if (actual is! int || actual < minimum) {
    failures.add('$path.$key must be an integer >= $minimum');
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

String _sha256Text(String value) =>
    sha256.convert(utf8.encode(value)).toString();

// ===========================================================================
// Plan 384 (G19) — killed-app group TEXT card.
//
// Same lane, same pinned pair, same prebuilt APK, its own artifact grammar.
// The muted validator asserts the ABSENCE of a card for the group under test;
// this scenario asserts its PRESENCE, so the two cannot share a validator and
// the muted admission is deliberately left untouched.
//
// What it closes: a killed Android app receiving a default-lane group text
// posted no OS card at all. The push died at
// `PUSH_ANDROID_DATA_DECRYPT_FAIL{group_parity_mismatch}` because the Go live
// envelope carries no inner sender key and the parity predicate's sender
// clause had no null guard.
// ===========================================================================

/// The two post-kill wakes this lane grades, resolved from the recipient's own
/// raw flow log.
///
/// [warmupFcmMessageId] is the cold-start absorber: the FIRST wake after a kill
/// spawns the background isolate cold, and its first-touch warm-up can outrun
/// the 2s `display_eligibility` phase budget, so that push exits at
/// `PUSH_BACKGROUND_STORAGE_DEFERRED` upstream of everything this lane grades.
/// It is deliberately not graded.
final class KilledTextCardPushBinding {
  const KilledTextCardPushBinding({
    required this.warmupFcmMessageId,
    required this.gradedFcmMessageId,
  });

  final String warmupFcmMessageId;
  final String gradedFcmMessageId;
}

/// Binds the graded killed-path push, or returns null when the log cannot
/// distinguish it.
///
/// Fails closed rather than guessing: the caller turns null into a capture
/// failure carrying the raw counts. The graded push may never be the warm-up,
/// and it must be the one the presenter actually showed.
KilledTextCardPushBinding? resolveKilledTextCardPushBinding(String flowLog) {
  final received = flowEventMessageIdsInOrder(
    flowLog,
    'PUSH_BACKGROUND_MESSAGE_RECEIVED',
  );
  if (received.length < 2) return null;
  final warmup = received.first;
  final graded = received.skip(1).toSet();

  final shown = flowEventMessageIdsInOrder(
    flowLog,
    'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
  ).where(graded.contains).toList(growable: false);
  if (shown.isEmpty) return null;

  return KilledTextCardPushBinding(
    warmupFcmMessageId: warmup,
    gradedFcmMessageId: shown.last,
  );
}

/// Counts raw log lines carrying [eventName].
///
/// `PUSH_BACKGROUND_NOTIFICATION_ERROR` details are `{'error': …}` only — the
/// event carries no message id — so an id-bound rule is unimplementable and
/// the lane grades the accumulated post-kill window instead. The window holds
/// exactly the warm-up and the graded wake, and post-fix neither may error.
int countFlowEventLines(String log, String eventName) =>
    log.split('\n').where((line) => line.contains(eventName)).length;

final class GroupKilledTextCardFixtureInput {
  const GroupKilledTextCardFixtureInput({
    required this.groupName,
    required this.baselineMarker,
    required this.warmupMarker,
    required this.gradedMarker,
  });

  final String groupName;

  /// Pre-kill, alive-lane control: proves this build/install can card at all
  /// before the process is terminated.
  final String baselineMarker;

  /// The throwaway push that absorbs the cold-start storage deferral.
  final String warmupMarker;
  final String gradedMarker;

  GroupKilledTextCardFixtureInput copyWith({
    String? groupName,
    String? baselineMarker,
    String? warmupMarker,
    String? gradedMarker,
  }) => GroupKilledTextCardFixtureInput(
    groupName: groupName ?? this.groupName,
    baselineMarker: baselineMarker ?? this.baselineMarker,
    warmupMarker: warmupMarker ?? this.warmupMarker,
    gradedMarker: gradedMarker ?? this.gradedMarker,
  );
}

final class GroupKilledTextCardDeliveryInput {
  const GroupKilledTextCardDeliveryInput({
    required this.recipientProcessState,
    required this.warmupFcmMessageId,
    required this.gradedFcmMessageId,
    required this.backgroundFlowLog,
  });

  final String recipientProcessState;
  final String warmupFcmMessageId;
  final String gradedFcmMessageId;
  final String backgroundFlowLog;

  GroupKilledTextCardDeliveryInput copyWith({
    String? recipientProcessState,
    String? warmupFcmMessageId,
    String? gradedFcmMessageId,
    String? backgroundFlowLog,
  }) => GroupKilledTextCardDeliveryInput(
    recipientProcessState: recipientProcessState ?? this.recipientProcessState,
    warmupFcmMessageId: warmupFcmMessageId ?? this.warmupFcmMessageId,
    gradedFcmMessageId: gradedFcmMessageId ?? this.gradedFcmMessageId,
    backgroundFlowLog: backgroundFlowLog ?? this.backgroundFlowLog,
  );
}

final class GroupKilledTextCardCardInput {
  const GroupKilledTextCardCardInput({
    required this.preKillCardCount,
    required this.preKillNotificationDump,
    required this.gradedCardCount,
    required this.gradedNotificationDump,
  });

  final int preKillCardCount;
  final String preKillNotificationDump;
  final int gradedCardCount;
  final String gradedNotificationDump;

  GroupKilledTextCardCardInput copyWith({
    int? preKillCardCount,
    String? preKillNotificationDump,
    int? gradedCardCount,
    String? gradedNotificationDump,
  }) => GroupKilledTextCardCardInput(
    preKillCardCount: preKillCardCount ?? this.preKillCardCount,
    preKillNotificationDump:
        preKillNotificationDump ?? this.preKillNotificationDump,
    gradedCardCount: gradedCardCount ?? this.gradedCardCount,
    gradedNotificationDump:
        gradedNotificationDump ?? this.gradedNotificationDump,
  );
}

final class GroupKilledTextCardCaptureInput {
  const GroupKilledTextCardCaptureInput({
    required this.recordedAt,
    required this.build,
    required this.topology,
    required this.fixture,
    required this.delivery,
    required this.card,
    required this.commandJournal,
  });

  final String recordedAt;
  final GroupMutedNotificationBuildInput build;
  final GroupMutedNotificationTopologyInput topology;
  final GroupKilledTextCardFixtureInput fixture;
  final GroupKilledTextCardDeliveryInput delivery;
  final GroupKilledTextCardCardInput card;
  final String commandJournal;

  GroupKilledTextCardCaptureInput copyWith({
    String? recordedAt,
    GroupMutedNotificationBuildInput? build,
    GroupMutedNotificationTopologyInput? topology,
    GroupKilledTextCardFixtureInput? fixture,
    GroupKilledTextCardDeliveryInput? delivery,
    GroupKilledTextCardCardInput? card,
    String? commandJournal,
  }) => GroupKilledTextCardCaptureInput(
    recordedAt: recordedAt ?? this.recordedAt,
    build: build ?? this.build,
    topology: topology ?? this.topology,
    fixture: fixture ?? this.fixture,
    delivery: delivery ?? this.delivery,
    card: card ?? this.card,
    commandJournal: commandJournal ?? this.commandJournal,
  );
}

/// Writes every raw evidence blob next to the artifact and returns the artifact
/// map that references them by relative path + SHA-256.
Future<Map<String, Object?>> buildGroupKilledTextCardArtifact({
  required Directory proofDirectory,
  required GroupKilledTextCardCaptureInput input,
}) async {
  if (!proofDirectory.existsSync()) {
    await proofDirectory.create(recursive: true);
  }

  Future<Map<String, Object?>> evidence(String name, String contents) async {
    final relative = '${groupTextKilledAppCardScenarioId}_$name';
    final file = File(
      '${proofDirectory.path}${Platform.pathSeparator}$relative',
    );
    final bytes = utf8.encode(contents);
    await file.writeAsBytes(bytes, flush: true);
    return <String, Object?>{
      'path': relative,
      'sha256': sha256.convert(bytes).toString(),
    };
  }

  final delivery = input.delivery;
  final card = input.card;

  return <String, Object?>{
    'schema': groupKilledTextCardArtifactSchema,
    'version': 1,
    'capabilityId': groupMutedNotificationCapabilityId,
    'scenario': groupTextKilledAppCardScenarioId,
    'recordedAt': input.recordedAt,
    'build': <String, Object?>{
      'profile': 'android.production_fcm',
      'provenance': 'central_prebuilt',
      'apkSha256': input.build.apkSha256,
      'childBuildCount': 0,
      'packageName': input.build.packageName,
    },
    'topology': <String, Object?>{
      'physical': <String, Object?>{
        'deviceId': input.topology.physicalDeviceId,
        'platform': 'android',
        'kind': 'physical',
      },
      'emulator': <String, Object?>{
        'deviceId': input.topology.emulatorDeviceId,
        'platform': 'android',
        'kind': 'emulator',
      },
    },
    'fixture': <String, Object?>{
      'groupName': input.fixture.groupName,
      'baselineMarker': input.fixture.baselineMarker,
      'warmupMarker': input.fixture.warmupMarker,
      'gradedMarker': input.fixture.gradedMarker,
    },
    'killedDelivery': <String, Object?>{
      'recipientProcessState': delivery.recipientProcessState,
      'warmupFcmMessageIdSha256': _sha256Text(delivery.warmupFcmMessageId),
      'gradedFcmMessageIdSha256': _sha256Text(delivery.gradedFcmMessageId),
      'backgroundFlowLog': await evidence(
        'background_flow.log',
        delivery.backgroundFlowLog,
      ),
    },
    'card': <String, Object?>{
      'preKillCardCount': card.preKillCardCount,
      'preKillNotificationDump': await evidence(
        'pre_kill_notification_dump.txt',
        card.preKillNotificationDump,
      ),
      'gradedCardCount': card.gradedCardCount,
      'gradedNotificationDump': await evidence(
        'graded_notification_dump.txt',
        card.gradedNotificationDump,
      ),
    },
    'automation': <String, Object?>{
      'manualTaps': 0,
      'notificationCardTaps': 0,
      'commandJournal': await evidence(
        'command_journal.json',
        input.commandJournal,
      ),
    },
  };
}

/// Builds and writes `<scenario>.json` into [proofDirectory].
Future<File> writeGroupKilledTextCardArtifact({
  required Directory proofDirectory,
  required GroupKilledTextCardCaptureInput input,
}) async {
  final artifact = await buildGroupKilledTextCardArtifact(
    proofDirectory: proofDirectory,
    input: input,
  );
  final file = File(
    '${proofDirectory.path}${Platform.pathSeparator}'
    '$groupTextKilledAppCardScenarioId.json',
  );
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(artifact),
    flush: true,
  );
  return file;
}

/// Validates a Plan-384 killed-app group-text card proof.
///
/// Every summary counter is re-derived from a content-addressed raw capture
/// stored next to [artifactFile]: a summary claiming "the graded push carded"
/// while the raw dump only holds the warm-up's card is rejected.
Future<GroupMutedNotificationArtifactValidation>
validateGroupKilledTextCardAndroidArtifact({
  required File artifactFile,
  String expectedPhysicalDeviceId = plan379PhysicalAndroidDeviceId,
  String expectedEmulatorDeviceId = plan379AndroidEmulatorDeviceId,
  String? expectedApkSha256,
  String? expectedPackageName,
}) async {
  final failures = <String>[];
  if (!_isRegularFile(artifactFile)) {
    return GroupMutedNotificationArtifactValidation(<String>[
      'proof artifact is not a regular file: ${artifactFile.path}',
    ]);
  }

  final artifact = _decodeObject(
    await artifactFile.readAsString(),
    r'$',
    failures,
  );
  if (artifact == null) {
    return GroupMutedNotificationArtifactValidation(failures);
  }

  if (artifact['scenario'] != groupTextKilledAppCardScenarioId) {
    failures.add(r'$.scenario is not the Plan 384 killed-app card scenario');
    return GroupMutedNotificationArtifactValidation(failures);
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
      'killedDelivery',
      'card',
      'automation',
    },
    r'$',
    failures,
  );
  _expectValue(
    artifact,
    'schema',
    groupKilledTextCardArtifactSchema,
    r'$',
    failures,
  );
  _expectValue(artifact, 'version', 1, r'$', failures);
  _expectValue(
    artifact,
    'capabilityId',
    groupMutedNotificationCapabilityId,
    r'$',
    failures,
  );
  _expectUtcTimestamp(artifact['recordedAt'], r'$.recordedAt', failures);

  final packageName = _validateBuild(
    artifact['build'],
    expectedApkSha256: expectedApkSha256,
    expectedPackageName: expectedPackageName,
    failures: failures,
  );
  _validateTopology(
    artifact['topology'],
    expectedPhysicalDeviceId: expectedPhysicalDeviceId,
    expectedEmulatorDeviceId: expectedEmulatorDeviceId,
    failures: failures,
  );

  final fixture = _object(artifact['fixture'], r'$.fixture', failures);
  var groupName = '';
  var baselineMarker = '';
  var warmupMarker = '';
  var gradedMarker = '';
  if (fixture != null) {
    _expectExactKeys(
      fixture,
      const <String>{
        'groupName',
        'baselineMarker',
        'warmupMarker',
        'gradedMarker',
      },
      r'$.fixture',
      failures,
    );
    groupName =
        _requiredString(fixture, 'groupName', r'$.fixture', failures) ?? '';
    baselineMarker =
        _requiredString(fixture, 'baselineMarker', r'$.fixture', failures) ??
        '';
    warmupMarker =
        _requiredString(fixture, 'warmupMarker', r'$.fixture', failures) ?? '';
    gradedMarker =
        _requiredString(fixture, 'gradedMarker', r'$.fixture', failures) ?? '';
    final markers = <String>[
      baselineMarker,
      warmupMarker,
      gradedMarker,
    ].where((marker) => marker.isNotEmpty).toList(growable: false);
    if (markers.toSet().length != markers.length) {
      failures.add(
        r'$.fixture markers must be pairwise distinct — a shared marker makes '
        'the graded card indistinguishable from the baseline or warm-up card',
      );
    }
  }

  await _validateKilledDelivery(
    artifact['killedDelivery'],
    artifactFile: artifactFile,
    failures: failures,
  );
  await _validateKilledCardEvidence(
    artifact['card'],
    artifactFile: artifactFile,
    packageName: packageName,
    groupName: groupName,
    baselineMarker: baselineMarker,
    gradedMarker: gradedMarker,
    failures: failures,
  );
  await _validateKilledAutomation(
    artifact['automation'],
    artifactFile: artifactFile,
    failures: failures,
  );

  return GroupMutedNotificationArtifactValidation(failures);
}

Future<void> _validateKilledDelivery(
  Object? value, {
  required File artifactFile,
  required List<String> failures,
}) async {
  const path = r'$.killedDelivery';
  final delivery = _object(value, path, failures);
  if (delivery == null) return;
  _expectExactKeys(
    delivery,
    const <String>{
      'recipientProcessState',
      'warmupFcmMessageIdSha256',
      'gradedFcmMessageIdSha256',
      'backgroundFlowLog',
    },
    path,
    failures,
  );
  if (delivery['recipientProcessState'] != 'terminated') {
    failures.add(
      '$path.recipientProcessState must be terminated — the whole point of '
      'this lane is the killed-process wake',
    );
  }
  final warmupDigest = delivery['warmupFcmMessageIdSha256'];
  final gradedDigest = delivery['gradedFcmMessageIdSha256'];
  for (final entry in <(String, Object?)>[
    ('warmupFcmMessageIdSha256', warmupDigest),
    ('gradedFcmMessageIdSha256', gradedDigest),
  ]) {
    if (!_isSha256(entry.$2)) {
      failures.add('$path.${entry.$1} must be a SHA-256 digest');
    }
  }
  if (warmupDigest == gradedDigest) {
    failures.add('$path warm-up and graded push digests must differ');
  }

  final log = await _readEvidence(
    delivery['backgroundFlowLog'],
    artifactFile: artifactFile,
    path: '$path.backgroundFlowLog',
    failures: failures,
  );
  if (log == null) return;

  final receivedDigests = _flowEventMessageDigests(
    log,
    'PUSH_BACKGROUND_MESSAGE_RECEIVED',
  );
  if (receivedDigests.length < 2) {
    failures.add(
      '$path.backgroundFlowLog records ${receivedDigests.length} post-kill '
      'wakes; the lane must land a warm-up wake BEFORE the graded push so the '
      'graded push does not absorb the cold-start storage deferral',
    );
  }
  if (warmupDigest is String && !receivedDigests.contains(warmupDigest)) {
    failures.add(
      '$path.backgroundFlowLog lacks a PUSH_BACKGROUND_MESSAGE_RECEIVED event '
      'for the warm-up push, so the cold-start cost is not proven paid',
    );
  }
  if (gradedDigest is String && !receivedDigests.contains(gradedDigest)) {
    failures.add(
      '$path.backgroundFlowLog lacks a PUSH_BACKGROUND_MESSAGE_RECEIVED event '
      'for the graded push, so the background isolate is not proven to have '
      'run for it',
    );
  }
  if (receivedDigests.isNotEmpty && gradedDigest == receivedDigests.first) {
    failures.add(
      '$path the graded push is the FIRST post-kill wake, so its disposition '
      'is the cold-start storage deferral rather than the killed-path card '
      'this lane grades',
    );
  }

  // CONTAINS, never `single`/`last`/an exact count: post-fix the warm-up push
  // presents a card too, so any count or positional rule over SHOWN would be
  // asserting an accident of ordering rather than the graded push's card.
  final shownDigests = _flowEventMessageDigests(
    log,
    'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
  );
  if (gradedDigest is String && !shownDigests.contains(gradedDigest)) {
    failures.add(
      '$path.backgroundFlowLog lacks a PUSH_BACKGROUND_NOTIFICATION_SHOWN '
      'event bound to the graded push, so the observed card is not '
      'attributable to the push under observation',
    );
  }

  // Window-scoped, not id-bound: PUSH_BACKGROUND_NOTIFICATION_ERROR details
  // are `{'error': …}` only. The accumulated window holds exactly the warm-up
  // and the graded wake, and post-fix neither may fail closed. Storage
  // deferral is a different event, so the warm-up's own cold-start exit does
  // not trip this.
  final errorLines = countFlowEventLines(
    log,
    'PUSH_BACKGROUND_NOTIFICATION_ERROR',
  );
  if (errorLines > 0) {
    failures.add(
      '$path.backgroundFlowLog carries $errorLines '
      'PUSH_BACKGROUND_NOTIFICATION_ERROR lines in the post-kill window; a '
      'killed-path group text must not fail closed',
    );
  }
}

Future<void> _validateKilledCardEvidence(
  Object? value, {
  required File artifactFile,
  required String packageName,
  required String groupName,
  required String baselineMarker,
  required String gradedMarker,
  required List<String> failures,
}) async {
  const path = r'$.card';
  final card = _object(value, path, failures);
  if (card == null) return;
  _expectExactKeys(
    card,
    const <String>{
      'preKillCardCount',
      'preKillNotificationDump',
      'gradedCardCount',
      'gradedNotificationDump',
    },
    path,
    failures,
  );
  _expectValue(card, 'preKillCardCount', 1, path, failures);
  _expectAtLeast(card, 'gradedCardCount', 1, path, failures);

  final preKillDump = await _readEvidence(
    card['preKillNotificationDump'],
    artifactFile: artifactFile,
    path: '$path.preKillNotificationDump',
    failures: failures,
  );
  if (preKillDump != null && packageName.isNotEmpty && groupName.isNotEmpty) {
    final baselineCards = extractActiveContentNotificationCards(
      preKillDump,
      packageName: packageName,
    ).where((entry) => entry.title == groupName).toList(growable: false);
    if (baselineCards.length != 1 ||
        !baselineCards.single.body.contains(baselineMarker)) {
      failures.add(
        '$path.preKillNotificationDump must show exactly one card for '
        '$groupName carrying the pre-kill baseline marker — without that '
        'alive-lane control, a dead notification install is '
        'indistinguishable from the killed-path regression',
      );
    }
  }

  final gradedDump = await _readEvidence(
    card['gradedNotificationDump'],
    artifactFile: artifactFile,
    path: '$path.gradedNotificationDump',
    failures: failures,
  );
  if (gradedDump != null && packageName.isNotEmpty && groupName.isNotEmpty) {
    final graded =
        extractActiveContentNotificationCards(
          gradedDump,
          packageName: packageName,
        ).where(
          (entry) =>
              entry.title == groupName && entry.body.contains(gradedMarker),
        );
    if (graded.isEmpty) {
      failures.add(
        '$path.gradedNotificationDump shows no card for $groupName carrying '
        'the graded marker; Android replaces a conversation card in place, so '
        'a card that still reads the baseline or warm-up body means the '
        'killed-path push posted nothing',
      );
    }
  }
}

/// Automation validator for the killed-card lane.
///
/// Deliberately not [_validateAutomation]: that one hard-requires the Group
/// Info mute toggle, which this scenario never performs. What both share is
/// the invariant that matters — zero human taps and zero notification-card
/// interactions, so the card under observation was posted by the OS rather
/// than provoked by the harness.
Future<void> _validateKilledAutomation(
  Object? value, {
  required File artifactFile,
  required List<String> failures,
}) async {
  const path = r'$.automation';
  final automation = _object(value, path, failures);
  if (automation == null) return;
  _expectExactKeys(
    automation,
    const <String>{'manualTaps', 'notificationCardTaps', 'commandJournal'},
    path,
    failures,
  );
  _expectValue(automation, 'manualTaps', 0, path, failures);
  _expectValue(automation, 'notificationCardTaps', 0, path, failures);

  final text = await _readEvidence(
    automation['commandJournal'],
    artifactFile: artifactFile,
    path: '$path.commandJournal',
    failures: failures,
  );
  if (text == null) return;
  final journal = _decodeObject(text, '$path.commandJournal', failures);
  if (journal == null) return;
  _expectExactKeys(
    journal,
    const <String>{'schema', 'commands'},
    '$path.commandJournal',
    failures,
  );
  _expectValue(
    journal,
    'schema',
    groupMutedNotificationCommandJournalSchema,
    '$path.commandJournal',
    failures,
  );
  final commands = journal['commands'];
  if (commands is! List || commands.isEmpty) {
    failures.add('$path.commandJournal.commands must be non-empty');
    return;
  }
  for (var index = 0; index < commands.length; index += 1) {
    final commandPath = '$path.commandJournal.commands[$index]';
    final command = _object(commands[index], commandPath, failures);
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
      commandPath,
      failures,
    );
    _expectUtcTimestamp(
      command['recordedAt'],
      '$commandPath.recordedAt',
      failures,
    );
    final stage = '${command['stage'] ?? ''}';
    final action = '${command['action'] ?? ''}';
    final semanticTarget = '${command['semanticTarget'] ?? ''}';
    if (action == 'tap_notification' ||
        stage.contains('notification_shade') ||
        semanticTarget.contains('notification card')) {
      failures.add('$commandPath records a forbidden notification-card action');
    }
  }
}

// ---------------------------------------------------------------------------
// Group Info mute-row UI targeting.
//
// Neither affordance the muted capture must drive exposes a label: the group
// header's info control is a bare `IconButton` with no tooltip/Semantics, and
// `Switch.adaptive` carries only a `ValueKey`, which never reaches the
// uiautomator tree. Both are therefore targeted geometrically.
//
// These are pure functions over a uiautomator XML dump precisely so the
// riskiest part of the device lane has host coverage: a bounds heuristic that
// silently drifts is otherwise only discoverable during a device run.
// ---------------------------------------------------------------------------

/// `app_en.arb: group_mute_notifications`.
const String groupMuteRowLabel = 'Mute Notifications';

/// `app_en.arb: group_mute_on_desc` — rendered only while the group IS muted.
const String groupMuteEnabledDescription =
    'New messages still arrive, but this group stays quiet.';

/// `app_en.arb: group_mute_off_desc` — rendered only while the group is NOT
/// muted.
const String groupMuteDisabledDescription =
    'Get notified when new messages arrive in this group.';

final class GroupMutedUiNode {
  const GroupMutedUiNode({
    required this.text,
    required this.description,
    required this.className,
    required this.checkable,
    required this.checked,
    required this.clickable,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final String description;
  final String className;
  final bool checkable;
  final bool checked;
  final bool clickable;
  final int left;
  final int top;
  final int right;
  final int bottom;

  int get centerX => (left + right) ~/ 2;
  int get centerY => (top + bottom) ~/ 2;

  bool matches(String value) => text == value || description == value;
}

List<GroupMutedUiNode> parseGroupMutedUiNodes(String xml) {
  final nodes = <GroupMutedUiNode>[];
  for (final match in RegExp(r'<node\b[^>]*>').allMatches(xml)) {
    final raw = match.group(0)!;
    final bounds = RegExp(
      r'bounds="\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]"',
    ).firstMatch(raw);
    if (bounds == null) continue;
    nodes.add(
      GroupMutedUiNode(
        text: _xmlAttribute(raw, 'text'),
        description: _xmlAttribute(raw, 'content-desc'),
        className: _xmlAttribute(raw, 'class'),
        checkable: _xmlAttribute(raw, 'checkable') == 'true',
        checked: _xmlAttribute(raw, 'checked') == 'true',
        clickable: _xmlAttribute(raw, 'clickable') == 'true',
        left: int.parse(bounds.group(1)!),
        top: int.parse(bounds.group(2)!),
        right: int.parse(bounds.group(3)!),
        bottom: int.parse(bounds.group(4)!),
      ),
    );
  }
  return nodes;
}

/// Semantics label of the Group Info app bar (an explicit `Semantics`, so it
/// survives in the accessibility tree).
const String groupInfoSurfaceLabel = 'Group Info';

/// True when the dump shows the Group Info screen.
///
/// Keyed on the app-bar label rather than the mute row: the mute row's
/// "Mute Notifications" `Text` is NOT exposed to the accessibility tree at all
/// (captured 2026-08-17 on a Pixel 6 — every `text=` attribute on this screen
/// is empty and the switch carries `NAF="true"`), so a row-keyed check can
/// never fire on a real device.
bool isGroupInfoSurface(String xml) => parseGroupMutedUiNodes(
  xml,
).any((node) => node.matches(groupInfoSurfaceLabel));

/// Centre of the Group Info mute switch.
///
/// The mute preference is the only `Switch` on this screen, and its label is
/// unreachable, so the switch is located as the screen's unique checkable
/// node. Ambiguity fails closed (returns null) rather than guessing, so a
/// second switch added later surfaces as a capture failure instead of a
/// silent mis-tap.
///
/// When the label IS exposed (a future accessibility fix, or another locale
/// that renders it), the row band is used to disambiguate instead.
(int, int)? findGroupMuteSwitchCenter(String xml, {int rowSlackPixels = 24}) {
  final nodes = parseGroupMutedUiNodes(xml);
  final switches = nodes
      .where(
        (node) =>
            node.checkable || node.className.toLowerCase().contains('switch'),
      )
      .toList(growable: false);
  if (switches.isEmpty) return null;

  GroupMutedUiNode? label;
  for (final node in nodes) {
    if (node.matches(groupMuteRowLabel)) {
      label = node;
      break;
    }
  }
  if (label != null) {
    GroupMutedUiNode? best;
    for (final node in switches) {
      if (node.centerY < label.top - rowSlackPixels) continue;
      if (node.centerY > label.bottom + rowSlackPixels) continue;
      if (best == null || node.centerX > best.centerX) best = node;
    }
    return best == null ? null : (best.centerX, best.centerY);
  }

  if (switches.length != 1) return null;
  return (switches.single.centerX, switches.single.centerY);
}

/// The mute switch's own checked state, or null when it is not on screen.
///
/// This replaces reading the row's subtitle text, which is not exposed. The
/// authoritative read remains the SQLCipher `groupIsMuted` observation; this
/// is only the UI-tier confirmation that the tap landed.
bool? groupMuteSwitchChecked(String xml) {
  final center = findGroupMuteSwitchCenter(xml);
  if (center == null) return null;
  for (final node in parseGroupMutedUiNodes(xml)) {
    final isSwitch =
        node.checkable || node.className.toLowerCase().contains('switch');
    if (!isSwitch) continue;
    if (node.centerX == center.$1 && node.centerY == center.$2) {
      return node.checked;
    }
  }
  return null;
}

/// Centre of the group header's unlabeled info control.
///
/// Back sits at the header's left edge and info at its right, both rendered as
/// label-free buttons, so the topmost button row is scanned and its rightmost
/// member returned.
(int, int)? findGroupInfoEntryCenter(String xml, {int headerBandPixels = 80}) {
  final candidates = parseGroupMutedUiNodes(xml)
      .where(
        (node) =>
            node.clickable &&
            node.text.isEmpty &&
            node.description.isEmpty &&
            node.className.toLowerCase().contains('button'),
      )
      .toList(growable: false);
  if (candidates.isEmpty) return null;

  var topmost = candidates.first.centerY;
  for (final node in candidates) {
    if (node.centerY < topmost) topmost = node.centerY;
  }
  GroupMutedUiNode? best;
  for (final node in candidates) {
    if (node.centerY > topmost + headerBandPixels) continue;
    if (best == null || node.centerX > best.centerX) best = node;
  }
  return best == null ? null : (best.centerX, best.centerY);
}

String _xmlAttribute(String raw, String name) {
  final match = RegExp('$name="([^"]*)"').firstMatch(raw);
  return match == null ? '' : match.group(1)!;
}

// ---------------------------------------------------------------------------
// Canonical happy-shape fixtures.
//
// These are the ONLY hand-authored inputs in the lane. Host negatives and the
// `scripts/test/group_muted_notification_device_contract_test.sh` fixtures are
// both single-field mutations of these, routed through the same
// [buildGroupMutedNotificationArtifact] the device capture stages call, so a
// validator cannot pass by recognizing hand-written negatives.
//
// The device capture supplies REAL values for every one of these fields; no
// default here is ever reachable from a live capture.
// ---------------------------------------------------------------------------

const String _fixtureApkSha256 =
    '3f2a1b9c8d7e6f504132a5b6c7d8e9f00112233445566778899aabbccddeeff0';
const String _fixturePackageName = 'com.mknoon.app';
const String _fixtureMutedGroupName = 'Plan379M-A1b2c3';
const String _fixtureControlGroupName = 'Plan379C-D4e5f6';
const String _fixtureActorName = 'Alice';
const String _fixtureRecordedAt = '2026-08-17T19:30:00.000Z';
const String _fixtureUnderTestMarker = 'Plan379MutedMarker';
final String _fixtureMutedGroupIdSha256 = _sha256Text('plan379-muted-group-id');
final String _fixtureControlGroupIdSha256 = _sha256Text(
  'plan379-control-group-id',
);
final String _fixtureUnderTestMessageIdSha256 = _sha256Text(
  'plan379-muted-message-id',
);
const String _fixtureControlMarker = 'Plan379ControlMarker';

/// One `dumpsys notification` active-section fixture.
///
/// Shaped to satisfy `extractActiveContentNotificationCards`: pkg-tagged
/// `NotificationRecord(` blocks before the `Ranking Config:` boundary, with
/// non-GROUP_SUMMARY flags so every record counts as content.
String mutedNotificationDumpFixture({
  required String packageName,
  required String? controlGroupName,
  required String? controlMarker,
  String? leakedMutedGroupName,
  String? leakedMarker,
}) {
  final buffer = StringBuffer('Notification Manager Service dump:\n')
    ..writeln('  Active notifications:');
  var id = 4100;
  void record(String title, String body) {
    id += 1;
    buffer
      ..writeln(
        '    NotificationRecord(0x0|$packageName|$id|null|10234: '
        'pkg=$packageName user=UserHandle{0} id=$id tag=null',
      )
      ..writeln('      channel=group_messages')
      ..writeln('      flags=0x18')
      ..writeln('      android.title=String ($title)')
      ..writeln('      android.text=String ($body)');
  }

  if (controlGroupName != null) {
    record(controlGroupName, '$_fixtureActorName: ${controlMarker ?? ''}');
  }
  if (leakedMutedGroupName != null) {
    record(leakedMutedGroupName, '$_fixtureActorName: ${leakedMarker ?? ''}');
  }
  buffer.writeln('Ranking Config:');
  return buffer.toString();
}

/// A dump holding exactly one card for [groupName].
String singleCardNotificationDumpFixture({
  required String packageName,
  required String groupName,
  required String marker,
}) => mutedNotificationDumpFixture(
  packageName: packageName,
  controlGroupName: groupName,
  controlMarker: marker,
);

/// The fixture lane's cold-start absorber — see [backgroundFlowLogFixture].
const String plan379WarmupFcmMessageIdFixture = 'plan379-fcm-warmup-push';

/// Raw client flow-log slice for the FCM/background lane.
///
/// Emits the warm-up wake FIRST, terminating in the cold-start
/// `PUSH_BACKGROUND_STORAGE_DEFERRED` the real device produces, so the shape
/// the host tier grades is the shape the capture records. Pass a null
/// [warmupFcmMessageId] to build the pre-warm-up (rejected) shape.
String backgroundFlowLogFixture({
  required String mutedFcmMessageId,
  required String? controlFcmMessageId,
  required String suppressionReason,
  required String suppressedFcmMessageId,
  String? warmupFcmMessageId = plan379WarmupFcmMessageIdFixture,
  String? shownFcmMessageId,
  String? trailingWakeFcmMessageId,
  bool includeShownEvent = true,
}) {
  final shownId = shownFcmMessageId ?? controlFcmMessageId;
  final lines = <String>[
    if (warmupFcmMessageId != null) ...<String>[
      '{"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED",'
          '"messageId":"$warmupFcmMessageId","type":"group_message"}',
      '{"event":"PUSH_BACKGROUND_STORAGE_DEFERRED","kind":"group_message",'
          '"phase":"display_eligibility","outcome":"storage_deferred"}',
    ],
    '{"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED",'
        '"messageId":"$mutedFcmMessageId","type":"group_reaction"}',
    if (controlFcmMessageId != null)
      '{"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED",'
          '"messageId":"$controlFcmMessageId","type":"group_reaction"}',
    if (trailingWakeFcmMessageId != null)
      '{"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED",'
          '"messageId":"$trailingWakeFcmMessageId","type":"group_message"}',
    '{"event":"PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED",'
        '"messageId":"$suppressedFcmMessageId","reason":"$suppressionReason"}',
    if (includeShownEvent && shownId != null)
      '{"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN",'
          '"messageId":"$shownId",'
          '"payload":"group:plan379-fixture|message:plan379-fixture"}',
  ];
  return '${lines.join('\n')}\n';
}

/// Raw probe observation slice bound to the summary counters.
String sqlcipherObservationFixture({
  required bool groupIsMuted,
  required int unreadCount,
  required bool badgeAvailable,
  required bool badgeIncludesObservedGroup,
}) => jsonEncode(<String, Object?>{
  'schema': 'mknoon.plan257.sqlcipher-observation.v1',
  'groupIsMuted': groupIsMuted,
  'unreadCount': unreadCount,
  'canonicalBadgeState': <String, Object?>{
    'available': badgeAvailable,
    'includesObservedGroup': badgeIncludesObservedGroup,
  },
});

String _commandJournalFixture({required bool includeControlVisit}) =>
    jsonEncode(<String, Object?>{
      'schema': groupMutedNotificationCommandJournalSchema,
      'commands': <Map<String, Object?>>[
        <String, Object?>{
          'stage': 'mute_toggle',
          'target': plan379PhysicalAndroidDeviceId,
          'action': 'tap',
          'semanticTarget': 'Mute Notifications',
          'recordedAt': '2026-08-17T19:20:00.000Z',
        },
        if (includeControlVisit)
          <String, Object?>{
            'stage': 'control_visit',
            'target': plan379PhysicalAndroidDeviceId,
            'action': 'tap',
            'semanticTarget': 'Open group $_fixtureControlGroupName',
            'recordedAt': '2026-08-17T19:22:00.000Z',
          },
      ],
    });

/// The accepted live-path (muted message) artifact input.
GroupMutedNotificationCaptureInput happyMutedMessageCaptureInput() =>
    GroupMutedNotificationCaptureInput(
      scenario: groupMutedMessageSuppressionScenarioId,
      recordedAt: _fixtureRecordedAt,
      build: const GroupMutedNotificationBuildInput(
        apkSha256: _fixtureApkSha256,
        packageName: _fixturePackageName,
      ),
      topology: const GroupMutedNotificationTopologyInput(
        physicalDeviceId: plan379PhysicalAndroidDeviceId,
        emulatorDeviceId: plan379AndroidEmulatorDeviceId,
      ),
      fixture: GroupMutedNotificationFixtureInput(
        mutedGroupName: _fixtureMutedGroupName,
        controlGroupName: _fixtureControlGroupName,
        mutedGroupIdSha256: _fixtureMutedGroupIdSha256,
        controlGroupIdSha256: _fixtureControlGroupIdSha256,
        actorName: _fixtureActorName,
      ),
      mutedProjection: GroupMutedProjectionInput(
        groupIsMuted: true,
        underTestMarker: _fixtureUnderTestMarker,
        underTestMessageIdSha256: _fixtureUnderTestMessageIdSha256,
        underTestReadAtNull: true,
        mutedCardCount: 0,
        unreadBaseline: 1,
        unreadAfter: 2,
        persistedRowObserved: true,
        reactionRowsObserved: 0,
        badgeAvailable: true,
        badgeIncludesMutedGroup: false,
        badgeIncludesControlGroup: true,
        badgeGroupIdentityCount: 1,
        notificationDump: mutedNotificationDumpFixture(
          packageName: _fixturePackageName,
          controlGroupName: _fixtureControlGroupName,
          controlMarker: _fixtureControlMarker,
        ),
        sqlcipherObservation: sqlcipherObservationFixture(
          groupIsMuted: true,
          unreadCount: 2,
          badgeAvailable: true,
          badgeIncludesObservedGroup: false,
        ),
      ),
      control: GroupMutedControlInput(
        controlMarker: _fixtureControlMarker,
        preMuteCardGroup: 'muted',
        preMuteCardCount: 1,
        preMuteNotificationDump: singleCardNotificationDumpFixture(
          packageName: _fixturePackageName,
          groupName: _fixtureMutedGroupName,
          marker: 'Plan379PreMuteMarker',
        ),
        postMuteCardCount: 1,
        postMuteNotificationDump: singleCardNotificationDumpFixture(
          packageName: _fixturePackageName,
          groupName: _fixtureControlGroupName,
          marker: _fixtureControlMarker,
        ),
      ),
      commandJournal: _commandJournalFixture(includeControlVisit: true),
    );

/// The canonical REJECTED input: unread did not grow across the muted send.
///
/// Shared by the host suite and `group_muted_notification_device_contract_test.sh`
/// so the shell and the host tier cannot disagree about what a rejected muted
/// artifact looks like. Both the summary and its raw probe observation move
/// together — mutating only the summary is caught by the raw-vs-summary
/// cross-check instead, which would leave the unread rule itself untested.
GroupMutedNotificationCaptureInput unreadUnchangedMutedMessageCaptureInput() {
  final happy = happyMutedMessageCaptureInput();
  final baseline = happy.mutedProjection.unreadBaseline;
  return happy.copyWith(
    mutedProjection: happy.mutedProjection.copyWith(
      unreadAfter: baseline,
      sqlcipherObservation: sqlcipherObservationFixture(
        groupIsMuted: true,
        unreadCount: baseline,
        badgeAvailable: true,
        badgeIncludesObservedGroup: false,
      ),
    ),
  );
}

/// The accepted FCM/background-path (muted reaction) artifact input.
GroupMutedNotificationCaptureInput happyMutedReactionCaptureInput() {
  final live = happyMutedMessageCaptureInput();
  return live.copyWith(
    scenario: groupMutedReactionBackgroundScenarioId,
    // The FCM lane reacts to a message the RECIPIENT authored, so its unread
    // does not grow; what must be persisted is the reaction row. Unread must
    // still not regress, which is what the equal baseline/after asserts.
    mutedProjection: live.mutedProjection.copyWith(
      unreadBaseline: 1,
      unreadAfter: 1,
      reactionRowsObserved: 1,
      sqlcipherObservation: sqlcipherObservationFixture(
        groupIsMuted: true,
        unreadCount: 1,
        badgeAvailable: true,
        badgeIncludesObservedGroup: false,
      ),
    ),
    control: live.control.copyWith(
      preMuteCardGroup: 'control',
      preMuteNotificationDump: singleCardNotificationDumpFixture(
        packageName: _fixturePackageName,
        groupName: _fixtureControlGroupName,
        marker: 'Plan379BaselineMarker',
      ),
    ),
    commandJournal: _commandJournalFixture(includeControlVisit: false),
    backgroundDelivery: GroupMutedBackgroundDeliveryInput(
      recipientProcessState: 'backgrounded',
      mutedFcmMessageId: 'plan379-fcm-muted-push',
      controlFcmMessageId: 'plan379-fcm-control-push',
      suppressionReason: 'group_reaction_local_state_ineligible',
      backgroundFlowLog: backgroundFlowLogFixture(
        mutedFcmMessageId: 'plan379-fcm-muted-push',
        controlFcmMessageId: 'plan379-fcm-control-push',
        suppressionReason: 'group_reaction_local_state_ineligible',
        suppressedFcmMessageId: 'plan379-fcm-muted-push',
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Plan 384 killed-app card fixtures.
// ---------------------------------------------------------------------------

const String _fixtureKilledGroupName = 'TC257Group1787055431430779';
const String _fixtureKilledBaselineMarker = 'Plan384Base9f8e7d6c5b';
const String _fixtureKilledWarmupMarker = 'Plan384Warm4a3b2c1d0e';
const String _fixtureKilledGradedMarker = 'Plan384Grad7e6d5c4b3a';
const String _fixtureKilledWarmupFcmMessageId = 'plan384-fcm-warmup-push';
const String _fixtureKilledGradedFcmMessageId = 'plan384-fcm-graded-push';

/// Raw recipient flow-log slice for the killed-app card lane.
///
/// The received/shown id lists are passed in whole so each host negative moves
/// exactly one rule: a fixture that had to imply ordering from booleans would
/// trip two rules at once and stop being a unique pin.
String killedTextCardFlowLogFixture({
  required List<String> receivedFcmMessageIds,
  required List<String> shownFcmMessageIds,
  bool includeWindowError = false,
}) {
  final lines = <String>[
    for (final id in receivedFcmMessageIds) ...<String>[
      '{"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED",'
          '"messageId":"$id","type":"group_message"}',
      if (id == receivedFcmMessageIds.first)
        '{"event":"PUSH_BACKGROUND_STORAGE_DEFERRED","kind":"group_message",'
            '"phase":"display_eligibility","outcome":"storage_deferred"}',
    ],
    '{"event":"PUSH_ANDROID_DATA_DECRYPT_OK","details":{"kind":"group"}}',
    for (final id in shownFcmMessageIds)
      '{"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN",'
          '"messageId":"$id","silent":true}',
    if (includeWindowError)
      '{"event":"PUSH_BACKGROUND_NOTIFICATION_ERROR","details":{"error":'
          '"OrdinaryMessageNotificationIntegrityException"}}',
  ];
  return '${lines.join('\n')}\n';
}

String _killedCommandJournalFixture() => jsonEncode(<String, Object?>{
  'schema': groupMutedNotificationCommandJournalSchema,
  'commands': <Map<String, Object?>>[
    <String, Object?>{
      'stage': 'killed_app_group_text',
      'target': plan379AndroidEmulatorDeviceId,
      'action': 'tap',
      'semanticTarget': 'Open group $_fixtureKilledGroupName',
      'recordedAt': '2026-08-19T09:10:00.000Z',
    },
    <String, Object?>{
      'stage': 'killed_app_group_text',
      'target': plan379PhysicalAndroidDeviceId,
      'action': 'terminate',
      'semanticTarget': 'recipient process',
      'recordedAt': '2026-08-19T09:11:00.000Z',
    },
  ],
});

/// The accepted killed-app card artifact input.
GroupKilledTextCardCaptureInput happyKilledTextCardCaptureInput() =>
    GroupKilledTextCardCaptureInput(
      recordedAt: '2026-08-19T09:12:00.000Z',
      build: const GroupMutedNotificationBuildInput(
        apkSha256: _fixtureApkSha256,
        packageName: _fixturePackageName,
      ),
      topology: const GroupMutedNotificationTopologyInput(
        physicalDeviceId: plan379PhysicalAndroidDeviceId,
        emulatorDeviceId: plan379AndroidEmulatorDeviceId,
      ),
      fixture: const GroupKilledTextCardFixtureInput(
        groupName: _fixtureKilledGroupName,
        baselineMarker: _fixtureKilledBaselineMarker,
        warmupMarker: _fixtureKilledWarmupMarker,
        gradedMarker: _fixtureKilledGradedMarker,
      ),
      delivery: GroupKilledTextCardDeliveryInput(
        recipientProcessState: 'terminated',
        warmupFcmMessageId: _fixtureKilledWarmupFcmMessageId,
        gradedFcmMessageId: _fixtureKilledGradedFcmMessageId,
        backgroundFlowLog: killedTextCardFlowLogFixture(
          receivedFcmMessageIds: const <String>[
            _fixtureKilledWarmupFcmMessageId,
            _fixtureKilledGradedFcmMessageId,
          ],
          shownFcmMessageIds: const <String>[
            _fixtureKilledWarmupFcmMessageId,
            _fixtureKilledGradedFcmMessageId,
          ],
        ),
      ),
      card: GroupKilledTextCardCardInput(
        preKillCardCount: 1,
        preKillNotificationDump: singleCardNotificationDumpFixture(
          packageName: _fixturePackageName,
          groupName: _fixtureKilledGroupName,
          marker: _fixtureKilledBaselineMarker,
        ),
        gradedCardCount: 1,
        gradedNotificationDump: singleCardNotificationDumpFixture(
          packageName: _fixturePackageName,
          groupName: _fixtureKilledGroupName,
          marker: _fixtureKilledGradedMarker,
        ),
      ),
      commandJournal: _killedCommandJournalFixture(),
    );

/// Rejected: the flow log carries no SHOWN event for the graded push, so the
/// observed card cannot be attributed to it.
GroupKilledTextCardCaptureInput
missingShownBindingKilledTextCardCaptureInput() {
  final happy = happyKilledTextCardCaptureInput();
  return happy.copyWith(
    delivery: happy.delivery.copyWith(
      backgroundFlowLog: killedTextCardFlowLogFixture(
        receivedFcmMessageIds: const <String>[
          _fixtureKilledWarmupFcmMessageId,
          _fixtureKilledGradedFcmMessageId,
        ],
        shownFcmMessageIds: const <String>[_fixtureKilledWarmupFcmMessageId],
      ),
    ),
  );
}

/// Rejected: a `PUSH_BACKGROUND_NOTIFICATION_ERROR` line inside the post-kill
/// window — the exact pre-fix shape, where the parity throw killed the card.
GroupKilledTextCardCaptureInput windowErrorKilledTextCardCaptureInput() {
  final happy = happyKilledTextCardCaptureInput();
  return happy.copyWith(
    delivery: happy.delivery.copyWith(
      backgroundFlowLog: killedTextCardFlowLogFixture(
        receivedFcmMessageIds: const <String>[
          _fixtureKilledWarmupFcmMessageId,
          _fixtureKilledGradedFcmMessageId,
        ],
        shownFcmMessageIds: const <String>[
          _fixtureKilledWarmupFcmMessageId,
          _fixtureKilledGradedFcmMessageId,
        ],
        includeWindowError: true,
      ),
    ),
  );
}

/// Rejected: the graded push is the FIRST post-kill wake, so its disposition
/// is the cold-start storage deferral rather than the boundary under test.
GroupKilledTextCardCaptureInput gradedPushIsFirstWakeCaptureInput() {
  final happy = happyKilledTextCardCaptureInput();
  return happy.copyWith(
    delivery: happy.delivery.copyWith(
      backgroundFlowLog: killedTextCardFlowLogFixture(
        receivedFcmMessageIds: const <String>[
          _fixtureKilledGradedFcmMessageId,
          _fixtureKilledWarmupFcmMessageId,
        ],
        shownFcmMessageIds: const <String>[
          _fixtureKilledGradedFcmMessageId,
          _fixtureKilledWarmupFcmMessageId,
        ],
      ),
    ),
  );
}

/// Rejected: the shade still shows the warm-up card. Android replaces a
/// conversation card in place, so "a card exists" is satisfied by the warm-up
/// alone — this is the exact false positive a bare presence check would pass.
GroupKilledTextCardCaptureInput staleCardKilledTextCardCaptureInput() {
  final happy = happyKilledTextCardCaptureInput();
  return happy.copyWith(
    card: happy.card.copyWith(
      gradedNotificationDump: singleCardNotificationDumpFixture(
        packageName: _fixturePackageName,
        groupName: _fixtureKilledGroupName,
        marker: _fixtureKilledWarmupMarker,
      ),
    ),
  );
}
