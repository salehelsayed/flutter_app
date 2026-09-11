import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';

const String groupMediaDistinctAuthorityMode = 'distinctAccountAndTransport';
const String groupMediaAccountBoundAuthorityMode = 'accountBoundLegacy';

bool groupMediaAuthorityModeIsValid(String mode) =>
    mode == groupMediaDistinctAuthorityMode ||
    mode == groupMediaAccountBoundAuthorityMode;

bool groupMediaRoleIdentityMatches(
  String mode,
  String account,
  String transport,
) =>
    groupMediaAuthorityModeIsValid(mode) &&
    account.isNotEmpty &&
    account.trim() == account &&
    transport.isNotEmpty &&
    transport.trim() == transport &&
    (mode == groupMediaAccountBoundAuthorityMode
        ? account == transport
        : account != transport);

const String groupMediaReliabilityArtifactSchema =
    'mknoon.group-media-reliability.v1';
const String groupMediaReliabilityAndroidBuildProfile =
    groupMediaAndroidDisposableBuildProfile;
const String groupMediaReliabilityAndroidPackageName =
    groupMediaAndroidDisposablePackageId;
const String groupMediaReliabilityIosBuildProfile =
    groupMediaIosDisposableBuildProfile;
const String groupMediaReliabilityArtifactValidatorId =
    'validateGroupMediaReliabilityArtifact';

const String groupMediaForegroundRetryAclRoundtripScenario =
    'group_media_foreground_retry_acl_roundtrip';
const String groupMediaIosReceiverBackgroundRecoveryScenario =
    'group_media_ios_receiver_background_recovery';

const List<String> groupMediaReliabilityScenarioIds = <String>[
  groupMediaForegroundRetryAclRoundtripScenario,
  groupMediaIosReceiverBackgroundRecoveryScenario,
];

const Set<String> _artifactKeys = <String>{
  'schema',
  'run_id',
  'scenario',
  'prepared_artifact',
  'device_roles',
  'identity_fingerprints',
  'account_vs_transport_discriminator',
  'acl_entries',
  'media',
  'role_databases',
  'retry_passes',
  'cleanup',
  'flow_events',
};
const Set<String> _mediaKinds = <String>{'jpeg', 'mp4', 'voice'};
const List<String> _requiredFlowEvents = <String>[
  'sender_uploads_settled',
  'sender_publications_settled',
  'receiver_jpeg_post_claim_pre_commit',
  'receiver_process_force_stopped',
  'receiver_process_relaunched',
  'receiver_prior_status_read',
  'receiver_downloads_settled',
  'receiver_media_rendered',
  'second_retry_pass_zero',
];
const List<String> _requiredFlowRoles = <String>[
  'sender',
  'sender',
  'receiver',
  'host',
  'host',
  'receiver',
  'receiver',
  'receiver',
  'host',
];

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _safeIdentifierPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$',
);
final RegExp _safeFlowEventPattern = RegExp(r'^[a-z][a-z0-9_.-]{0,95}$');
final RegExp _safeFactKeyPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');
final RegExp _sensitiveFactKeyPattern = RegExp(
  r'(raw|peer_id|token|secret|private_key|media_bytes|db_path|absolute_path)',
);

final class GroupMediaReliabilityValidation {
  GroupMediaReliabilityValidation(List<String> failures)
    : failures = List<String>.unmodifiable(failures);

  final List<String> failures;

  bool get ok => failures.isEmpty;

  String get detail => ok ? 'accepted' : failures.join('; ');
}

/// Validates the non-circular Plan 269 device artifact.
///
/// The artifact keeps only run-scoped hashes and sanitized relative database
/// paths. It deliberately cannot carry peer IDs, credentials, media bytes, or
/// user-specific absolute database paths.
GroupMediaReliabilityValidation validateGroupMediaReliabilityArtifact(
  Object? value,
) {
  final failures = <String>[];
  final artifact = _object(value, r'$', failures);
  if (artifact == null) return GroupMediaReliabilityValidation(failures);

  _expectExactKeys(
    artifact,
    <String>{
      ..._artifactKeys,
      if (artifact.containsKey('authority_mode')) 'authority_mode',
    },
    r'$',
    failures,
  );
  final rawMode = artifact.containsKey('authority_mode')
      ? artifact['authority_mode']
      : groupMediaDistinctAuthorityMode;
  final authorityMode = rawMode is String ? rawMode : '';
  if (!groupMediaAuthorityModeIsValid(authorityMode)) {
    failures.add(
      r'$.authority_mode must name an exact supported authority mode',
    );
  }
  _expectValue(
    artifact,
    'schema',
    groupMediaReliabilityArtifactSchema,
    r'$',
    failures,
  );
  final runId = _requiredSafeIdentifier(artifact, 'run_id', r'$', failures);
  _expectValue(
    artifact,
    'scenario',
    groupMediaForegroundRetryAclRoundtripScenario,
    r'$',
    failures,
  );

  _validatePreparedArtifact(artifact['prepared_artifact'], failures);
  final deviceDigests = _validateDeviceRoles(
    artifact['device_roles'],
    failures,
  );
  final identityDigests = _validateIdentityFingerprints(
    artifact['identity_fingerprints'],
    failures,
    authorityMode,
  );
  for (final role in const <String>['sender', 'receiver']) {
    final activeDevice = deviceDigests[role];
    final activeTransport = identityDigests[role]?['transport'];
    if (activeDevice != null &&
        activeTransport != null &&
        activeDevice != activeTransport) {
      failures.add(
        r'$.device_roles.'
        '$role.device_sha256 must match the active transport fingerprint',
      );
    }
  }
  _validateDiscriminator(
    artifact['account_vs_transport_discriminator'],
    identityDigests,
    failures,
    authorityMode,
  );
  _validateAcl(artifact['acl_entries'], identityDigests, failures);
  _validateMedia(artifact['media'], failures);
  _validateRoleDatabases(artifact['role_databases'], runId, failures);
  _validateRetryPasses(artifact['retry_passes'], failures);
  _validateCleanup(
    artifact['cleanup'],
    artifact['prepared_artifact'],
    failures,
  );
  _validateFlowEvents(artifact['flow_events'], failures);

  final senderDevice = deviceDigests['sender'];
  final receiverDevice = deviceDigests['receiver'];
  if (senderDevice != null && senderDevice == receiverDevice) {
    failures.add(r'$.device_roles must bind two distinct devices');
  }

  return GroupMediaReliabilityValidation(failures);
}

void _validatePreparedArtifact(Object? value, List<String> failures) {
  const path = r'$.prepared_artifact';
  final artifact = _object(value, path, failures);
  if (artifact == null) return;
  _expectExactKeys(
    artifact,
    const <String>{'profile', 'application_id', 'sha256', 'child_builds'},
    path,
    failures,
  );
  _expectValue(
    artifact,
    'profile',
    groupMediaReliabilityAndroidBuildProfile,
    path,
    failures,
  );
  _expectValue(
    artifact,
    'application_id',
    groupMediaReliabilityAndroidPackageName,
    path,
    failures,
  );
  _requiredDigest(artifact, 'sha256', path, failures);
  _expectValue(artifact, 'child_builds', 0, path, failures);
}

Map<String, String> _validateDeviceRoles(Object? value, List<String> failures) {
  const path = r'$.device_roles';
  final roles = _object(value, path, failures);
  final result = <String, String>{};
  if (roles == null) return result;
  _expectExactKeys(roles, const <String>{'sender', 'receiver'}, path, failures);

  for (final role in const <String>['sender', 'receiver']) {
    final rolePath = '$path.$role';
    final binding = _object(roles[role], rolePath, failures);
    if (binding == null) continue;
    _expectExactKeys(
      binding,
      const <String>{'platform', 'kind', 'device_sha256'},
      rolePath,
      failures,
    );
    _expectValue(binding, 'platform', 'android', rolePath, failures);
    _expectValue(
      binding,
      'kind',
      role == 'sender' ? 'physical' : 'emulator',
      rolePath,
      failures,
    );
    final digest = _requiredDigest(
      binding,
      'device_sha256',
      rolePath,
      failures,
    );
    if (digest != null) result[role] = digest;
  }
  return result;
}

Map<String, Map<String, String>> _validateIdentityFingerprints(
  Object? value,
  List<String> failures,
  String authorityMode,
) {
  const path = r'$.identity_fingerprints';
  final identities = _object(value, path, failures);
  final result = <String, Map<String, String>>{};
  if (identities == null) return result;
  _expectExactKeys(
    identities,
    const <String>{'sender', 'receiver'},
    path,
    failures,
  );

  final allDigests = <String>{};
  for (final role in const <String>['sender', 'receiver']) {
    final rolePath = '$path.$role';
    final identity = _object(identities[role], rolePath, failures);
    if (identity == null) continue;
    _expectExactKeys(
      identity,
      const <String>{'account_sha256', 'transport_sha256'},
      rolePath,
      failures,
    );
    final account = _requiredDigest(
      identity,
      'account_sha256',
      rolePath,
      failures,
    );
    final transport = _requiredDigest(
      identity,
      'transport_sha256',
      rolePath,
      failures,
    );
    if (account != null && transport != null) {
      if (!groupMediaRoleIdentityMatches(authorityMode, account, transport)) {
        failures.add(
          '$rolePath must match the declared account/transport authority mode',
        );
      }
      result[role] = <String, String>{
        'account': account,
        'transport': transport,
      };
      if (!allDigests.add(account) ||
          (authorityMode == groupMediaDistinctAuthorityMode &&
              !allDigests.add(transport))) {
        failures.add('$path fingerprints must be unique across both roles');
      }
    }
  }
  return result;
}

void _validateDiscriminator(
  Object? value,
  Map<String, Map<String, String>> identities,
  List<String> failures,
  String authorityMode,
) {
  const path = r'$.account_vs_transport_discriminator';
  final discriminator = _object(value, path, failures);
  if (discriminator == null) return;
  _expectExactKeys(
    discriminator,
    const <String>{'sender', 'receiver'},
    path,
    failures,
  );
  for (final role in const <String>['sender', 'receiver']) {
    _expectValue(
      discriminator,
      role,
      authorityMode == groupMediaDistinctAuthorityMode,
      path,
      failures,
    );
    final identity = identities[role];
    if (identity != null &&
        !groupMediaRoleIdentityMatches(
          authorityMode,
          identity['account']!,
          identity['transport']!,
        )) {
      failures.add('$path.$role contradicts the identity fingerprints');
    }
  }
}

void _validateAcl(
  Object? value,
  Map<String, Map<String, String>> identities,
  List<String> failures,
) {
  const path = r'$.acl_entries';
  if (value is! List) {
    failures.add('$path must be an array');
    return;
  }
  if (value.length != 2) {
    failures.add('$path must contain exactly both active transport hashes');
    return;
  }
  final entries = <String>{};
  for (final entry in value) {
    if (entry is! String || !_sha256Pattern.hasMatch(entry)) {
      failures.add('$path must contain only lowercase SHA-256 fingerprints');
      return;
    }
    entries.add(entry);
  }
  final expected = <String>{};
  final senderTransport = identities['sender']?['transport'];
  final receiverTransport = identities['receiver']?['transport'];
  if (senderTransport != null) expected.add(senderTransport);
  if (receiverTransport != null) expected.add(receiverTransport);
  if (entries.length != 2 ||
      expected.length == 2 && !entries.containsAll(expected)) {
    failures.add('$path does not match both active transports');
  }
}

void _validateMedia(Object? value, List<String> failures) {
  const path = r'$.media';
  final media = _object(value, path, failures);
  if (media == null) return;
  _expectExactKeys(
    media,
    const <String>{
      'uploads_per_blob',
      'publications_per_message',
      'download_attempts',
      'rendered_surfaces',
    },
    path,
    failures,
  );
  _validateExactKindCounts(
    media['uploads_per_blob'],
    '$path.uploads_per_blob',
    const <String, int>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    failures,
  );
  _validateExactKindCounts(
    media['publications_per_message'],
    '$path.publications_per_message',
    const <String, int>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    failures,
  );
  _validateExactKindCounts(
    media['download_attempts'],
    '$path.download_attempts',
    const <String, int>{'jpeg': 2, 'mp4': 1, 'voice': 1},
    failures,
  );
  _validateExactKindCounts(
    media['rendered_surfaces'],
    '$path.rendered_surfaces',
    const <String, int>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    failures,
  );
}

void _validateExactKindCounts(
  Object? value,
  String path,
  Map<String, int> expected,
  List<String> failures,
) {
  final counts = _object(value, path, failures);
  if (counts == null) return;
  _expectExactKeys(counts, _mediaKinds, path, failures);
  for (final entry in expected.entries) {
    _expectValue(counts, entry.key, entry.value, path, failures);
  }
}

void _validateRoleDatabases(
  Object? value,
  String? runId,
  List<String> failures,
) {
  const path = r'$.role_databases';
  final databases = _object(value, path, failures);
  if (databases == null) return;
  _expectExactKeys(
    databases,
    const <String>{'sender', 'receiver'},
    path,
    failures,
  );

  final roleRows = <String, List<Map<String, Object?>>>{};
  final roleDatabasePathDigests = <String, String>{};
  for (final role in const <String>['sender', 'receiver']) {
    final rolePath = '$path.$role';
    final database = _object(databases[role], rolePath, failures);
    if (database == null) continue;
    _expectExactKeys(
      database,
      const <String>{
        'role_db_path',
        'database_path_sha256',
        'cipher_version',
        'user_version',
        'reopened',
        'rows',
      },
      rolePath,
      failures,
    );
    final databasePathDigest = _requiredDigest(
      database,
      'database_path_sha256',
      rolePath,
      failures,
    );
    if (databasePathDigest != null) {
      roleDatabasePathDigests[role] = databasePathDigest;
    }
    _validateRoleDatabasePath(
      database['role_db_path'],
      role,
      rolePath,
      failures,
    );
    final cipherVersion = database['cipher_version'];
    if (cipherVersion is! String ||
        cipherVersion.trim().isEmpty ||
        cipherVersion.length > 96 ||
        cipherVersion.contains(RegExp(r'[\r\n]'))) {
      failures.add('$rolePath.cipher_version must be a safe non-empty string');
    }
    _expectValue(
      database,
      'user_version',
      currentIdentityDatabaseVersion,
      rolePath,
      failures,
    );
    _expectValue(database, 'reopened', true, rolePath, failures);
    roleRows[role] = _validateDatabaseRows(
      database['rows'],
      rolePath,
      runId,
      failures,
    );
  }

  final sender = roleRows['sender'];
  final receiver = roleRows['receiver'];
  if (roleDatabasePathDigests['sender'] != null &&
      roleDatabasePathDigests['sender'] ==
          roleDatabasePathDigests['receiver']) {
    failures.add('$path must bind distinct sender and receiver databases');
  }
  if (sender != null && receiver != null && sender.length == receiver.length) {
    for (var index = 0; index < sender.length; index += 1) {
      for (final key in const <String>['media_kind', 'message_id', 'blob_id']) {
        if (sender[index][key] != receiver[index][key]) {
          failures.add(
            '$path sender/receiver row $index must bind the same $key',
          );
        }
      }
    }
  }
}

void _validateRoleDatabasePath(
  Object? value,
  String role,
  String parentPath,
  List<String> failures,
) {
  if (value is! String ||
      value.trim().isEmpty ||
      !RegExp('^$role/[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\$').hasMatch(value)) {
    failures.add(
      '$parentPath.role_db_path must be a sanitized $role-relative path',
    );
  }
}

List<Map<String, Object?>> _validateDatabaseRows(
  Object? value,
  String parentPath,
  String? runId,
  List<String> failures,
) {
  final path = '$parentPath.rows';
  if (value is! List || value.length != _mediaKinds.length) {
    failures.add('$path must contain exactly jpeg, mp4, and voice rows');
    return const <Map<String, Object?>>[];
  }
  final rows = <Map<String, Object?>>[];
  const kinds = <String>['jpeg', 'mp4', 'voice'];
  for (var index = 0; index < value.length; index += 1) {
    final rowPath = '$path[$index]';
    final row = _object(value[index], rowPath, failures);
    if (row == null) continue;
    rows.add(row);
    _expectExactKeys(
      row,
      const <String>{
        'run_id',
        'media_kind',
        'message_id',
        'blob_id',
        'status',
        'upload_retry_count',
        'download_retry_count',
      },
      rowPath,
      failures,
    );
    if (runId != null) _expectValue(row, 'run_id', runId, rowPath, failures);
    _expectValue(row, 'media_kind', kinds[index], rowPath, failures);
    _requiredSafeIdentifier(row, 'message_id', rowPath, failures);
    _requiredSafeIdentifier(row, 'blob_id', rowPath, failures);
    _expectValue(row, 'status', 'done', rowPath, failures);
    _expectValue(row, 'upload_retry_count', 0, rowPath, failures);
    _expectValue(row, 'download_retry_count', 0, rowPath, failures);
  }
  final messageIds = rows
      .map((row) => row['message_id'])
      .whereType<String>()
      .toList(growable: false);
  if (messageIds.length == kinds.length &&
      messageIds.toSet().length != kinds.length) {
    failures.add('$path must bind three distinct message_id values');
  }
  final blobIds = rows
      .map((row) => row['blob_id'])
      .whereType<String>()
      .toList(growable: false);
  if (blobIds.length == kinds.length &&
      blobIds.toSet().length != kinds.length) {
    failures.add('$path must bind three distinct blob_id values');
  }
  return rows;
}

void _validateRetryPasses(Object? value, List<String> failures) {
  const path = r'$.retry_passes';
  final retryPasses = _object(value, path, failures);
  if (retryPasses == null) return;
  _expectExactKeys(
    retryPasses,
    const <String>{'second_upload_work', 'second_download_work'},
    path,
    failures,
  );
  _expectValue(retryPasses, 'second_upload_work', 0, path, failures);
  _expectValue(retryPasses, 'second_download_work', 0, path, failures);
}

void _validateCleanup(
  Object? value,
  Object? preparedArtifactValue,
  List<String> failures,
) {
  const path = r'$.cleanup';
  final cleanup = _object(value, path, failures);
  if (cleanup == null) return;
  _expectExactKeys(
    cleanup,
    const <String>{
      'application_id',
      'artifact_sha256',
      'sender',
      'receiver',
      'receipts_distinct',
      'app_left_installed',
      'production_package_commands',
      'uninstall_commands',
      'pm_clear_commands',
      'broad_delete_commands',
    },
    path,
    failures,
  );
  _expectValue(
    cleanup,
    'application_id',
    groupMediaReliabilityAndroidPackageName,
    path,
    failures,
  );
  final artifactDigest = _requiredDigest(
    cleanup,
    'artifact_sha256',
    path,
    failures,
  );
  final preparedArtifact = _object(
    preparedArtifactValue,
    r'$.prepared_artifact',
    failures,
  );
  if (artifactDigest != null &&
      preparedArtifact != null &&
      artifactDigest != preparedArtifact['sha256']) {
    failures.add(
      r'$.cleanup.artifact_sha256 must match $.prepared_artifact.sha256',
    );
  }

  final receiptDigests = <String>[];
  for (final role in const <String>['sender', 'receiver']) {
    final rolePath = '$path.$role';
    final roleCleanup = _object(cleanup[role], rolePath, failures);
    if (roleCleanup == null) continue;
    _expectExactKeys(
      roleCleanup,
      const <String>{'pre_reset', 'post_reset'},
      rolePath,
      failures,
    );
    final preDigest = _validateResetReceipt(
      roleCleanup['pre_reset'],
      rolePath,
      expectedPhase: 'pre',
      failures: failures,
    );
    final postDigest = _validateResetReceipt(
      roleCleanup['post_reset'],
      rolePath,
      expectedPhase: 'post',
      failures: failures,
    );
    if (preDigest != null) receiptDigests.add(preDigest);
    if (postDigest != null) receiptDigests.add(postDigest);
    if (preDigest != null && preDigest == postDigest) {
      failures.add('$rolePath must bind distinct pre/post reset receipts');
    }
  }
  _expectValue(cleanup, 'receipts_distinct', true, path, failures);
  if (receiptDigests.length == 4 && receiptDigests.toSet().length != 4) {
    failures.add('$path must bind four distinct reset receipts');
  }
  _expectValue(cleanup, 'app_left_installed', true, path, failures);
  _expectValue(cleanup, 'production_package_commands', 0, path, failures);
  _expectValue(cleanup, 'uninstall_commands', 0, path, failures);
  _expectValue(cleanup, 'pm_clear_commands', 0, path, failures);
  _expectValue(cleanup, 'broad_delete_commands', 0, path, failures);
}

String? _validateResetReceipt(
  Object? value,
  String parentPath, {
  required String expectedPhase,
  required List<String> failures,
}) {
  final path = '$parentPath.${expectedPhase}_reset';
  final receipt = _object(value, path, failures);
  if (receipt == null) return null;
  _expectExactKeys(
    receipt,
    const <String>{
      'phase',
      'receipt_sha256',
      'process_id_sha256',
      'profile',
      'application_id',
      'secure_storage_empty',
      'database_absent',
      'allowlisted_files_absent',
      'contains_secrets',
    },
    path,
    failures,
  );
  _expectValue(receipt, 'phase', expectedPhase, path, failures);
  final digest = _requiredDigest(receipt, 'receipt_sha256', path, failures);
  _requiredDigest(receipt, 'process_id_sha256', path, failures);
  _expectValue(
    receipt,
    'profile',
    groupMediaReliabilityAndroidBuildProfile,
    path,
    failures,
  );
  _expectValue(
    receipt,
    'application_id',
    groupMediaReliabilityAndroidPackageName,
    path,
    failures,
  );
  _expectValue(receipt, 'secure_storage_empty', true, path, failures);
  _expectValue(receipt, 'database_absent', true, path, failures);
  _expectValue(receipt, 'allowlisted_files_absent', true, path, failures);
  _expectValue(receipt, 'contains_secrets', false, path, failures);
  return digest;
}

void _validateFlowEvents(Object? value, List<String> failures) {
  const path = r'$.flow_events';
  if (value is! List || value.isEmpty) {
    failures.add('$path must be a non-empty event list');
    return;
  }
  final events = <String>[];
  final roles = <String>[];
  final factsByEvent = <String, Map<String, Object?>>{};
  for (var index = 0; index < value.length; index += 1) {
    final eventPath = '$path[$index]';
    final event = _object(value[index], eventPath, failures);
    if (event == null) continue;
    _expectExactKeys(
      event,
      const <String>{'sequence', 'name', 'role', 'facts'},
      eventPath,
      failures,
    );
    _expectValue(event, 'sequence', index + 1, eventPath, failures);
    final name = event['name'];
    if (name is! String || !_safeFlowEventPattern.hasMatch(name)) {
      failures.add('$eventPath.name must be a safe event name');
    } else {
      events.add(name);
    }
    final role = event['role'];
    if (role is! String ||
        !const <String>{'sender', 'receiver', 'host'}.contains(role)) {
      failures.add('$eventPath.role must be sender, receiver, or host');
    }
    roles.add(role is String ? role : '');
    final facts = _object(event['facts'], '$eventPath.facts', failures);
    if (facts != null) {
      if (name is String) factsByEvent[name] = facts;
      for (final entry in facts.entries) {
        if (!_safeFactKeyPattern.hasMatch(entry.key) ||
            _sensitiveFactKeyPattern.hasMatch(entry.key)) {
          failures.add('$eventPath.facts contains unsafe key ${entry.key}');
          continue;
        }
        final fact = entry.value;
        final safeString =
            fact is String &&
            fact.isNotEmpty &&
            fact.length <= 128 &&
            !fact.contains(RegExp(r'[\r\n/\\]')) &&
            !fact.startsWith('12D3Koo');
        if (fact is! bool && fact is! int && !safeString) {
          failures.add('$eventPath.facts.${entry.key} must be a safe scalar');
        }
      }
    }
  }
  if (events.toSet().length != events.length) {
    failures.add('$path must not contain duplicate events');
  }
  if (events.length != _requiredFlowEvents.length) {
    failures.add('$path must contain the exact ordered process trace');
  } else {
    for (var index = 0; index < _requiredFlowEvents.length; index++) {
      if (events[index] != _requiredFlowEvents[index]) {
        failures.add('$path must contain the exact ordered process trace');
        break;
      }
    }
  }
  if (roles.length != _requiredFlowRoles.length) {
    failures.add('$path must bind the exact ordered role trace');
  } else {
    for (var index = 0; index < _requiredFlowRoles.length; index++) {
      if (roles[index] != _requiredFlowRoles[index]) {
        failures.add('$path must bind the exact ordered role trace');
        break;
      }
    }
  }
  _validateProcessFlowEvents(factsByEvent, failures);
}

void _validateProcessFlowEvents(
  Map<String, Map<String, Object?>> factsByEvent,
  List<String> failures,
) {
  final uploads = factsByEvent['sender_uploads_settled'];
  final publications = factsByEvent['sender_publications_settled'];
  final barrier = factsByEvent['receiver_jpeg_post_claim_pre_commit'];
  final stopped = factsByEvent['receiver_process_force_stopped'];
  final relaunched = factsByEvent['receiver_process_relaunched'];
  final prior = factsByEvent['receiver_prior_status_read'];
  final downloads = factsByEvent['receiver_downloads_settled'];
  final rendered = factsByEvent['receiver_media_rendered'];
  final secondPass = factsByEvent['second_retry_pass_zero'];
  if (uploads != null) {
    const uploadsPath = r'$.flow_events[sender_uploads_settled].facts';
    _expectExactKeys(uploads, const <String>{'count'}, uploadsPath, failures);
    _expectValue(uploads, 'count', 3, uploadsPath, failures);
  }
  if (publications != null) {
    const publicationsPath =
        r'$.flow_events[sender_publications_settled].facts';
    _expectExactKeys(
      publications,
      const <String>{'count'},
      publicationsPath,
      failures,
    );
    _expectValue(publications, 'count', 3, publicationsPath, failures);
  }
  if (downloads != null) {
    const downloadsPath = r'$.flow_events[receiver_downloads_settled].facts';
    _expectExactKeys(
      downloads,
      const <String>{'settled_attachment_count', 'first_pass_work'},
      downloadsPath,
      failures,
    );
    _expectValue(
      downloads,
      'settled_attachment_count',
      3,
      downloadsPath,
      failures,
    );
    final firstPassWork = downloads['first_pass_work'];
    if (firstPassWork is! int || firstPassWork < 1 || firstPassWork > 3) {
      failures.add('$downloadsPath.first_pass_work must be between 1 and 3');
    }
  }
  if (rendered != null) {
    const renderedPath = r'$.flow_events[receiver_media_rendered].facts';
    _expectExactKeys(
      rendered,
      const <String>{
        'jpeg_decoder_frame',
        'mp4_thumbnail_frame',
        'voice_player_loaded',
      },
      renderedPath,
      failures,
    );
    _expectValue(rendered, 'jpeg_decoder_frame', true, renderedPath, failures);
    _expectValue(rendered, 'mp4_thumbnail_frame', true, renderedPath, failures);
    _expectValue(rendered, 'voice_player_loaded', true, renderedPath, failures);
  }
  if (secondPass != null) {
    const secondPassPath = r'$.flow_events[second_retry_pass_zero].facts';
    _expectExactKeys(
      secondPass,
      const <String>{'scope', 'upload_work', 'download_work'},
      secondPassPath,
      failures,
    );
    _expectValue(
      secondPass,
      'scope',
      'sender_post_render',
      secondPassPath,
      failures,
    );
    _expectValue(secondPass, 'upload_work', 0, secondPassPath, failures);
    _expectValue(secondPass, 'download_work', 0, secondPassPath, failures);
  }
  if (barrier == null ||
      stopped == null ||
      relaunched == null ||
      prior == null) {
    return;
  }

  const barrierPath =
      r'$.flow_events[receiver_jpeg_post_claim_pre_commit].facts';
  _expectExactKeys(
    barrier,
    const <String>{
      'barrier_name',
      'marker_atomic',
      'prior_status',
      'attempt',
      'old_pid_sha256',
    },
    barrierPath,
    failures,
  );
  _expectValue(
    barrier,
    'barrier_name',
    'receiver_jpeg_post_claim_pre_commit',
    barrierPath,
    failures,
  );
  _expectValue(barrier, 'marker_atomic', true, barrierPath, failures);
  _expectValue(barrier, 'prior_status', 'downloading', barrierPath, failures);
  _expectValue(barrier, 'attempt', 1, barrierPath, failures);
  final oldPid = _requiredDigest(
    barrier,
    'old_pid_sha256',
    barrierPath,
    failures,
  );

  const stoppedPath = r'$.flow_events[receiver_process_force_stopped].facts';
  _expectExactKeys(
    stopped,
    const <String>{'old_pid_sha256', 'old_pid_gone'},
    stoppedPath,
    failures,
  );
  final stoppedPid = _requiredDigest(
    stopped,
    'old_pid_sha256',
    stoppedPath,
    failures,
  );
  _expectValue(stopped, 'old_pid_gone', true, stoppedPath, failures);

  const relaunchedPath = r'$.flow_events[receiver_process_relaunched].facts';
  _expectExactKeys(
    relaunched,
    const <String>{
      'old_pid_sha256',
      'fresh_pid_sha256',
      'launcher_only',
      'pid_changed',
    },
    relaunchedPath,
    failures,
  );
  final relaunchedOldPid = _requiredDigest(
    relaunched,
    'old_pid_sha256',
    relaunchedPath,
    failures,
  );
  final freshPid = _requiredDigest(
    relaunched,
    'fresh_pid_sha256',
    relaunchedPath,
    failures,
  );
  _expectValue(relaunched, 'launcher_only', true, relaunchedPath, failures);
  _expectValue(relaunched, 'pid_changed', true, relaunchedPath, failures);

  const priorPath = r'$.flow_events[receiver_prior_status_read].facts';
  _expectExactKeys(
    prior,
    const <String>{'prior_status', 'after_relaunch', 'attempt'},
    priorPath,
    failures,
  );
  _expectValue(prior, 'prior_status', 'downloading', priorPath, failures);
  _expectValue(prior, 'after_relaunch', true, priorPath, failures);
  _expectValue(prior, 'attempt', 2, priorPath, failures);

  if (oldPid != null && (stoppedPid != oldPid || relaunchedOldPid != oldPid)) {
    failures.add(r'$.flow_events process events must bind the same old PID');
  }
  if (oldPid != null && freshPid != null && oldPid == freshPid) {
    failures.add(r'$.flow_events fresh PID must differ from the old PID');
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
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      failures.add('$path keys must be strings');
      return null;
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String path,
  List<String> failures,
) {
  final actual = value.keys.toSet();
  final missing = expected.difference(actual).toList()..sort();
  final unexpected = actual.difference(expected).toList()..sort();
  if (missing.isNotEmpty) {
    failures.add('$path missing keys: ${missing.join(', ')}');
  }
  if (unexpected.isNotEmpty) {
    failures.add('$path unexpected keys: ${unexpected.join(', ')}');
  }
}

void _expectValue(
  Map<String, Object?> value,
  String key,
  Object expected,
  String path,
  List<String> failures,
) {
  if (value[key] != expected) failures.add('$path.$key must equal $expected');
}

String? _requiredDigest(
  Map<String, Object?> value,
  String key,
  String path,
  List<String> failures,
) {
  final digest = value[key];
  if (digest is! String || !_sha256Pattern.hasMatch(digest)) {
    failures.add('$path.$key must be a lowercase SHA-256 digest');
    return null;
  }
  return digest;
}

String? _requiredSafeIdentifier(
  Map<String, Object?> value,
  String key,
  String path,
  List<String> failures,
) {
  final identifier = value[key];
  if (identifier is! String || !_safeIdentifierPattern.hasMatch(identifier)) {
    failures.add('$path.$key must be a safe non-empty identifier');
    return null;
  }
  return identifier;
}
