import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/database/app_database_version.dart';

import 'group_media_reliability_criteria.dart';

const String groupMediaIosBackgroundRecoveryArtifactSchema =
    'mknoon.group-media-ios-background-recovery.v1';
const String groupMediaIosFixtureReceiptSchema =
    'mknoon.group-media-ios-fixture-receipt.v1';
const String groupMediaIosNativeObservationSchema =
    'mknoon.group-media-ios-native-observation.v1';
const String groupMediaIosDatabaseObservationSchema =
    'mknoon.group-media-ios-database-observation.v1';
const String groupMediaIosBackgroundRecoveryArtifactValidatorId =
    'validateGroupMediaIosBackgroundRecoveryArtifact';
const String groupMediaIosBackgroundRecoveryXctestSelector =
    'RunnerUITests/GroupMediaBackgroundRecoveryUITests/'
    'testReceiverBackgroundRecovery';

const List<String> groupMediaIosBackgroundRecoveryFlowEvents = <String>[
  'local_network_permission_ready',
  'prepared_bundle_validated',
  'pixel_sender_verified',
  'physical_iphone_verified',
  'phase_a_home_pressed',
  'phase_a_task_granted',
  'phase_a_normal_end',
  'phase_a_effect_visible',
  'phase_b_home_pressed',
  'phase_b_durable_post_claim',
  'phase_b_host_terminated',
  'phase_b_interrupted',
  'phase_b_relaunched_without_group_route',
  'phase_b_resume_after_drain',
  'phase_b_effect_visible',
];

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _safeRunIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$');
const List<String> _androidResetActions = <String>[
  'phase-a-background-success',
  'phase-b-stop-at-post-claim',
];

final class GroupMediaIosBackgroundRecoveryValidation {
  GroupMediaIosBackgroundRecoveryValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;
  String get detail => ok ? 'accepted' : failures.join('; ');
}

GroupMediaIosBackgroundRecoveryValidation
validateGroupMediaIosBoundaryObservation({
  required Object? value,
  required String section,
  required String runId,
  required String receiverDigest,
}) {
  final failures = <String>[];
  if (!const <String>{
    'phase_a',
    'phase_b_claim',
    'phase_b_recovery',
  }.contains(section)) {
    failures.add(r'$.boundary_observations has an unknown section');
    return GroupMediaIosBackgroundRecoveryValidation(failures);
  }
  _validateObservationPair(
    value,
    phase: section,
    path: r'$.boundary_observations.' + section,
    runId: runId,
    receiverDigest: receiverDigest,
    failures: failures,
  );
  return GroupMediaIosBackgroundRecoveryValidation(failures);
}

/// Validates the independent iOS suspension artifact.
///
/// This schema is deliberately distinct from the Android media round-trip
/// schema. It binds observations produced by three independent boundaries:
/// the prebuilt XCTest controller, the fixture/database observer, and the host
/// process controller. A generic scenario runner cannot satisfy the artifact
/// by merely echoing its own command plan.
GroupMediaIosBackgroundRecoveryValidation
validateGroupMediaIosBackgroundRecoveryArtifact(Object? value) {
  final failures = <String>[];
  final artifact = _object(value, r'$', failures);
  if (artifact == null) {
    return GroupMediaIosBackgroundRecoveryValidation(failures);
  }
  _exactKeys(
    artifact,
    const <String>{
      'schema',
      'run_id',
      'scenario',
      'prepared_artifact',
      'cleanup',
      'device_roles',
      'xctest',
      'phase_a',
      'phase_b',
      'boundary_observations',
      'flow_events',
    },
    r'$',
    failures,
  );
  _expect(
    artifact,
    'schema',
    groupMediaIosBackgroundRecoveryArtifactSchema,
    r'$',
    failures,
  );
  final runId = artifact['run_id'];
  if (runId is! String || !_safeRunIdPattern.hasMatch(runId)) {
    failures.add(r'$.run_id must be a safe non-empty run identifier');
  }
  _expect(
    artifact,
    'scenario',
    groupMediaIosReceiverBackgroundRecoveryScenario,
    r'$',
    failures,
  );
  _validatePreparedArtifact(artifact['prepared_artifact'], failures);
  _validateCleanup(artifact['cleanup'], failures);
  final receiverDigest = _validateDeviceRoles(
    artifact['device_roles'],
    failures,
  );
  _validateXctest(artifact['xctest'], failures);
  _validatePhaseA(artifact['phase_a'], failures);
  _validatePhaseB(artifact['phase_b'], failures);
  _validateBoundaryObservations(
    artifact['boundary_observations'],
    runId: runId is String ? runId : null,
    receiverDigest: receiverDigest,
    failures: failures,
  );
  final events = artifact['flow_events'];
  if (events is! List ||
      events.length != groupMediaIosBackgroundRecoveryFlowEvents.length ||
      !_sameList(events, groupMediaIosBackgroundRecoveryFlowEvents)) {
    failures.add(r'$.flow_events must be the exact ordered iOS boundary trace');
  }
  return GroupMediaIosBackgroundRecoveryValidation(failures);
}

void _validateCleanup(Object? value, List<String> failures) {
  const path = r'$.cleanup';
  final cleanup = _object(value, path, failures);
  if (cleanup == null) return;
  _exactKeys(
    cleanup,
    const <String>{
      'pre_reset',
      'post_reset',
      'android_senders',
      'uninstall_commands',
      'app_left_installed',
    },
    path,
    failures,
  );
  _expect(cleanup, 'uninstall_commands', 0, path, failures);
  _expect(cleanup, 'app_left_installed', true, path, failures);
  final pre = _validateResetFacts(
    cleanup['pre_reset'],
    expectedPhase: 'pre',
    path: '$path.pre_reset',
    failures: failures,
  );
  final post = _validateResetFacts(
    cleanup['post_reset'],
    expectedPhase: 'post',
    path: '$path.post_reset',
    failures: failures,
  );
  if (pre != null && post != null && pre == post) {
    failures.add('$path must bind distinct pre/post reset receipts');
  }
  _validateAndroidCleanup(cleanup['android_senders'], failures);
}

void _validateAndroidCleanup(Object? value, List<String> failures) {
  const path = r'$.cleanup.android_senders';
  final senders = _object(value, path, failures);
  if (senders == null) return;
  _exactKeys(senders, _androidResetActions.toSet(), path, failures);
  final receiptDigests = <String>[];
  for (final action in _androidResetActions) {
    final actionPath = '$path.$action';
    final facts = _object(senders[action], actionPath, failures);
    if (facts == null) continue;
    _exactKeys(
      facts,
      const <String>{
        'pre_reset',
        'post_reset',
        'uninstall_commands',
        'pm_clear_commands',
        'broad_delete_commands',
        'app_left_installed',
      },
      actionPath,
      failures,
    );
    _expect(facts, 'uninstall_commands', 0, actionPath, failures);
    _expect(facts, 'pm_clear_commands', 0, actionPath, failures);
    _expect(facts, 'broad_delete_commands', 0, actionPath, failures);
    _expect(facts, 'app_left_installed', true, actionPath, failures);
    final pre = _validateResetFacts(
      facts['pre_reset'],
      expectedPhase: 'pre',
      path: '$actionPath.pre_reset',
      failures: failures,
    );
    final post = _validateResetFacts(
      facts['post_reset'],
      expectedPhase: 'post',
      path: '$actionPath.post_reset',
      failures: failures,
    );
    if (pre != null) receiptDigests.add(pre);
    if (post != null) receiptDigests.add(post);
    if (pre != null && post != null && pre == post) {
      failures.add('$actionPath must bind distinct pre/post reset receipts');
    }
  }
  if (receiptDigests.length == _androidResetActions.length * 2 &&
      receiptDigests.toSet().length != receiptDigests.length) {
    failures.add('$path must bind four globally distinct reset receipts');
  }
}

String? _validateResetFacts(
  Object? value, {
  required String expectedPhase,
  required String path,
  required List<String> failures,
}) {
  final reset = _object(value, path, failures);
  if (reset == null) return null;
  _exactKeys(
    reset,
    const <String>{
      'phase',
      'receipt_sha256',
      'keychain_empty',
      'database_absent',
      'allowlisted_files_absent',
    },
    path,
    failures,
  );
  _expect(reset, 'phase', expectedPhase, path, failures);
  _expect(reset, 'keychain_empty', true, path, failures);
  _expect(reset, 'database_absent', true, path, failures);
  _expect(reset, 'allowlisted_files_absent', true, path, failures);
  return _digest(reset['receipt_sha256'], '$path.receipt_sha256', failures);
}

void _validatePreparedArtifact(Object? value, List<String> failures) {
  const path = r'$.prepared_artifact';
  final artifact = _object(value, path, failures);
  if (artifact == null) return;
  _exactKeys(
    artifact,
    const <String>{
      'profile',
      'bundle_sha256',
      'android_profile',
      'android_sha256',
      'android_package',
      'child_builds',
    },
    path,
    failures,
  );
  _expect(
    artifact,
    'profile',
    groupMediaReliabilityIosBuildProfile,
    path,
    failures,
  );
  _digest(artifact['bundle_sha256'], '$path.bundle_sha256', failures);
  _expect(
    artifact,
    'android_profile',
    groupMediaReliabilityAndroidBuildProfile,
    path,
    failures,
  );
  _digest(artifact['android_sha256'], '$path.android_sha256', failures);
  _expect(
    artifact,
    'android_package',
    groupMediaReliabilityAndroidPackageName,
    path,
    failures,
  );
  _expect(artifact, 'child_builds', 0, path, failures);
}

String? _validateDeviceRoles(Object? value, List<String> failures) {
  const path = r'$.device_roles';
  final roles = _object(value, path, failures);
  if (roles == null) return null;
  _exactKeys(roles, const <String>{'sender', 'receiver'}, path, failures);
  String? senderDigest;
  String? receiverDigest;
  for (final role in const <String>['sender', 'receiver']) {
    final rolePath = '$path.$role';
    final binding = _object(roles[role], rolePath, failures);
    if (binding == null) continue;
    _exactKeys(
      binding,
      const <String>{'platform', 'kind', 'device_sha256'},
      rolePath,
      failures,
    );
    _expect(
      binding,
      'platform',
      role == 'sender' ? 'android' : 'ios',
      rolePath,
      failures,
    );
    _expect(binding, 'kind', 'physical', rolePath, failures);
    final digest = _digest(
      binding['device_sha256'],
      '$rolePath.device_sha256',
      failures,
    );
    if (role == 'sender') {
      senderDigest = digest;
    } else {
      receiverDigest = digest;
    }
  }
  if (senderDigest != null && senderDigest == receiverDigest) {
    failures.add('$path must bind two distinct physical devices');
  }
  return receiverDigest;
}

void _validateXctest(Object? value, List<String> failures) {
  const path = r'$.xctest';
  final xctest = _object(value, path, failures);
  if (xctest == null) return;
  _exactKeys(
    xctest,
    const <String>{
      'selector',
      'invocations',
      'home_presses',
      'manual_steps',
      'sleep_only_waits',
      'local_network_permission',
      'result',
    },
    path,
    failures,
  );
  _expect(
    xctest,
    'selector',
    groupMediaIosBackgroundRecoveryXctestSelector,
    path,
    failures,
  );
  _expect(xctest, 'invocations', 1, path, failures);
  _expect(xctest, 'home_presses', 2, path, failures);
  _expect(xctest, 'manual_steps', 0, path, failures);
  _expect(xctest, 'sleep_only_waits', 0, path, failures);
  _expect(
    xctest,
    'local_network_permission',
    'automated_or_pregranted',
    path,
    failures,
  );
  _expect(xctest, 'result', 'passed', path, failures);
}

void _validatePhaseA(Object? value, List<String> failures) {
  const path = r'$.phase_a';
  final phase = _object(value, path, failures);
  if (phase == null) return;
  _exactKeys(
    phase,
    const <String>{
      'critical_task_granted',
      'terminal_path',
      'native_end_count',
      'durable_status',
      'download_attempts',
      'ui_effects',
    },
    path,
    failures,
  );
  _expect(phase, 'critical_task_granted', true, path, failures);
  _expect(phase, 'terminal_path', 'normal', path, failures);
  _expect(phase, 'native_end_count', 1, path, failures);
  _expect(phase, 'durable_status', 'done', path, failures);
  _expect(phase, 'download_attempts', 1, path, failures);
  _expect(phase, 'ui_effects', 1, path, failures);
}

void _validatePhaseB(Object? value, List<String> failures) {
  const path = r'$.phase_b';
  final phase = _object(value, path, failures);
  if (phase == null) return;
  _exactKeys(
    phase,
    const <String>{
      'critical_task_granted',
      'barrier',
      'pre_interrupt_status',
      'host_terminations',
      'terminal_path',
      'native_end_count',
      'relaunch_route',
      'resume_after_drain_attempts',
      'durable_status',
      'download_attempts',
      'ui_effects',
      'fresh_pid',
    },
    path,
    failures,
  );
  _expect(phase, 'critical_task_granted', true, path, failures);
  _expect(phase, 'barrier', 'durable_post_claim_pre_commit', path, failures);
  _expect(phase, 'pre_interrupt_status', 'downloading', path, failures);
  _expect(phase, 'host_terminations', 1, path, failures);
  _expect(phase, 'terminal_path', 'interrupted', path, failures);
  _expect(phase, 'native_end_count', 0, path, failures);
  _expect(phase, 'relaunch_route', 'root_without_group', path, failures);
  _expect(phase, 'resume_after_drain_attempts', 1, path, failures);
  _expect(phase, 'durable_status', 'done', path, failures);
  _expect(phase, 'download_attempts', 2, path, failures);
  _expect(phase, 'ui_effects', 1, path, failures);
  _expect(phase, 'fresh_pid', true, path, failures);
}

void _validateBoundaryObservations(
  Object? value, {
  required String? runId,
  required String? receiverDigest,
  required List<String> failures,
}) {
  const path = r'$.boundary_observations';
  final observations = _object(value, path, failures);
  if (observations == null) return;
  const phases = <String>['phase_a', 'phase_b_claim', 'phase_b_recovery'];
  _exactKeys(
    observations,
    <String>{...phases, 'database_path_sha256'},
    path,
    failures,
  );
  final databasePathDigest = _digest(
    observations['database_path_sha256'],
    '$path.database_path_sha256',
    failures,
  );
  final allDigests = <String>{};
  for (final phase in phases) {
    final phasePath = '$path.$phase';
    final digests = _validateObservationPair(
      observations[phase],
      phase: phase,
      path: phasePath,
      runId: runId,
      receiverDigest: receiverDigest,
      expectedDatabasePathDigest: databasePathDigest,
      failures: failures,
    );
    allDigests.addAll(digests);
  }
  if (allDigests.length != 6) {
    failures.add('$path must contain six distinct independently bound records');
  }
}

Set<String> _validateObservationPair(
  Object? value, {
  required String phase,
  required String path,
  required String? runId,
  required String? receiverDigest,
  String? expectedDatabasePathDigest,
  required List<String> failures,
}) {
  final digests = <String>{};
  final pair = _object(value, path, failures);
  if (pair == null) return digests;
  _exactKeys(
    pair,
    const <String>{'native', 'database', 'native_sha256', 'database_sha256'},
    path,
    failures,
  );
  final expectedPhase = switch (phase) {
    'phase_a' => 'a',
    'phase_b_claim' => 'b_claim',
    _ => 'b_recovery',
  };
  final native = _object(pair['native'], '$path.native', failures);
  final database = _object(pair['database'], '$path.database', failures);
  if (native != null) {
    _validateNativeObservation(
      native,
      path: '$path.native',
      expectedPhase: expectedPhase,
      runId: runId,
      receiverDigest: receiverDigest,
      failures: failures,
    );
    final expectedDigest = groupMediaIosObservationDigest(native);
    _expect(pair, 'native_sha256', expectedDigest, path, failures);
    digests.add(expectedDigest);
  }
  if (database != null) {
    _validateDatabaseObservation(
      database,
      path: '$path.database',
      expectedPhase: expectedPhase,
      runId: runId,
      receiverDigest: receiverDigest,
      failures: failures,
    );
    if (expectedDatabasePathDigest != null) {
      _expect(
        database,
        'database_path_sha256',
        expectedDatabasePathDigest,
        '$path.database',
        failures,
      );
    }
    final expectedDigest = groupMediaIosObservationDigest(database);
    _expect(pair, 'database_sha256', expectedDigest, path, failures);
    digests.add(expectedDigest);
  }
  _digest(pair['native_sha256'], '$path.native_sha256', failures);
  _digest(pair['database_sha256'], '$path.database_sha256', failures);
  if (digests.length != 2) {
    failures.add('$path must bind two distinct observation records');
  }
  return digests;
}

void _validateNativeObservation(
  Map<String, Object?> value, {
  required String path,
  required String expectedPhase,
  required String? runId,
  required String? receiverDigest,
  required List<String> failures,
}) {
  _exactKeys(
    value,
    const <String>{
      'schema',
      'run_id',
      'phase',
      'source',
      'receiver_device_sha256',
      'home_observed',
      'critical_task_granted',
      'terminal_path',
      'native_end_count',
      'receiver_pid',
      'host_kill_observed',
    },
    path,
    failures,
  );
  _expect(
    value,
    'schema',
    groupMediaIosNativeObservationSchema,
    path,
    failures,
  );
  if (runId != null) _expect(value, 'run_id', runId, path, failures);
  _expect(value, 'phase', expectedPhase, path, failures);
  _expect(value, 'source', 'physical_idevicesyslog', path, failures);
  if (receiverDigest != null) {
    _expect(value, 'receiver_device_sha256', receiverDigest, path, failures);
  }
  _expect(value, 'home_observed', true, path, failures);
  _expect(value, 'critical_task_granted', true, path, failures);
  final expectedTerminal = switch (expectedPhase) {
    'a' => 'normal',
    'b_claim' => 'none',
    _ => 'interrupted',
  };
  _expect(value, 'terminal_path', expectedTerminal, path, failures);
  _expect(
    value,
    'native_end_count',
    expectedPhase == 'a' ? 1 : 0,
    path,
    failures,
  );
  _expect(
    value,
    'host_kill_observed',
    expectedPhase == 'b_recovery',
    path,
    failures,
  );
  final pid = value['receiver_pid'];
  if (pid is! int || pid <= 0) {
    failures.add('$path.receiver_pid must be a positive observed PID');
  }
}

void _validateDatabaseObservation(
  Map<String, Object?> value, {
  required String path,
  required String expectedPhase,
  required String? runId,
  required String? receiverDigest,
  required List<String> failures,
}) {
  _exactKeys(
    value,
    const <String>{
      'schema',
      'run_id',
      'phase',
      'source',
      'receiver_device_sha256',
      'parent_message_sha256',
      'ui_effect_sha256',
      'database_path_sha256',
      'database_reopened',
      'cipher_version',
      'user_version',
      'barrier',
      'durable_status',
      'download_attempts',
      'resume_after_drain_attempts',
    },
    path,
    failures,
  );
  _expect(
    value,
    'schema',
    groupMediaIosDatabaseObservationSchema,
    path,
    failures,
  );
  if (runId != null) _expect(value, 'run_id', runId, path, failures);
  _expect(value, 'phase', expectedPhase, path, failures);
  _expect(value, 'source', 'production_sqlcipher', path, failures);
  if (receiverDigest != null) {
    _expect(value, 'receiver_device_sha256', receiverDigest, path, failures);
  }
  _digest(
    value['parent_message_sha256'],
    '$path.parent_message_sha256',
    failures,
  );
  _digest(value['ui_effect_sha256'], '$path.ui_effect_sha256', failures);
  _digest(
    value['database_path_sha256'],
    '$path.database_path_sha256',
    failures,
  );
  if (runId != null) {
    final mediaPhase = expectedPhase == 'a' ? 'A' : 'B';
    _expect(
      value,
      'parent_message_sha256',
      _textDigest('P269-PARENT-$mediaPhase-$runId'),
      path,
      failures,
    );
    _expect(
      value,
      'ui_effect_sha256',
      _textDigest('P269-$mediaPhase-$runId'),
      path,
      failures,
    );
  }
  _expect(value, 'database_reopened', true, path, failures);
  final cipherVersion = value['cipher_version'];
  if (cipherVersion is! String ||
      !RegExp(r'^SQLCipher [0-9]+\.[0-9]+\.[0-9]+$').hasMatch(cipherVersion)) {
    failures.add(
      '$path.cipher_version must report a concrete SQLCipher version',
    );
  }
  _expect(
    value,
    'user_version',
    currentIdentityDatabaseVersion,
    path,
    failures,
  );
  final expectedBarrier = switch (expectedPhase) {
    'a' => 'background_receive_started',
    'b_claim' => 'durable_post_claim_pre_commit',
    _ => 'resume_after_first_group_inbox_drain',
  };
  final expectedStatus = expectedPhase == 'b_claim' ? 'downloading' : 'done';
  _expect(value, 'barrier', expectedBarrier, path, failures);
  _expect(value, 'durable_status', expectedStatus, path, failures);
  _expect(
    value,
    'download_attempts',
    expectedPhase == 'b_recovery' ? 2 : 1,
    path,
    failures,
  );
  _expect(
    value,
    'resume_after_drain_attempts',
    expectedPhase == 'b_recovery' ? 1 : 0,
    path,
    failures,
  );
}

String groupMediaIosObservationDigest(Object? value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

String _textDigest(String value) =>
    sha256.convert(utf8.encode(value)).toString();

Object? _canonical(Object? value) {
  if (value is List) {
    return value.map<Object?>(_canonical).toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  return value;
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
  if (!_sameSet(actual, expected)) {
    failures.add('$path has an unexpected key set');
  }
}

void _expect(
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

String? _digest(Object? value, String path, List<String> failures) {
  if (value is! String || !_sha256Pattern.hasMatch(value)) {
    failures.add('$path must be a lowercase SHA-256 digest');
    return null;
  }
  return value;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

bool _sameList(List<Object?> left, List<String> right) {
  for (var index = 0; index < right.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
