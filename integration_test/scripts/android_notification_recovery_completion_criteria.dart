import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const String androidNotificationRecoveryCompletionCapabilityId =
    'notifications.android_recovery_completion';
const String androidNotificationRecoveryCompletionValidator =
    'integration_test/android_notification_recovery_completion_proof_test.dart';
const String androidNotificationRecoveryCompletionCampaignSchema =
    'mknoon.plan331.android-notification-recovery-completion.v1';
const String androidNotificationRecoveryCompletionReceiptSchema =
    'mknoon.plan331.android-notification-recovery-receipt.v1';
const String androidNotificationRecoveryCompletionCommandSchema =
    'mknoon.plan331.android-notification-command-journal.v1';
const String plan331PhysicalAndroidDeviceId = '21071FDF600CSC';
const String plan331AndroidEmulatorDeviceId = 'emulator-5554';

const List<String> androidNotificationRecoveryCompletionAssertions = <String>[
  'notifications.headless_direct_group_recovery',
  'notifications.foreground_handoff_new_generation',
  'notifications.direct_custody_recovery',
  'notifications.synthetic_outer_id_recovery',
  'notifications.history_count_projection',
  'notifications.registration_health_live_recovery',
  'notifications.recovery_copy_locales',
  'notifications.zero_taps_zero_child_builds',
];

const List<String> androidNotificationRecoveryCompletionScenarioIds = <String>[
  'headless_direct_group_recovery',
  'foreground_handoff_new_generation',
  'direct_custody_recovery',
  'synthetic_outer_id_removal',
  'history_registration_health',
  'localized_recovery_copy',
];

final class AndroidNotificationRecoveryCompletionValidation {
  AndroidNotificationRecoveryCompletionValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

/// Validates the final Sims proof and every content-addressed raw attachment.
///
/// Normalized `passed` booleans are never sufficient. The validator replays
/// command ordering, app receipt binding, relay provenance, process absence,
/// OS-card evidence, and scenario-specific invariants from files adjacent to
/// the aggregate proof.
AndroidNotificationRecoveryCompletionValidation
validateAndroidNotificationRecoveryCompletionArtifact({
  required File artifactFile,
  String expectedPhysicalDeviceId = plan331PhysicalAndroidDeviceId,
  String expectedEmulatorDeviceId = plan331AndroidEmulatorDeviceId,
  String? expectedApkSha256,
  String? expectedPackageName,
}) {
  final failures = <String>[];
  if (!_isRegularFile(artifactFile, followLinks: false)) {
    return AndroidNotificationRecoveryCompletionValidation(<String>[
      'proof artifact is not a regular file: ${artifactFile.path}',
    ]);
  }

  final artifact = _decodeObject(
    artifactFile.readAsStringSync(),
    r'$',
    failures,
  );
  if (artifact == null) {
    return AndroidNotificationRecoveryCompletionValidation(failures);
  }
  _expectExactKeys(
    artifact,
    const <String>{
      'schema',
      'campaignSchema',
      'capabilityId',
      'validatorIds',
      'status',
      'recordedAt',
      'buildProfile',
      'preparedArtifactSha256',
      'packageName',
      'childBuildCount',
      'manualTaps',
      'notificationCardTaps',
      'headlessActivityLaunchCount',
      'forbiddenProcessStopCount',
      'platforms',
      'physicalDeviceId',
      'emulatorDeviceId',
      'scenarios',
    },
    r'$',
    failures,
  );
  _expectValue(artifact, 'schema', 'mknoon.sims.proof.v1', r'$', failures);
  _expectValue(
    artifact,
    'campaignSchema',
    androidNotificationRecoveryCompletionCampaignSchema,
    r'$',
    failures,
  );
  _expectValue(
    artifact,
    'capabilityId',
    androidNotificationRecoveryCompletionCapabilityId,
    r'$',
    failures,
  );
  _expectValue(artifact, 'status', 'passed', r'$', failures);
  _expectValue(
    artifact,
    'validatorIds',
    const <String>[androidNotificationRecoveryCompletionValidator],
    r'$',
    failures,
  );
  _expectUtcTimestamp(artifact['recordedAt'], r'$.recordedAt', failures);
  _expectValue(
    artifact,
    'buildProfile',
    'android.production_fcm',
    r'$',
    failures,
  );
  for (final key in const <String>[
    'childBuildCount',
    'manualTaps',
    'notificationCardTaps',
    'headlessActivityLaunchCount',
    'forbiddenProcessStopCount',
  ]) {
    _expectValue(artifact, key, 0, r'$', failures);
  }
  _expectValue(
    artifact,
    'platforms',
    const <String>['android'],
    r'$',
    failures,
  );
  _expectValue(
    artifact,
    'physicalDeviceId',
    expectedPhysicalDeviceId,
    r'$',
    failures,
  );
  _expectValue(
    artifact,
    'emulatorDeviceId',
    expectedEmulatorDeviceId,
    r'$',
    failures,
  );
  final apkSha = artifact['preparedArtifactSha256'];
  if (!_isSha256(apkSha)) {
    failures.add(r'$.preparedArtifactSha256 must be a lowercase SHA-256');
  } else if (expectedApkSha256 != null && apkSha != expectedApkSha256) {
    failures.add(r'$.preparedArtifactSha256 does not bind the prepared APK');
  }
  final packageName = artifact['packageName'];
  if (packageName is! String ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$').hasMatch(packageName)) {
    failures.add(r'$.packageName is not a safe Android package');
  } else if (expectedPackageName != null &&
      packageName != expectedPackageName) {
    failures.add(r'$.packageName does not match the prepared app');
  }

  final scenarios = artifact['scenarios'];
  final expectedPairs = <String>{
    for (final scenarioId in androidNotificationRecoveryCompletionScenarioIds)
      '$scenarioId@$expectedPhysicalDeviceId',
    for (final scenarioId in androidNotificationRecoveryCompletionScenarioIds)
      '$scenarioId@$expectedEmulatorDeviceId',
  };
  if (scenarios is! List || scenarios.length != expectedPairs.length) {
    failures.add(
      r'$.scenarios must contain every scenario in both Android receiver roles',
    );
    return AndroidNotificationRecoveryCompletionValidation(failures);
  }

  final observedPairs = <String>{};
  for (var index = 0; index < scenarios.length; index += 1) {
    final path = '\$.scenarios[$index]';
    final scenario = _object(scenarios[index], path, failures);
    if (scenario == null) continue;
    _expectExactKeys(
      scenario,
      const <String>{
        'id',
        'mode',
        'receiverDeviceId',
        'senderDeviceId',
        'evidence',
      },
      path,
      failures,
    );
    final id = scenario['id'];
    final receiver = scenario['receiverDeviceId'];
    final sender = scenario['senderDeviceId'];
    if (id is! String ||
        !androidNotificationRecoveryCompletionScenarioIds.contains(id)) {
      failures.add('$path.id is not a registered Plan-331 scenario');
      continue;
    }
    if (receiver is! String ||
        !<String>{
          expectedPhysicalDeviceId,
          expectedEmulatorDeviceId,
        }.contains(receiver)) {
      failures.add('$path.receiverDeviceId is not an assigned Android target');
      continue;
    }
    final expectedSender = receiver == expectedPhysicalDeviceId
        ? expectedEmulatorDeviceId
        : expectedPhysicalDeviceId;
    if (sender != expectedSender) {
      failures.add('$path.senderDeviceId must be the other assigned target');
    }
    final pair = '$id@$receiver';
    if (!observedPairs.add(pair)) {
      failures.add('$path duplicates $pair');
    }
    _expectValue(
      scenario,
      'mode',
      id == 'synthetic_outer_id_removal'
          ? 'test_only_transport_mutation'
          : 'real_relay',
      path,
      failures,
    );
    _validateScenarioEvidence(
      artifactFile: artifactFile,
      scenario: scenario,
      path: path,
      scenarioId: id,
      receiverDeviceId: receiver,
      senderDeviceId: expectedSender,
      packageName: packageName is String ? packageName : '',
      failures: failures,
    );
  }
  if (!_sameStringSet(observedPairs, expectedPairs)) {
    failures.add(r'$.scenarios receiver-role matrix is incomplete');
  }
  return AndroidNotificationRecoveryCompletionValidation(failures);
}

void _validateScenarioEvidence({
  required File artifactFile,
  required Map<String, Object?> scenario,
  required String path,
  required String scenarioId,
  required String receiverDeviceId,
  required String senderDeviceId,
  required String packageName,
  required List<String> failures,
}) {
  final evidence = _object(scenario['evidence'], '$path.evidence', failures);
  if (evidence == null) return;
  final expectedKeys = <String>{
    'receipt',
    'flowLog',
    'notificationDump',
    'activityDump',
    'relayJournal',
    'commandJournal',
    if (scenarioId == 'localized_recovery_copy') ...<String>{
      'localeEnDump',
      'localeDeDump',
      'localeArDump',
      'localeFallbackDump',
    },
  };
  _expectExactKeys(evidence, expectedKeys, '$path.evidence', failures);
  final raw = <String, String>{};
  for (final key in expectedKeys) {
    final value = _readEvidence(
      evidence[key],
      artifactFile: artifactFile,
      path: '$path.evidence.$key',
      failures: failures,
    );
    if (value != null) raw[key] = value;
  }
  final receipt = _decodeObject(
    raw['receipt'] ?? '',
    '$path.evidence.receipt',
    failures,
  );
  if (receipt == null) return;
  _expectExactKeys(
    receipt,
    const <String>{
      'schema',
      'scenarioId',
      'runId',
      'nonce',
      'status',
      'receiverDeviceId',
      'senderDeviceId',
      'facts',
    },
    '$path.evidence.receipt',
    failures,
  );
  _expectValue(
    receipt,
    'schema',
    androidNotificationRecoveryCompletionReceiptSchema,
    '$path.evidence.receipt',
    failures,
  );
  _expectValue(
    receipt,
    'scenarioId',
    scenarioId,
    '$path.evidence.receipt',
    failures,
  );
  _expectValue(
    receipt,
    'receiverDeviceId',
    receiverDeviceId,
    '$path.evidence.receipt',
    failures,
  );
  _expectValue(
    receipt,
    'senderDeviceId',
    senderDeviceId,
    '$path.evidence.receipt',
    failures,
  );
  _expectValue(receipt, 'status', 'passed', '$path.evidence.receipt', failures);
  final runId = _safeToken(
    receipt['runId'],
    '$path.evidence.receipt.runId',
    failures,
  );
  final nonce = _safeToken(
    receipt['nonce'],
    '$path.evidence.receipt.nonce',
    failures,
  );
  final flow = raw['flowLog'] ?? '';
  final relay = raw['relayJournal'] ?? '';
  final notifications = raw['notificationDump'] ?? '';
  final activity = raw['activityDump'] ?? '';
  if (runId != null && !flow.contains(runId)) {
    failures.add('$path.evidence.flowLog is not bound to the receipt runId');
  }
  if (scenarioId != 'synthetic_outer_id_removal' &&
      runId != null &&
      (!relay.contains(runId) ||
          !RegExp(
            r'(relay|inbox|push|fcm)',
            caseSensitive: false,
          ).hasMatch(relay))) {
    failures.add('$path.evidence.relayJournal lacks real-relay run binding');
  }
  if (!notifications.contains(packageName)) {
    failures.add('$path.evidence.notificationDump lacks the package boundary');
  }
  for (final secretMarker in const <String>[
    '-----BEGIN PRIVATE KEY-----',
    '"private_key"',
    '"client_email"',
  ]) {
    if (raw.values.any((value) => value.contains(secretMarker))) {
      failures.add('$path evidence contains forbidden credential material');
    }
  }
  _validateCommandJournal(
    raw['commandJournal'] ?? '',
    scenarioId: scenarioId,
    runId: runId,
    nonce: nonce,
    receiverDeviceId: receiverDeviceId,
    allowedDevices: <String>{receiverDeviceId, senderDeviceId},
    path: '$path.evidence.commandJournal',
    failures: failures,
  );
  final facts = _object(
    receipt['facts'],
    '$path.evidence.receipt.facts',
    failures,
  );
  if (facts == null) return;
  switch (scenarioId) {
    case 'headless_direct_group_recovery':
      _expectExactKeys(
        facts,
        const <String>{
          'generation',
          'directRowsRecovered',
          'groupRowsRecovered',
          'directCards',
          'groupCards',
          'generationAcknowledged',
          'duplicateCount',
          'activityLaunchesBeforeAck',
        },
        '$path.evidence.receipt.facts',
        failures,
      );
      _expectPositive(facts['generation'], '$path.facts.generation', failures);
      _expectPositive(
        facts['directRowsRecovered'],
        '$path.facts.directRowsRecovered',
        failures,
      );
      _expectPositive(
        facts['groupRowsRecovered'],
        '$path.facts.groupRowsRecovered',
        failures,
      );
      for (final key in const <String>['directCards', 'groupCards']) {
        _expectValue(facts, key, 1, '$path.facts', failures);
      }
      _expectValue(
        facts,
        'generationAcknowledged',
        true,
        '$path.facts',
        failures,
      );
      _expectValue(facts, 'duplicateCount', 0, '$path.facts', failures);
      _expectValue(
        facts,
        'activityLaunchesBeforeAck',
        0,
        '$path.facts',
        failures,
      );
      _expectOrdered(
        flow,
        const <String>[
          'RECOVERY_GENERATION_COMMITTED',
          'CANONICAL_RECOVERY_HEADLESS_STARTED',
          'DIRECT_INBOX_DRAIN_EXHAUSTED',
          'GROUP_INBOX_DRAIN_EXHAUSTED',
          'NOTIFICATION_SETTLEMENT_COMPLETE',
          'RECOVERY_GENERATION_ACKNOWLEDGED',
        ],
        '$path.evidence.flowLog',
        failures,
      );
      if (RegExp(
        '${RegExp.escape(packageName)}/\\.MainActivity',
        caseSensitive: false,
      ).hasMatch(activity)) {
        failures.add('$path headless activity dump shows MainActivity');
      }
    case 'foreground_handoff_new_generation':
      _expectExactKeys(
        facts,
        const <String>{
          'firstGeneration',
          'newerGeneration',
          'soleOwner',
          'staleCompletionRejected',
          'newerGenerationAcknowledged',
          'duplicateCount',
        },
        '$path.evidence.receipt.facts',
        failures,
      );
      final first = _positiveInt(facts['firstGeneration']);
      final newer = _positiveInt(facts['newerGeneration']);
      if (first == null || newer == null || newer <= first) {
        failures.add('$path handoff generations are not monotonic');
      }
      for (final key in const <String>[
        'soleOwner',
        'staleCompletionRejected',
        'newerGenerationAcknowledged',
      ]) {
        _expectValue(facts, key, true, '$path.facts', failures);
      }
      _expectValue(facts, 'duplicateCount', 0, '$path.facts', failures);
      _expectOrdered(
        flow,
        const <String>[
          'RECOVERY_OWNER_DRAINING',
          'FOREGROUND_HANDOFF_ACQUIRED',
          'STALE_RECOVERY_COMPLETION_REJECTED',
          'NEWER_RECOVERY_GENERATION_ACKNOWLEDGED',
        ],
        '$path.evidence.flowLog',
        failures,
      );
    case 'direct_custody_recovery':
      _expectExactKeys(
        facts,
        const <String>{
          'eventKinds',
          'firstShowFailureInjected',
          'readyCustodyRetained',
          'restartRetryCount',
          'duplicateCount',
        },
        '$path.evidence.receipt.facts',
        failures,
      );
      _expectValue(
        facts,
        'eventKinds',
        const <String>['text', 'photo', 'video', 'voiceMessage', 'reactionAdd'],
        '$path.facts',
        failures,
      );
      _expectValue(
        facts,
        'firstShowFailureInjected',
        true,
        '$path.facts',
        failures,
      );
      _expectValue(
        facts,
        'readyCustodyRetained',
        true,
        '$path.facts',
        failures,
      );
      _expectValue(facts, 'restartRetryCount', 1, '$path.facts', failures);
      _expectValue(facts, 'duplicateCount', 0, '$path.facts', failures);
    case 'synthetic_outer_id_removal':
      _expectExactKeys(
        facts,
        const <String>{
          'label',
          'ordinaryRelayClaim',
          'authenticCiphertextRetained',
          'authenticatedInnerIdentityPromoted',
          'exactClaimAndReadFence',
          'identityFreeFallbackSilent',
        },
        '$path.evidence.receipt.facts',
        failures,
      );
      _expectValue(
        facts,
        'label',
        'test_only_outer_id_removal',
        '$path.facts',
        failures,
      );
      _expectValue(facts, 'ordinaryRelayClaim', false, '$path.facts', failures);
      for (final key in const <String>[
        'authenticCiphertextRetained',
        'authenticatedInnerIdentityPromoted',
        'exactClaimAndReadFence',
        'identityFreeFallbackSilent',
      ]) {
        _expectValue(facts, key, true, '$path.facts', failures);
      }
      if (!flow.contains('TEST_ONLY_OUTER_ID_REMOVAL') ||
          flow.contains('ORDINARY_RELAY_MISSING_OUTER_ID')) {
        failures.add(
          '$path synthetic mutation is mislabeled as ordinary relay',
        );
      }
    case 'history_registration_health':
      _expectExactKeys(
        facts,
        const <String>{
          'historyLineCount',
          'totalUnreadCount',
          'androidNumber',
          'stableConversationCardCount',
          'healthPhases',
          'warningActionAutomated',
          'warningClearedLive',
        },
        '$path.evidence.receipt.facts',
        failures,
      );
      _expectValue(facts, 'historyLineCount', 5, '$path.facts', failures);
      final total = _positiveInt(facts['totalUnreadCount']);
      if (total == null || total <= 5 || facts['androidNumber'] != total) {
        failures.add(
          '$path history count is capped or not bound to Android number',
        );
      }
      _expectValue(
        facts,
        'stableConversationCardCount',
        2,
        '$path.facts',
        failures,
      );
      _expectValue(
        facts,
        'healthPhases',
        const <String>[
          'healthy',
          'transient',
          'thresholdWarning',
          'permissionDenied',
          'retrying',
          'healthy',
        ],
        '$path.facts',
        failures,
      );
      _expectValue(
        facts,
        'warningActionAutomated',
        true,
        '$path.facts',
        failures,
      );
      _expectValue(facts, 'warningClearedLive', true, '$path.facts', failures);
      if (!notifications.contains('android.messages') ||
          !RegExp(
            r'(number|mNumber)\s*[=:]\s*[6-9][0-9]*',
            caseSensitive: false,
          ).hasMatch(notifications)) {
        failures.add(
          '$path notification dump lacks InboxStyle history/full number',
        );
      }
    case 'localized_recovery_copy':
      _expectExactKeys(
        facts,
        const <String>{
          'locales',
          'stableChannelId',
          'importancePreserved',
          'unsupportedLocaleUsedDefault',
        },
        '$path.evidence.receipt.facts',
        failures,
      );
      _expectValue(
        facts,
        'locales',
        const <String>['en', 'de', 'ar', 'unsupported-default'],
        '$path.facts',
        failures,
      );
      for (final key in const <String>[
        'stableChannelId',
        'importancePreserved',
        'unsupportedLocaleUsedDefault',
      ]) {
        _expectValue(facts, key, true, '$path.facts', failures);
      }
      _expectLocalizedDump(
        raw['localeEnDump'],
        const <String>[
          'mknoon_dropped_push_recovery',
          'Message recovery',
          'Messages may be waiting',
        ],
        '$path.evidence.localeEnDump',
        failures,
      );
      _expectLocalizedDump(
        raw['localeDeDump'],
        const <String>[
          'mknoon_dropped_push_recovery',
          'Nachrichtenwiederherstellung',
          'Möglicherweise warten Nachrichten',
        ],
        '$path.evidence.localeDeDump',
        failures,
      );
      _expectLocalizedDump(
        raw['localeArDump'],
        const <String>[
          'mknoon_dropped_push_recovery',
          'استرداد الرسائل',
          'قد تكون هناك رسائل بانتظار الاسترداد',
        ],
        '$path.evidence.localeArDump',
        failures,
      );
      _expectLocalizedDump(
        raw['localeFallbackDump'],
        const <String>[
          'mknoon_dropped_push_recovery',
          'Message recovery',
          'Messages may be waiting',
        ],
        '$path.evidence.localeFallbackDump',
        failures,
      );
  }
}

void _validateCommandJournal(
  String encoded, {
  required String scenarioId,
  required String? runId,
  required String? nonce,
  required String receiverDeviceId,
  required Set<String> allowedDevices,
  required String path,
  required List<String> failures,
}) {
  final journal = _decodeObject(encoded, path, failures);
  if (journal == null) return;
  _expectExactKeys(
    journal,
    const <String>{'schema', 'scenarioId', 'runId', 'nonce', 'commands'},
    path,
    failures,
  );
  _expectValue(
    journal,
    'schema',
    androidNotificationRecoveryCompletionCommandSchema,
    path,
    failures,
  );
  _expectValue(journal, 'scenarioId', scenarioId, path, failures);
  _expectValue(journal, 'runId', runId, path, failures);
  _expectValue(journal, 'nonce', nonce, path, failures);
  final commands = journal['commands'];
  if (commands is! List || commands.isEmpty) {
    failures.add('$path.commands must contain actual host-driven commands');
    return;
  }
  final joined = <String>[];
  final stdoutEmpty = <bool?>[];
  final phases = <String>[];
  var boundRecoveryBroadcastObserved = false;
  for (var index = 0; index < commands.length; index += 1) {
    final itemPath = '$path.commands[$index]';
    final command = _object(commands[index], itemPath, failures);
    if (command == null) continue;
    _expectExactKeys(
      command,
      const <String>{
        'phase',
        'device',
        'args',
        'exitCode',
        'stdoutEmpty',
        'capturedAt',
      },
      itemPath,
      failures,
    );
    final phase = command['phase'];
    final device = command['device'];
    final args = command['args'];
    if (phase is! String ||
        !const <String>{
          'setup',
          'termination',
          'headless',
          'capture',
          'teardown',
        }.contains(phase)) {
      failures.add('$itemPath.phase is invalid');
    } else {
      phases.add(phase);
    }
    if (device is! String || !allowedDevices.contains(device)) {
      failures.add('$itemPath.device is outside the assigned pair');
    }
    if (args is! List ||
        args.isEmpty ||
        args.any((value) => value is! String)) {
      failures.add('$itemPath.args must be a nonempty string array');
      continue;
    }
    final tokens = args.cast<String>();
    final line = tokens.join(' ');
    joined.add(line);
    if (device == receiverDeviceId &&
        runId != null &&
        nonce != null &&
        _containsSubsequence(tokens, <String>[
          'am',
          'broadcast',
          '-a',
          'com.mknoon.app.debug.NOTIFICATION_RECOVERY_COMPLETION',
          '--es',
          'scenarioId',
          scenarioId,
          '--es',
          'runId',
          runId,
          '--es',
          'nonce',
          nonce,
        ])) {
      boundRecoveryBroadcastObserved = true;
    }
    stdoutEmpty.add(
      command['stdoutEmpty'] is bool ? command['stdoutEmpty']! as bool : null,
    );
    if (line.contains('force-stop') ||
        RegExp(r'(^| )input tap( |$)').hasMatch(line) ||
        line.contains('click-notification')) {
      failures.add('$itemPath contains a forbidden process stop/card tap');
    }
    if ((phase == 'termination' || phase == 'headless') &&
        line.contains('am start')) {
      failures.add('$itemPath launches an Activity during the headless window');
    }
    if (command['exitCode'] is! int) {
      failures.add('$itemPath.exitCode must be an integer');
    }
    if (command['stdoutEmpty'] is! bool) {
      failures.add('$itemPath.stdoutEmpty must be boolean');
    }
    _expectUtcTimestamp(
      command['capturedAt'],
      '$itemPath.capturedAt',
      failures,
    );
  }
  if (!boundRecoveryBroadcastObserved) {
    failures.add(
      '$path lacks the exact receiver scenario/run/nonce recovery broadcast',
    );
  }
  if (scenarioId == 'headless_direct_group_recovery') {
    final home = joined.indexWhere((line) => line.contains('KEYCODE_HOME'));
    final kill = joined.indexWhere(
      (line) =>
          line.contains('am kill') && line.contains(receiverDeviceId) == false,
      home < 0 ? 0 : home + 1,
    );
    final firstPid = joined.indexWhere(
      (line) => line.contains('pidof'),
      kill < 0 ? 0 : kill + 1,
    );
    final lastPid = joined.lastIndexWhere((line) => line.contains('pidof'));
    final boundedStop = joined.indexWhere(
      (line) => line.contains('cmd activity stop-app'),
      firstPid < 0 ? 0 : firstPid + 1,
    );
    if (home < 0 || kill <= home || firstPid <= kill || lastPid < firstPid) {
      failures.add(
        '$path lacks ordered HOME, am kill, and bounded pidof proof',
      );
    }
    if (boundedStop >= 0 && lastPid <= boundedStop) {
      failures.add('$path stop-app fallback lacks a final empty-pid proof');
    }
    if (!phases.contains('headless')) {
      failures.add('$path lacks a headless command phase');
    }
    if (lastPid < 0 || stdoutEmpty[lastPid] != true) {
      failures.add('$path final pidof observation is not empty');
    }
  }
}

String? _readEvidence(
  Object? value, {
  required File artifactFile,
  required String path,
  required List<String> failures,
}) {
  final ref = _object(value, path, failures);
  if (ref == null) return null;
  _expectExactKeys(
    ref,
    const <String>{'path', 'sha256', 'bytes'},
    path,
    failures,
  );
  final relative = ref['path'];
  final digest = ref['sha256'];
  final byteCount = ref['bytes'];
  if (relative is! String ||
      relative.isEmpty ||
      relative.startsWith('/') ||
      relative.contains('..') ||
      relative.contains('\\')) {
    failures.add('$path.path must be a safe relative sibling path');
    return null;
  }
  if (!_isSha256(digest) ||
      byteCount is! int ||
      byteCount <= 0 ||
      byteCount > 10000000) {
    failures.add('$path has invalid digest/byte metadata');
    return null;
  }
  final file = File(
    '${artifactFile.parent.path}${Platform.pathSeparator}$relative',
  );
  if (!_isRegularFile(file, followLinks: false)) {
    failures.add('$path does not resolve to a regular evidence file');
    return null;
  }
  final bytes = file.readAsBytesSync();
  if (bytes.length != byteCount || sha256.convert(bytes).toString() != digest) {
    failures.add('$path content address does not match the evidence file');
    return null;
  }
  return utf8.decode(bytes, allowMalformed: false);
}

void _expectLocalizedDump(
  String? value,
  List<String> needles,
  String path,
  List<String> failures,
) {
  if (value == null || needles.any((needle) => !value.contains(needle))) {
    failures.add('$path lacks stable channel and localized recovery copy');
  }
}

void _expectOrdered(
  String value,
  List<String> markers,
  String path,
  List<String> failures,
) {
  var cursor = -1;
  for (final marker in markers) {
    final next = value.indexOf(marker, cursor + 1);
    if (next <= cursor) {
      failures.add('$path lacks ordered marker $marker');
      return;
    }
    cursor = next;
  }
}

Map<String, Object?>? _decodeObject(
  String encoded,
  String path,
  List<String> failures,
) {
  try {
    return _object(jsonDecode(encoded), path, failures);
  } on Object {
    failures.add('$path is not valid JSON');
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
  if (!_sameStringSet(value.keys.toSet(), expected)) {
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
  if (jsonEncode(value[key]) != jsonEncode(expected)) {
    failures.add('$path.$key must equal ${jsonEncode(expected)}');
  }
}

String? _safeToken(Object? value, String path, List<String> failures) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 160 ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    failures.add('$path must be a safe bound token');
    return null;
  }
  return value;
}

void _expectPositive(Object? value, String path, List<String> failures) {
  if (_positiveInt(value) == null) {
    failures.add('$path must be a positive integer');
  }
}

int? _positiveInt(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value.toInt() == value && value > 0) {
    return value.toInt();
  }
  return null;
}

void _expectUtcTimestamp(Object? value, String path, List<String> failures) {
  if (value is! String) {
    failures.add('$path must be a UTC timestamp');
    return;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    failures.add('$path must be a canonical UTC timestamp');
  }
}

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isRegularFile(File file, {required bool followLinks}) =>
    FileSystemEntity.typeSync(file.path, followLinks: followLinks) ==
    FileSystemEntityType.file;

bool _sameStringSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _containsSubsequence(List<String> values, List<String> expected) {
  if (expected.isEmpty) return true;
  var expectedIndex = 0;
  for (final value in values) {
    if (value != expected[expectedIndex]) continue;
    expectedIndex += 1;
    if (expectedIndex == expected.length) return true;
  }
  return false;
}
