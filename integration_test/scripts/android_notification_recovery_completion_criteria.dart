import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String androidNotificationRecoveryCompletionCapabilityId =
    'notifications.android_recovery_completion';
const String androidNotificationRecoveryCompletionValidator =
    'integration_test/android_notification_recovery_completion_proof_test.dart';
const String androidNotificationRecoveryCompletionScenarioId =
    'android_fixed_wake_direct_reaction_recovery';
const String androidNotificationRecoveryCompletionRawSchema =
    'mknoon.plan393.android-fixed-wake-recovery-raw.v1';
const String androidNotificationRecoveryCompletionCampaignSchema =
    'mknoon.plan393.android-fixed-wake-recovery-final.v1';
const String androidNotificationRecoveryCompletionBuildProfile =
    'android.production_fcm.fixed_wake';
const String androidNotificationRecoveryCompletionBuildCapability =
    'build.android.production_fcm.fixed_wake';
const String androidNotificationRecoveryCompletionArtifactEnvironment =
    'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM_FIXED_WAKE';

const List<String> androidNotificationRecoveryCompletionAssertions = <String>[
  'notifications.fixed_wake_live_route_selected',
  'notifications.direct_reaction_canonical_recovery',
  'notifications.generic_recovery_card_retired',
  'notifications.no_duplicate_or_second_tone',
  'notifications.state_and_route_restored',
  'notifications.zero_taps_zero_child_builds',
];

const List<Map<String, String>> androidNotificationRecoveryDisposition =
    <Map<String, String>>[
      <String, String>{
        'assertion': 'notifications.headless_direct_group_recovery',
        'disposition': 'retained_host_native',
        'owner': 'plan374_tc374_02_tc374_08',
      },
      <String, String>{
        'assertion': 'notifications.foreground_handoff_new_generation',
        'disposition': 'retained_host_concurrency',
        'owner': 'plan374_tc374_06_and_plan393_distinct_generations',
      },
      <String, String>{
        'assertion': 'notifications.direct_custody_recovery',
        'disposition': 'specialized',
        'owner': 'plan393_authenticated_direct_reaction',
      },
      <String, String>{
        'assertion': 'notifications.synthetic_outer_id_recovery',
        'disposition': 'retired_obsolete_unsafe',
        'owner': 'plan375_tc375_04_identity_free_wake',
      },
      <String, String>{
        'assertion': 'notifications.history_count_projection',
        'disposition': 'retained_outside_recovery_matrix',
        'owner': 'conversation_snapshot_and_projection_tests',
      },
      <String, String>{
        'assertion': 'notifications.registration_health_live_recovery',
        'disposition': 'split_existing_owners',
        'owner': 'plan375_tc375_07_and_registration_health_tests',
      },
      <String, String>{
        'assertion': 'notifications.recovery_copy_locales',
        'disposition': 'retained_native_host',
        'owner': 'android_recovery_string_resources_tests',
      },
      <String, String>{
        'assertion': 'notifications.zero_taps_zero_child_builds',
        'disposition': 'retained_narrowed_capability',
        'owner': 'plan393_tc393_12_tc393_13',
      },
    ];

Set<int> parseAndroidCanonicalRecoveryJobIds({
  required String dump,
  required String appPackage,
}) {
  final normalized = dump.replaceAll('\r', '');
  final start = RegExp(
    r'^Registered(?:\s+\d+)?\s+jobs:',
    multiLine: true,
  ).firstMatch(normalized);
  if (start == null) {
    throw const FormatException('JobScheduler has no registered-jobs section.');
  }

  var section = normalized.substring(start.end);
  final endOffsets = <String>[
    '\nPending queue:',
    '\nActive jobs:',
    '\nRecently completed jobs:',
    '\nConcurrency:',
  ].map(section.indexOf).where((index) => index >= 0).toList()..sort();
  if (endOffsets.isNotEmpty) section = section.substring(0, endOffsets.first);

  final headers = RegExp(
    r'^\s*JOB\s+#?[^\s/]+/(?<job>\d+)(?::|\s+from\s+namespace\b[^\n]*:)',
    multiLine: true,
  ).allMatches(section).toList();
  final result = <int>{};
  final service =
      '$appPackage/androidx.work.impl.background.systemjob.SystemJobService';
  for (var index = 0; index < headers.length; index += 1) {
    final block = section.substring(
      headers[index].start,
      index + 1 < headers.length ? headers[index + 1].start : section.length,
    );
    if (block.contains(service) &&
        block.contains('androidx.work.systemjobscheduler') &&
        block.contains('#HeadlessCanonicalRecoveryWorker#')) {
      final id = int.tryParse(headers[index].namedGroup('job') ?? '');
      if (id != null) result.add(id);
    }
  }
  return Set<int>.unmodifiable(result);
}

final class AndroidNotificationRecoveryCompletionValidation {
  AndroidNotificationRecoveryCompletionValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;
  bool get ok => failures.isEmpty;
  String get detail => ok ? 'accepted' : failures.join('; ');
}

AndroidNotificationRecoveryCompletionValidation
validateAndroidNotificationRecoveryCompletionArtifact({
  required File artifactFile,
  String? expectedPhysicalDeviceId,
  String? expectedEmulatorDeviceId,
  String? expectedApkSha256,
  String? expectedPackageName,
}) {
  final failures = <String>[];
  final root = _readObject(artifactFile, r'$', failures);
  if (root == null) {
    return AndroidNotificationRecoveryCompletionValidation(failures);
  }
  _exactKeys(
    root,
    const <String>{
      'status',
      'recordedAt',
      'campaignSchema',
      'scenarioIds',
      'criteria',
      'targetIds',
      'targetKinds',
      'buildProfile',
      'buildCapability',
      'preparedArtifactEnvironment',
      'preparedArtifactSha256',
      'captureRoot',
      'captureArtifactPath',
      'captureArtifactSha256',
      'childBuildCount',
      'manualTaps',
      'notificationCardTaps',
      'mainActivityLaunchesDuringKilledRecovery',
      'authenticatedRouteUnregister',
      'routeAbsentReadback',
      'stateRestored',
      'postRestoreAppCardCount',
      'schema',
      'capabilityId',
      'validatorIds',
    },
    r'$',
    failures,
  );
  _expect(root, 'schema', 'mknoon.sims.proof.v1', r'$', failures);
  _expect(
    root,
    'campaignSchema',
    androidNotificationRecoveryCompletionCampaignSchema,
    r'$',
    failures,
  );
  _expect(
    root,
    'capabilityId',
    androidNotificationRecoveryCompletionCapabilityId,
    r'$',
    failures,
  );
  _expect(
    root,
    'validatorIds',
    const <String>[androidNotificationRecoveryCompletionValidator],
    r'$',
    failures,
  );
  _expect(root, 'status', 'passed', r'$', failures);
  _expect(
    root,
    'scenarioIds',
    const <String>[androidNotificationRecoveryCompletionScenarioId],
    r'$',
    failures,
  );
  _expect(
    root,
    'criteria',
    androidNotificationRecoveryCompletionAssertions,
    r'$',
    failures,
  );
  _expect(
    root,
    'buildProfile',
    androidNotificationRecoveryCompletionBuildProfile,
    r'$',
    failures,
  );
  _expect(
    root,
    'buildCapability',
    androidNotificationRecoveryCompletionBuildCapability,
    r'$',
    failures,
  );
  _expect(
    root,
    'preparedArtifactEnvironment',
    androidNotificationRecoveryCompletionArtifactEnvironment,
    r'$',
    failures,
  );
  _utc(root['recordedAt'], r'$.recordedAt', failures);
  for (final key in const <String>[
    'childBuildCount',
    'manualTaps',
    'notificationCardTaps',
    'mainActivityLaunchesDuringKilledRecovery',
    'postRestoreAppCardCount',
  ]) {
    _expect(root, key, 0, r'$', failures);
  }
  for (final key in const <String>[
    'authenticatedRouteUnregister',
    'routeAbsentReadback',
    'stateRestored',
  ]) {
    _expect(root, key, true, r'$', failures);
  }
  if (!_digest(root['preparedArtifactSha256'])) {
    failures.add(r'$.preparedArtifactSha256 invalid');
  } else if (expectedApkSha256 != null &&
      root['preparedArtifactSha256'] != expectedApkSha256) {
    failures.add(r'$.preparedArtifactSha256 does not bind the prepared APK');
  }
  final targets = root['targetIds'];
  if (targets is! List || targets.length != 2) {
    failures.add(
      r'$.targetIds must contain physical sender and emulator receiver',
    );
  } else {
    if (expectedPhysicalDeviceId != null &&
        targets[0] != expectedPhysicalDeviceId) {
      failures.add(r'$.targetIds[0] is not the assigned physical sender');
    }
    if (expectedEmulatorDeviceId != null &&
        targets[1] != expectedEmulatorDeviceId) {
      failures.add(r'$.targetIds[1] is not the assigned emulator receiver');
    }
  }
  _expect(
    root,
    'targetKinds',
    const <String>['physical', 'emulator'],
    r'$',
    failures,
  );

  final capturePath = root['captureArtifactPath'];
  if (capturePath is! String || capturePath.trim().isEmpty) {
    failures.add(r'$.captureArtifactPath missing');
    return AndroidNotificationRecoveryCompletionValidation(failures);
  }
  final rawArtifact = File(capturePath);
  if (!_regular(rawArtifact, followLinks: false)) {
    failures.add(r'$.captureArtifactPath is not a regular file');
    return AndroidNotificationRecoveryCompletionValidation(failures);
  }
  final actualRawDigest = sha256
      .convert(rawArtifact.readAsBytesSync())
      .toString();
  if (root['captureArtifactSha256'] != actualRawDigest) {
    failures.add(r'$.captureArtifactSha256 mismatch');
  }
  final rawValidation = validateAndroidNotificationRecoveryRawArtifact(
    artifactFile: rawArtifact,
    expectedPhysicalDeviceId: expectedPhysicalDeviceId,
    expectedEmulatorDeviceId: expectedEmulatorDeviceId,
    expectedApkSha256: expectedApkSha256,
    expectedPackageName: expectedPackageName,
  );
  failures.addAll(rawValidation.failures.map((value) => 'raw: $value'));
  return AndroidNotificationRecoveryCompletionValidation(failures);
}

AndroidNotificationRecoveryCompletionValidation
validateAndroidNotificationRecoveryRawArtifact({
  required File artifactFile,
  String? expectedPhysicalDeviceId,
  String? expectedEmulatorDeviceId,
  String? expectedApkSha256,
  String? expectedPackageName,
}) {
  final failures = <String>[];
  final root = _readObject(artifactFile, r'$', failures);
  if (root == null) {
    return AndroidNotificationRecoveryCompletionValidation(failures);
  }
  final raw = artifactFile.readAsStringSync();
  for (final forbidden in const <String>[
    'BEGIN PRIVATE KEY',
    '"fcmToken":',
    '"pushToken":',
    '"privateKey":',
    'NotificationRecoveryCompletionReceiver',
    'android_notification_recovery_completion_campaign_driver',
  ]) {
    if (raw.contains(forbidden)) failures.add('artifact contains $forbidden');
  }
  _exactKeys(
    root,
    const <String>{
      'schema',
      'version',
      'scenario',
      'status',
      'recordedAt',
      'buildProfile',
      'buildCapability',
      'preparedArtifactSha256',
      'appPackage',
      'topology',
      'relay',
      'transitionA',
      'transitionB',
      'cleanup',
      'automation',
      'assertions',
      'oldAssertionDisposition',
      'redaction',
    },
    r'$',
    failures,
  );
  _expect(
    root,
    'schema',
    androidNotificationRecoveryCompletionRawSchema,
    r'$',
    failures,
  );
  _expect(root, 'version', 1, r'$', failures);
  _expect(
    root,
    'scenario',
    androidNotificationRecoveryCompletionScenarioId,
    r'$',
    failures,
  );
  _expect(root, 'status', 'passed', r'$', failures);
  _expect(
    root,
    'buildProfile',
    androidNotificationRecoveryCompletionBuildProfile,
    r'$',
    failures,
  );
  _expect(
    root,
    'buildCapability',
    androidNotificationRecoveryCompletionBuildCapability,
    r'$',
    failures,
  );
  _expect(
    root,
    'assertions',
    androidNotificationRecoveryCompletionAssertions,
    r'$',
    failures,
  );
  _expect(
    root,
    'oldAssertionDisposition',
    androidNotificationRecoveryDisposition,
    r'$',
    failures,
  );
  _utc(root['recordedAt'], r'$.recordedAt', failures);
  if (!_digest(root['preparedArtifactSha256'])) {
    failures.add(r'$.preparedArtifactSha256 invalid');
  } else if (expectedApkSha256 != null &&
      root['preparedArtifactSha256'] != expectedApkSha256) {
    failures.add(r'$.preparedArtifactSha256 mismatch');
  }
  if (expectedPackageName != null &&
      root['appPackage'] != expectedPackageName) {
    failures.add(r'$.appPackage mismatch');
  }

  final topology = _object(root['topology'], r'$.topology', failures);
  if (topology != null) {
    _exactKeys(
      topology,
      const <String>{'sender', 'receiver'},
      r'$.topology',
      failures,
    );
    _device(
      topology['sender'],
      r'$.topology.sender',
      'physical',
      'sender',
      expectedPhysicalDeviceId,
      failures,
    );
    _device(
      topology['receiver'],
      r'$.topology.receiver',
      'emulator',
      'receiver',
      expectedEmulatorDeviceId,
      failures,
    );
  }
  final relay = _object(root['relay'], r'$.relay', failures);
  if (relay != null) {
    _exactKeys(
      relay,
      const <String>{
        'revision',
        'sha256',
        'selectedRouteCounter',
        'executionBoundary',
        'backend',
        'pushTokenState',
        'wakeOutcomeLedger',
        'provider',
      },
      r'$.relay',
      failures,
    );
    if (relay['revision'] is! String || '${relay['revision']}'.trim().isEmpty) {
      failures.add(r'$.relay.revision missing');
    }
    if (!_digest(relay['sha256'])) failures.add(r'$.relay.sha256 invalid');
    _expect(
      relay,
      'selectedRouteCounter',
      'relay_push_route_selected_total',
      r'$.relay',
      failures,
    );
    _expect(
      relay,
      'executionBoundary',
      'ephemeral_production_redis_fixture',
      r'$.relay',
      failures,
    );
    _expect(relay, 'backend', 'redis', r'$.relay', failures);
    _expect(relay, 'pushTokenState', 'encrypted', r'$.relay', failures);
    _expect(relay, 'wakeOutcomeLedger', 'redis', r'$.relay', failures);
    _expect(relay, 'provider', 'fcm', r'$.relay', failures);
  }

  final transitionA = _transition(
    root['transitionA'],
    r'$.transitionA',
    lifecycle: 'alive_backgrounded',
    requireKilledWorker: false,
    artifactDirectory: artifactFile.parent,
    failures: failures,
  );
  final transitionB = _transition(
    root['transitionB'],
    r'$.transitionB',
    lifecycle: 'killed',
    requireKilledWorker: true,
    artifactDirectory: artifactFile.parent,
    failures: failures,
  );
  if (transitionA != null && transitionB != null) {
    for (final key in const <String>[
      'targetMarkerSha256',
      'targetMessageIdSha256',
      'reactionIdSha256',
      'recoveryGeneration',
    ]) {
      if (transitionA[key] == transitionB[key]) {
        failures.add(r'$.transitionB reuses transition A ' + key);
      }
    }
  }

  final cleanup = _object(root['cleanup'], r'$.cleanup', failures);
  if (cleanup != null) {
    _exactKeys(
      cleanup,
      const <String>{
        'authenticatedRouteUnregister',
        'unregisterReceipt',
        'routeAbsentReadback',
        'absenceProbeReactionIdSha256',
        'absenceProbeRouteBefore',
        'absenceProbeRouteAfter',
        'absenceProbeRelayJournal',
        'postCampaignAppCardCount',
        'localStateRestorationOwnedByParent',
      },
      r'$.cleanup',
      failures,
    );
    for (final key in const <String>[
      'authenticatedRouteUnregister',
      'routeAbsentReadback',
      'localStateRestorationOwnedByParent',
    ]) {
      _expect(cleanup, key, true, r'$.cleanup', failures);
    }
    _expect(cleanup, 'postCampaignAppCardCount', 0, r'$.cleanup', failures);
    if (!_digest(cleanup['absenceProbeReactionIdSha256'])) {
      failures.add(r'$.cleanup absence reaction digest invalid');
    }
    final before = _route(
      cleanup['absenceProbeRouteBefore'],
      r'$.cleanup.absenceProbeRouteBefore',
      artifactFile.parent,
      failures,
    );
    final after = _route(
      cleanup['absenceProbeRouteAfter'],
      r'$.cleanup.absenceProbeRouteAfter',
      artifactFile.parent,
      failures,
    );
    if (before != null &&
        after != null &&
        (before.$1 != after.$1 || before.$2 != after.$2)) {
      failures.add(r'$.cleanup route remained selectable after unregister');
    }
    _reference(
      cleanup['unregisterReceipt'],
      artifactFile.parent,
      r'$.cleanup.unregisterReceipt',
      failures,
    );
    _reference(
      cleanup['absenceProbeRelayJournal'],
      artifactFile.parent,
      r'$.cleanup.absenceProbeRelayJournal',
      failures,
    );
  }

  final automation = _object(root['automation'], r'$.automation', failures);
  if (automation != null) {
    _exactKeys(
      automation,
      const <String>{
        'manualUserTaps',
        'notificationCardTaps',
        'childBuildCount',
        'mainActivityLaunchesDuringKilledRecovery',
        'productionIngressInjectionCount',
        'statePreparedByParent',
      },
      r'$.automation',
      failures,
    );
    for (final key in const <String>[
      'manualUserTaps',
      'notificationCardTaps',
      'childBuildCount',
      'mainActivityLaunchesDuringKilledRecovery',
      'productionIngressInjectionCount',
    ]) {
      _expect(automation, key, 0, r'$.automation', failures);
    }
    _expect(
      automation,
      'statePreparedByParent',
      true,
      r'$.automation',
      failures,
    );
  }
  final redaction = _object(root['redaction'], r'$.redaction', failures);
  if (redaction != null) {
    for (final key in const <String>[
      'providerTokensPersisted',
      'privateKeysPersisted',
      'rawPeerIdsPersisted',
      'messagePlaintextPersisted',
    ]) {
      _expect(redaction, key, false, r'$.redaction', failures);
    }
  }
  return AndroidNotificationRecoveryCompletionValidation(failures);
}

Map<String, Object?>? _transition(
  Object? value,
  String path, {
  required String lifecycle,
  required bool requireKilledWorker,
  required Directory artifactDirectory,
  required List<String> failures,
}) {
  final transition = _object(value, path, failures);
  if (transition == null) return null;
  final commonKeys = <String>{
    'lifecycle',
    'targetMarkerSha256',
    'targetMessageIdSha256',
    'reactionIdSha256',
    'recoveryGeneration',
    'routeBefore',
    'routeAfter',
    'opaqueRouteDelta',
    'richRouteDelta',
    'productionFixedWakeIngress',
    'genericCard',
    'canonicalCard',
    'genericCardRetiredAfterCanonical',
    'exactMarkerAcknowledgement',
    'duplicateCanonicalShowCount',
    'requestedToneCount',
    'richFlutterFireCallbackCount',
    'notificationSnapshots',
    'runtimeEvidence',
    'relayJournal',
  };
  if (lifecycle == 'alive_backgrounded') {
    commonKeys.add('exactChatActivation');
  }
  if (requireKilledWorker) {
    commonKeys.addAll(const <String>{
      'processAbsentBeforeSend',
      'barrierArmReceipt',
      'firstWorkerPid',
      'resumedWorkerPid',
      'runAttemptCount',
      'terminalOutcome',
      'jobSchedulerBaseline',
      'jobSchedulerAudit',
    });
  }
  _exactKeys(transition, commonKeys, path, failures);
  _expect(transition, 'lifecycle', lifecycle, path, failures);
  for (final key in const <String>[
    'targetMarkerSha256',
    'targetMessageIdSha256',
    'reactionIdSha256',
  ]) {
    if (!_digest(transition[key])) failures.add('$path.$key invalid');
  }
  final generation = transition['recoveryGeneration'];
  if (generation is! int || generation <= 0) {
    failures.add('$path.recoveryGeneration invalid');
  }
  final before = _route(
    transition['routeBefore'],
    '$path.routeBefore',
    artifactDirectory,
    failures,
  );
  final after = _route(
    transition['routeAfter'],
    '$path.routeAfter',
    artifactDirectory,
    failures,
  );
  if (before != null && after != null) {
    if (after.$1 - before.$1 != 1 || after.$2 - before.$2 != 0) {
      failures.add('$path selected route is not opaque +1/rich +0');
    }
    _expect(transition, 'opaqueRouteDelta', 1, path, failures);
    _expect(transition, 'richRouteDelta', 0, path, failures);
  }
  final ingress = _object(
    transition['productionFixedWakeIngress'],
    '$path.productionFixedWakeIngress',
    failures,
  );
  if (ingress != null) {
    _expect(
      ingress,
      'event',
      'plan393_fixed_wake_ingress',
      '$path.productionFixedWakeIngress',
      failures,
    );
    _expect(
      ingress,
      'generation',
      generation,
      '$path.productionFixedWakeIngress',
      failures,
    );
    _expect(
      ingress,
      'triggerKind',
      'FIXED_WAKE',
      '$path.productionFixedWakeIngress',
      failures,
    );
    _expect(
      ingress,
      'genericMayHaveAlerted',
      false,
      '$path.productionFixedWakeIngress',
      failures,
    );
    _expect(
      ingress,
      'genericCardTag',
      'mknoon_dropped_push_recovery',
      '$path.productionFixedWakeIngress',
      failures,
    );
    _expect(
      ingress,
      'genericCardId',
      329,
      '$path.productionFixedWakeIngress',
      failures,
    );
    _expect(
      ingress,
      'genericCardRequestedSilent',
      true,
      '$path.productionFixedWakeIngress',
      failures,
    );
    _expect(
      ingress,
      'richFlutterFireDelegated',
      false,
      '$path.productionFixedWakeIngress',
      failures,
    );
    _expect(
      ingress,
      'productionIngressInvoked',
      true,
      '$path.productionFixedWakeIngress',
      failures,
    );
  }
  final generic = _object(
    transition['genericCard'],
    '$path.genericCard',
    failures,
  );
  if (generic != null) {
    _expect(
      generic,
      'tag',
      'mknoon_dropped_push_recovery',
      '$path.genericCard',
      failures,
    );
    _expect(generic, 'id', 329, '$path.genericCard', failures);
    _expect(generic, 'observed', true, '$path.genericCard', failures);
    _expect(generic, 'requestedSilent', true, '$path.genericCard', failures);
  }
  final canonical = _object(
    transition['canonicalCard'],
    '$path.canonicalCard',
    failures,
  );
  if (canonical != null) {
    if (canonical['id'] is! int ||
        canonical['id'] == 329 ||
        canonical['id'] == 330) {
      failures.add('$path canonical card id invalid');
    }
    _expect(
      canonical,
      'producer',
      'direct_reaction',
      '$path.canonicalCard',
      failures,
    );
    _expect(
      canonical,
      'sourceCustody',
      'SQL_READY',
      '$path.canonicalCard',
      failures,
    );
    _expect(
      canonical,
      'presentationOwner',
      'INBOX_RECONCILER',
      '$path.canonicalCard',
      failures,
    );
    _expect(
      canonical,
      'effectPhase',
      'SETTLED',
      '$path.canonicalCard',
      failures,
    );
    _expect(
      canonical,
      'requestedSilent',
      false,
      '$path.canonicalCard',
      failures,
    );
    if (!_digest(canonical['titleSha256']) ||
        !_digest(canonical['bodySha256'])) {
      failures.add('$path canonical copy digests invalid');
    }
    final settlement = _object(
      canonical['settlement'],
      '$path.canonicalCard.settlement',
      failures,
    );
    if (settlement != null) {
      _expect(
        settlement,
        'sourceCustody',
        'SQL_READY',
        '$path.canonicalCard.settlement',
        failures,
      );
      _expect(
        settlement,
        'presentationOwner',
        'INBOX_RECONCILER',
        '$path.canonicalCard.settlement',
        failures,
      );
      _expect(
        settlement,
        'effectPhase',
        'SETTLED',
        '$path.canonicalCard.settlement',
        failures,
      );
      _expect(
        settlement,
        'presentationState',
        'OS_POSTED',
        '$path.canonicalCard.settlement',
        failures,
      );
    }
  }
  _expect(transition, 'genericCardRetiredAfterCanonical', true, path, failures);
  _expect(transition, 'duplicateCanonicalShowCount', 0, path, failures);
  _expect(transition, 'requestedToneCount', 1, path, failures);
  _expect(transition, 'richFlutterFireCallbackCount', 0, path, failures);
  final acknowledgement = _object(
    transition['exactMarkerAcknowledgement'],
    '$path.exactMarkerAcknowledgement',
    failures,
  );
  if (acknowledgement != null) {
    _expect(
      acknowledgement,
      'event',
      'plan393_recovery_generation_acknowledged',
      '$path.exactMarkerAcknowledgement',
      failures,
    );
    _expect(
      acknowledgement,
      'generation',
      generation,
      '$path.exactMarkerAcknowledgement',
      failures,
    );
    _expect(
      acknowledgement,
      'genericCardId',
      329,
      '$path.exactMarkerAcknowledgement',
      failures,
    );
    _expect(
      acknowledgement,
      'genericCardRetired',
      true,
      '$path.exactMarkerAcknowledgement',
      failures,
    );
    if (requireKilledWorker) {
      _expect(
        acknowledgement,
        'owner',
        'headless',
        '$path.exactMarkerAcknowledgement',
        failures,
      );
    }
  }
  _references(
    transition['notificationSnapshots'],
    artifactDirectory,
    '$path.notificationSnapshots',
    failures,
    exactLength: 2,
  );
  _references(
    transition['runtimeEvidence'],
    artifactDirectory,
    '$path.runtimeEvidence',
    failures,
    exactLength: 2,
  );
  _reference(
    transition['relayJournal'],
    artifactDirectory,
    '$path.relayJournal',
    failures,
  );
  if (lifecycle == 'alive_backgrounded') {
    _reference(
      transition['exactChatActivation'],
      artifactDirectory,
      '$path.exactChatActivation',
      failures,
    );
  }
  if (requireKilledWorker) {
    _expect(transition, 'processAbsentBeforeSend', true, path, failures);
    final arm = _object(
      transition['barrierArmReceipt'],
      '$path.barrierArmReceipt',
      failures,
    );
    if (arm != null) {
      _expect(arm, 'status', 'PASS', '$path.barrierArmReceipt', failures);
      _expect(
        arm,
        'phase',
        'arm-fixed-wake',
        '$path.barrierArmReceipt',
        failures,
      );
      _expect(
        arm,
        'processDeathBarrierArmed',
        true,
        '$path.barrierArmReceipt',
        failures,
      );
      _expect(
        arm,
        'productionIngressInvoked',
        false,
        '$path.barrierArmReceipt',
        failures,
      );
      _expect(
        arm,
        'pendingGenerationBefore',
        null,
        '$path.barrierArmReceipt',
        failures,
      );
      _expect(
        arm,
        'pendingGenerationAfter',
        null,
        '$path.barrierArmReceipt',
        failures,
      );
      _expect(
        arm,
        'mainActivityLaunchCount',
        0,
        '$path.barrierArmReceipt',
        failures,
      );
      if (!_digest(arm['receiptSha256'])) {
        failures.add('$path barrier receipt digest invalid');
      }
    }
    final firstPid = transition['firstWorkerPid'];
    final resumedPid = transition['resumedWorkerPid'];
    if (firstPid is! int ||
        firstPid <= 0 ||
        resumedPid is! int ||
        resumedPid <= 0 ||
        firstPid == resumedPid) {
      failures.add('$path worker PID provenance invalid');
    }
    final attempt = transition['runAttemptCount'];
    if (attempt is! int || attempt < 1) {
      failures.add('$path runAttemptCount must prove retry');
    }
    _expect(transition, 'terminalOutcome', 'SUCCESS', path, failures);
    if (acknowledgement != null && acknowledgement['pid'] != resumedPid) {
      failures.add('$path ACK PID does not match resumed worker');
    }
    _reference(
      transition['jobSchedulerBaseline'],
      artifactDirectory,
      '$path.jobSchedulerBaseline',
      failures,
    );
    _reference(
      transition['jobSchedulerAudit'],
      artifactDirectory,
      '$path.jobSchedulerAudit',
      failures,
    );
  }
  return transition;
}

(int, int)? _route(
  Object? value,
  String path,
  Directory directory,
  List<String> failures,
) {
  final route = _object(value, path, failures);
  if (route == null) return null;
  _exactKeys(
    route,
    const <String>{'opaque', 'rich', 'evidence'},
    path,
    failures,
  );
  final opaque = route['opaque'];
  final rich = route['rich'];
  if (opaque is! int || opaque < 0 || rich is! int || rich < 0) {
    failures.add('$path counters invalid');
    return null;
  }
  _reference(route['evidence'], directory, '$path.evidence', failures);
  return (opaque, rich);
}

void _device(
  Object? value,
  String path,
  String kind,
  String role,
  String? expectedId,
  List<String> failures,
) {
  final device = _object(value, path, failures);
  if (device == null) return;
  _exactKeys(
    device,
    const <String>{'deviceId', 'kind', 'role'},
    path,
    failures,
  );
  _expect(device, 'kind', kind, path, failures);
  _expect(device, 'role', role, path, failures);
  final id = device['deviceId'];
  if (id is! String || !RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(id)) {
    failures.add('$path.deviceId invalid');
  }
  if (expectedId != null && id != expectedId) {
    failures.add('$path.deviceId mismatch');
  }
  if (kind == 'physical' && id is String && id.startsWith('emulator-')) {
    failures.add('$path physical device is emulator-shaped');
  }
  if (kind == 'emulator' &&
      id is String &&
      !RegExp(r'^emulator-[0-9]+$').hasMatch(id)) {
    failures.add('$path emulator device is not live-ID shaped');
  }
}

void _references(
  Object? value,
  Directory directory,
  String path,
  List<String> failures, {
  required int exactLength,
}) {
  if (value is! List || value.length != exactLength) {
    failures.add('$path must contain $exactLength references');
    return;
  }
  for (var index = 0; index < value.length; index += 1) {
    _reference(value[index], directory, '$path[$index]', failures);
  }
}

void _reference(
  Object? value,
  Directory directory,
  String path,
  List<String> failures,
) {
  final reference = _object(value, path, failures);
  if (reference == null) return;
  _exactKeys(
    reference,
    const <String>{'path', 'sha256', 'bytes'},
    path,
    failures,
  );
  final relative = reference['path'];
  if (relative is! String ||
      relative.isEmpty ||
      relative.contains('/') ||
      relative.contains(r'\') ||
      relative == '.' ||
      relative == '..') {
    failures.add('$path.path is not one adjacent filename');
    return;
  }
  final file = File('${directory.path}${Platform.pathSeparator}$relative');
  if (!_regular(file, followLinks: false)) {
    failures.add('$path attachment missing');
    return;
  }
  final bytes = file.readAsBytesSync();
  if (reference['bytes'] != bytes.length ||
      reference['sha256'] != sha256.convert(bytes).toString()) {
    failures.add('$path content address mismatch');
  }
}

Map<String, Object?>? _readObject(
  File file,
  String path,
  List<String> failures,
) {
  if (!_regular(file, followLinks: false)) {
    failures.add('$path is not a regular file');
    return null;
  }
  try {
    final value = jsonDecode(file.readAsStringSync());
    return _object(value, path, failures);
  } on Object {
    failures.add('$path is not JSON');
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

void _exactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
  List<String> failures,
) {
  final actual = value.keys.toSet();
  if (actual.length != expected.length || !actual.containsAll(expected)) {
    failures.add('$path keys mismatch');
  }
}

void _expect(
  Map<String, Object?> value,
  String key,
  Object? expected,
  String path,
  List<String> failures,
) {
  if (!_deepEqual(value[key], expected)) failures.add('$path.$key mismatch');
}

bool _deepEqual(Object? left, Object? right) {
  if (left is List && right is List) {
    return left.length == right.length &&
        List<int>.generate(
          left.length,
          (index) => index,
        ).every((index) => _deepEqual(left[index], right[index]));
  }
  if (left is Map && right is Map) {
    final l = left.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    final r = right.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    return l.length == r.length &&
        l.keys.every((key) => r.containsKey(key) && _deepEqual(l[key], r[key]));
  }
  return left == right;
}

bool _digest(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

void _utc(Object? value, String path, List<String> failures) {
  if (value is! String || DateTime.tryParse(value)?.isUtc != true) {
    failures.add('$path must be UTC');
  }
}

bool _regular(File file, {required bool followLinks}) =>
    FileSystemEntity.typeSync(file.absolute.path, followLinks: followLinks) ==
    FileSystemEntityType.file;
