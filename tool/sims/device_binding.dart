import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'live_device_resolver.dart';
import 'manifest.dart';
import 'planner.dart';
import 'verdict.dart';

final class SimsDevicePlanBinding {
  SimsDevicePlanBinding._({
    required this.plan,
    required this.environment,
    required this.environmentByCapabilityId,
    required this.assignments,
    required this.targetStateDigests,
    required this.preflightVerdicts,
    required this.preparationTargets,
    required this.skippedBuildProfiles,
    required this.inventoryDigest,
  });

  factory SimsDevicePlanBinding.bind(
    SimsPlan source,
    SimsLiveDeviceInventory inventory, {
    Map<String, String> processEnvironment = const <String, String>{},
    bool blockPreparationRequired = true,
  }) {
    final resolver = SimsLiveDeviceResolver(inventory);
    final environment = <String, String>{};
    final environmentByCapabilityId = <String, Map<String, String>>{};
    final assignments = <String, String>{};
    final preflight = <String, SimsVerdict>{};
    final preparationById = <String, SimsLiveDeviceTarget>{};
    final rows = <CapabilitySpec>[];
    final requiredTargetIds = _requiredTargetIdsForPlan(
      source.rows,
      processEnvironment,
    );

    for (final row in source.rows) {
      if (!row.automationReady) {
        preflight[row.id] = SimsVerdict.blocked(
          row.id,
          blocker: SimsBlockerKind.missingDriver,
          detail:
              'Capability is registered but its automated proof driver is '
              'not implemented.',
        );
        rows.add(row.copyWith(dependencies: const <String>[]));
        continue;
      }
      final iosNotificationRow =
          row.id == 'notifications.ios_payload_fast_path';
      final resolution = resolver.resolveLocks(
        row.resources,
        requiredTargetIds: requiredTargetIds,
      );
      final disposableAuthorizationIssue =
          row.targetCapabilities.contains('ios.simulators.disposable')
          ? _disposableSimulatorAuthorizationIssue(processEnvironment)
          : null;
      if (disposableAuthorizationIssue != null &&
          (resolution.status == SimsDeviceResolutionStatus.resolved ||
              resolution.status ==
                  SimsDeviceResolutionStatus.preparationRequired)) {
        preflight[row.id] = SimsVerdict.blocked(
          row.id,
          blocker: SimsBlockerKind.permissions,
          detail: disposableAuthorizationIssue,
        );
        rows.add(row.copyWith(dependencies: const <String>[]));
        continue;
      }
      if (resolution.status != SimsDeviceResolutionStatus.resolved) {
        switch (resolution.status) {
          case SimsDeviceResolutionStatus.resolved:
            throw StateError('unreachable resolved-device branch');
          case SimsDeviceResolutionStatus.preparationRequired:
            for (final target in resolution.preparationTargets) {
              final id = target.launchId ?? target.runtimeId ?? target.name;
              preparationById[id] = target;
            }
            if (blockPreparationRequired) {
              preflight[row.id] = SimsVerdict.blocked(
                row.id,
                blocker: SimsBlockerKind.environment,
                detail: resolution.detail,
              );
            }
            rows.add(row);
          case SimsDeviceResolutionStatus.targetUnavailable:
            preflight[row.id] = SimsVerdict.notApplicable(
              row.id,
              blocker: SimsBlockerKind.targetUnavailable,
              targetCapabilityAvailable: false,
              reason: resolution.naReason!,
              detail: resolution.detail,
            );
            rows.add(row);
          case SimsDeviceResolutionStatus.discoveryFailed:
            preflight[row.id] = SimsVerdict.blocked(
              row.id,
              blocker: SimsBlockerKind.environment,
              detail: resolution.detail,
            );
            rows.add(row);
          case SimsDeviceResolutionStatus.invalidResource:
            preflight[row.id] = SimsVerdict.fail(
              row.id,
              assertionsAttempted: 0,
              blocker: SimsBlockerKind.harness,
              detail: resolution.detail,
            );
            rows.add(row);
        }
        continue;
      }

      final preflightIssues = <_PreflightIssue>[];
      if (iosNotificationRow) {
        preflightIssues.addAll(
          _iosNotificationPreflightIssues(processEnvironment),
        );
      } else if (row.targetCapabilities.contains('relay.staging') &&
          (processEnvironment['MKNOON_RELAY_ADDRESSES']?.trim().isEmpty ??
              true)) {
        preflightIssues.add(
          const _PreflightIssue(
            SimsBlockerKind.environment,
            'MKNOON_RELAY_ADDRESSES is required for the staging-relay '
            'proof boundary.',
          ),
        );
      }
      if (!_isBuildRow(row) &&
          row.targetCapabilities.contains('credentials.fcm')) {
        final credentialIssue = _fcmCredentialIssue(processEnvironment);
        if (credentialIssue != null) {
          preflightIssues.add(
            _PreflightIssue(SimsBlockerKind.credentials, credentialIssue),
          );
        }
      }
      if (row.targetCapabilities.contains('credentials.apns-signing')) {
        final signingIssue = _iosSigningIssue(processEnvironment);
        if (signingIssue != null) {
          preflightIssues.add(
            _PreflightIssue(SimsBlockerKind.credentials, signingIssue),
          );
        }
      }
      if (preflightIssues.isNotEmpty) {
        preflight[row.id] = SimsVerdict.blocked(
          row.id,
          blocker: preflightIssues.first.blocker,
          detail: preflightIssues.map((issue) => issue.detail).join(' '),
        );
        rows.add(row.copyWith(dependencies: const <String>[]));
        continue;
      }
      environmentByCapabilityId[row.id] = Map<String, String>.unmodifiable(
        resolution.environment,
      );
      _mergeWithoutConflict(
        environment,
        Map<String, String>.of(resolution.environment)
          ..remove('SIMS_DEVICE_ASSIGNMENTS_JSON'),
      );
      _mergeWithoutConflict(assignments, resolution.assignments);
      rows.add(
        row.copyWith(
          resources: <ResourceLock>[
            for (final lock in row.resources)
              ResourceLock(
                name: _resolvedResourceName(
                  lock.name,
                  resolution.assignments[lock.name],
                ),
                access: lock.access,
              ),
          ],
        ),
      );
    }

    environment['SIMS_DEVICE_ASSIGNMENTS_JSON'] = _assignmentsJson(assignments);

    final skippedBuildProfiles = <String>{};
    for (final buildRow in rows.where(
      (row) => row.command.isNotEmpty && row.command.first == '@prepare-build',
    )) {
      final consumers = rows.where(
        (row) =>
            row.id != buildRow.id &&
            row.buildProfileId == buildRow.buildProfileId,
      );
      if (consumers.isEmpty) continue;
      final runnableConsumers = consumers.where(
        (row) => !preflight.containsKey(row.id),
      );
      if (runnableConsumers.isNotEmpty) continue;
      final allUnavailable = consumers.every(
        (row) => preflight[row.id]?.status == SimsVerdictStatus.notApplicable,
      );
      skippedBuildProfiles.add(buildRow.buildProfileId);
      MapEntry<String, SimsVerdict?>? firstActualBlocker;
      for (final consumer in consumers) {
        final verdict = preflight[consumer.id];
        if (verdict != null &&
            verdict.status != SimsVerdictStatus.notApplicable) {
          firstActualBlocker = MapEntry<String, SimsVerdict?>(
            consumer.id,
            verdict,
          );
          break;
        }
      }
      preflight[buildRow.id] = allUnavailable
          ? SimsVerdict.notApplicable(
              buildRow.id,
              blocker: SimsBlockerKind.targetUnavailable,
              targetCapabilityAvailable: false,
              reason: targetUnavailableNaReason,
              detail:
                  'Build omitted because every selected consumer target is '
                  'unavailable by project policy.',
            )
          : SimsVerdict.blocked(
              buildRow.id,
              blocker:
                  firstActualBlocker?.value?.blocker ??
                  SimsBlockerKind.dependency,
              detail:
                  'Build omitted because no selected consumer is runnable. '
                  '${firstActualBlocker == null ? 'Consumer preflight did not provide a blocker.' : '${firstActualBlocker.key}: ${firstActualBlocker.value!.detail}'}',
            );
    }

    final iosA = environment['SIMS_IOS_SIMULATOR_A_DEVICE_ID'];
    if (iosA != null) environment['SIMS_IOS_SIMULATOR_ID'] = iosA;
    final iosIds = <String>[
      for (final name in const <String>[
        'SIMS_IOS_SIMULATOR_A_DEVICE_ID',
        'SIMS_IOS_SIMULATOR_B_DEVICE_ID',
        'SIMS_IOS_SIMULATOR_C_DEVICE_ID',
        'SIMS_IOS_SIMULATOR_D_DEVICE_ID',
      ])
        ?environment[name],
    ];
    if (iosIds.isNotEmpty) {
      environment['SIMS_IOS_SIMULATOR_IDS'] = iosIds.join(',');
    }

    final targetStateDigests = <String, String>{};
    for (final targetId in assignments.values.toSet()) {
      final target =
          inventory.byRuntimeId(targetId) ?? inventory.byLaunchId(targetId);
      if (target == null) {
        throw StateError(
          'Resolved target is absent from the discovered inventory: $targetId',
        );
      }
      targetStateDigests[targetId] = sha256
          .convert(
            utf8.encode(
              canonicalJson(<String, Object?>{
                'target': target.toJson(),
                'sourceStatus': <String, String>{
                  for (final source in target.sources)
                    source.name: inventory.sourceStatus(source).name,
                },
              }),
            ),
          )
          .toString();
    }

    return SimsDevicePlanBinding._(
      plan: SimsPlan(
        mode: source.mode,
        simultaneous: source.simultaneous,
        releaseEligibleCandidate: source.releaseEligibleCandidate,
        manifestDigest: source.manifestDigest,
        family: source.family,
        onlyId: source.onlyId,
        lane: source.lane,
        rows: List<CapabilitySpec>.unmodifiable(rows),
      ),
      environment: Map<String, String>.unmodifiable(environment),
      environmentByCapabilityId: Map<String, Map<String, String>>.unmodifiable(
        environmentByCapabilityId,
      ),
      assignments: Map<String, String>.unmodifiable(assignments),
      targetStateDigests: Map<String, String>.unmodifiable(targetStateDigests),
      preflightVerdicts: Map<String, SimsVerdict>.unmodifiable(preflight),
      preparationTargets: List<SimsLiveDeviceTarget>.unmodifiable(
        preparationById.values,
      ),
      skippedBuildProfiles: Set<String>.unmodifiable(skippedBuildProfiles),
      inventoryDigest: simsLiveDeviceInventoryDigest(inventory),
    );
  }

  final SimsPlan plan;
  final Map<String, String> environment;
  final Map<String, Map<String, String>> environmentByCapabilityId;
  final Map<String, String> assignments;
  final Map<String, String> targetStateDigests;
  final Map<String, SimsVerdict> preflightVerdicts;
  final List<SimsLiveDeviceTarget> preparationTargets;
  final Set<String> skippedBuildProfiles;
  final String inventoryDigest;
}

String simsLiveDeviceInventoryDigest(SimsLiveDeviceInventory inventory) {
  final targets = inventory.targets.map((target) => target.toJson()).toList()
    ..sort(
      (left, right) => canonicalJson(left).compareTo(canonicalJson(right)),
    );
  final notReadyTargetClasses =
      inventory.notReadyTargetClasses
          .map((targetClass) => targetClass.name)
          .toList()
        ..sort();
  return sha256
      .convert(
        utf8.encode(
          canonicalJson(<String, Object?>{
            'targets': targets,
            'notReadyTargetClasses': notReadyTargetClasses,
            'sourceStatuses': <String, String>{
              for (final source in SimsDeviceDiscoverySource.values)
                source.name: inventory.sourceStatus(source).name,
            },
          }),
        ),
      )
      .toString();
}

Map<String, String> _requiredTargetIdsForPlan(
  Iterable<CapabilitySpec> rows,
  Map<String, String> environment,
) {
  final result = <String, String>{};
  for (final row in rows) {
    final required = _requiredTargetIdsFor(
      row,
      environment,
      iosNotificationRow: row.id == 'notifications.ios_payload_fast_path',
    );
    _mergeWithoutConflict(result, required);
  }
  return Map<String, String>.unmodifiable(result);
}

String _assignmentsJson(Map<String, String> assignments) {
  final entries = assignments.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return jsonEncode(<String, String>{
    for (final entry in entries) entry.key: entry.value,
  });
}

bool _isBuildRow(CapabilitySpec row) =>
    row.command.isNotEmpty && row.command.first == '@prepare-build';

final class _PreflightIssue {
  const _PreflightIssue(this.blocker, this.detail);

  final SimsBlockerKind blocker;
  final String detail;
}

Map<String, String> _requiredTargetIdsFor(
  CapabilitySpec row,
  Map<String, String> environment, {
  required bool iosNotificationRow,
}) {
  final result = <String, String>{};
  for (final resource in row.resources) {
    final environmentName = switch (resource.name.split(':').last) {
      'android-physical' => 'SIMS_ANDROID_PHYSICAL_DEVICE_ID',
      'android-emulator' => 'SIMS_ANDROID_EMULATOR_DEVICE_ID',
      'android-emulator-second' => 'SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID',
      _ => null,
    };
    if (environmentName == null) continue;
    final targetId = environment[environmentName]?.trim();
    if (targetId != null && targetId.isNotEmpty) {
      result[resource.name] = targetId;
    }
  }
  if (row.targetCapabilities.contains('ios.simulators.disposable')) {
    final ids = _validDisposableSimulatorIds(environment);
    if (ids != null) {
      const resources = <String>[
        'device:ios-simulator-a',
        'device:ios-simulator-b',
        'device:ios-simulator-c',
        'device:ios-simulator-d',
      ];
      for (var index = 0; index < resources.length; index += 1) {
        result[resources[index]] = ids[index];
      }
    }
  }
  if (iosNotificationRow) {
    final staging = _jsonEnvironmentFile(
      environment,
      'SIMS_IOS_NOTIFICATION_STAGING_MANIFEST',
    );
    if (staging != null && _validIosStagingAttestation(staging)) {
      result['device:ios-physical'] = '${staging['receiverDeviceId']}'.trim();
    }
  }
  return result;
}

List<String>? _validDisposableSimulatorIds(Map<String, String> environment) {
  final ids = (environment['SIMS_IOS_DISPOSABLE_SIMULATOR_IDS'] ?? '')
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  final uuid = RegExp(
    r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
    caseSensitive: false,
  );
  if (ids.length != 4 ||
      ids.toSet().length != 4 ||
      ids.any((id) => !uuid.hasMatch(id))) {
    return null;
  }
  return ids;
}

String? _disposableSimulatorAuthorizationIssue(
  Map<String, String> environment,
) {
  if (_validDisposableSimulatorIds(environment) == null) {
    return 'SIMS_IOS_DISPOSABLE_SIMULATOR_IDS must explicitly authorize four '
        'distinct simulator UUIDs before the group runner may uninstall '
        'Runner or mutate simulator app data.';
  }
  return null;
}

List<_PreflightIssue> _iosNotificationPreflightIssues(
  Map<String, String> environment,
) {
  final issues = <_PreflightIssue>[];
  final staging = _jsonEnvironmentFile(
    environment,
    'SIMS_IOS_NOTIFICATION_STAGING_MANIFEST',
  );
  if (staging == null) {
    issues.add(
      const _PreflightIssue(
        SimsBlockerKind.credentials,
        'SIMS_IOS_NOTIFICATION_STAGING_MANIFEST must be readable, redacted '
        'JSON attesting APNs, signing, dedicated-device cleanup, and relay '
        'readiness.',
      ),
    );
  } else if (!_validIosStagingAttestation(staging)) {
    issues.add(
      const _PreflightIssue(
        SimsBlockerKind.credentials,
        'The iOS staging attestation does not prove development-APNs '
        'credentials/signing, provider probe, relay custody, and '
        'dedicated-device cleanup readiness.',
      ),
    );
  }

  final request = _jsonEnvironmentFile(
    environment,
    'SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST',
  );
  if (request == null || !_validIosProviderRequest(request, staging)) {
    issues.add(
      const _PreflightIssue(
        SimsBlockerKind.credentials,
        'SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST must be readable run-safe '
        'JSON bound to the attested receiver and peer.',
      ),
    );
  }

  final providerDriver =
      environment['SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER']?.trim() ?? '';
  if (!_isExecutableRegularFile(providerDriver)) {
    issues.add(
      const _PreflightIssue(
        SimsBlockerKind.missingDriver,
        'SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER must be an executable '
        'automated setup/APNs/relay-cleanup adapter.',
      ),
    );
  }

  final payloadProducer =
      environment['SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER']?.trim() ?? '';
  if (!_isExecutableRegularFile(payloadProducer) ||
      (staging != null &&
          !_fileMatchesSha256(
            payloadProducer,
            staging['payloadProducerSha256'],
          ))) {
    issues.add(
      const _PreflightIssue(
        SimsBlockerKind.missingDriver,
        'SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER must be the executable '
        'Go 1.25 producer fingerprinted by the staging attestation.',
      ),
    );
  }

  final relayFixture =
      environment['SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER']?.trim() ?? '';
  if (!_isExecutableRegularFile(relayFixture) ||
      (staging != null &&
          !_fileMatchesSha256(
            relayFixture,
            staging['relayFixtureDriverSha256'],
          ))) {
    issues.add(
      const _PreflightIssue(
        SimsBlockerKind.missingDriver,
        'SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER must be the executable '
        'relay adapter fingerprinted by the staging attestation.',
      ),
    );
  }

  final apnsKey = environment['SIMS_IOS_APNS_AUTH_KEY_PATH']?.trim() ?? '';
  final apnsKeyId = environment['SIMS_IOS_APNS_KEY_ID']?.trim() ?? '';
  final apnsTeamId = environment['SIMS_IOS_APNS_TEAM_ID']?.trim() ?? '';
  final appleIdentifier = RegExp(r'^[A-Z0-9]{10}$');
  if (!_isOwnerOnlyRegularFile(apnsKey) ||
      !appleIdentifier.hasMatch(apnsKeyId) ||
      !appleIdentifier.hasMatch(apnsTeamId)) {
    issues.add(
      const _PreflightIssue(
        SimsBlockerKind.credentials,
        'SIMS_IOS_APNS_AUTH_KEY_PATH must be owner-only, and '
        'SIMS_IOS_APNS_KEY_ID/SIMS_IOS_APNS_TEAM_ID must be valid Apple '
        'identifiers for development APNs.',
      ),
    );
  }

  final relayTarget = environment['SIMS_NOTIFICATION_RELAY_TARGET']?.trim();
  final relayKey = environment['SIMS_NOTIFICATION_RELAY_KEY']?.trim() ?? '';
  if (relayTarget == null ||
      relayTarget.isEmpty ||
      relayTarget.contains(RegExp(r'[\r\n]')) ||
      !_isRegularFile(relayKey)) {
    issues.add(
      const _PreflightIssue(
        SimsBlockerKind.environment,
        'SIMS_NOTIFICATION_RELAY_TARGET and a readable '
        'SIMS_NOTIFICATION_RELAY_KEY are required for the iOS custody '
        'campaign.',
      ),
    );
  }
  return issues;
}

String? _iosSigningIssue(Map<String, String> environment) {
  final staging = _jsonEnvironmentFile(
    environment,
    'SIMS_IOS_NOTIFICATION_STAGING_MANIFEST',
  );
  if (staging == null || !_validIosSigningAttestation(staging)) {
    return 'The iOS build requires a readable redacted staging attestation '
        'with a successful development-signing probe and hashed identity.';
  }
  return null;
}

Map<String, Object?>? _jsonEnvironmentFile(
  Map<String, String> environment,
  String name,
) {
  final path = environment[name]?.trim() ?? '';
  if (!_isRegularFile(path)) return null;
  try {
    final decoded = jsonDecode(File(path).readAsStringSync());
    if (decoded is! Map) return null;
    return decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  } on Object {
    return null;
  }
}

bool _validIosStagingAttestation(Map<String, Object?> value) =>
    value['schema'] == 'mknoon.sims.ios-payload-fast-path-staging.v1' &&
    value['environment'] == 'staging' &&
    value['provider'] == 'apns' &&
    value['providerConfigured'] == true &&
    value['providerCredentialsAvailable'] == true &&
    value['providerProbeSucceeded'] == true &&
    value['relayActive'] == true &&
    value['relayInboxSeedDriverAvailable'] == true &&
    value['dedicatedDisposableReceiver'] == true &&
    value['destructiveTestStateResetAuthorized'] == true &&
    value['providerCleanupAvailable'] == true &&
    value['productionDeploymentPerformed'] == false &&
    _validIosSigningAttestation(value) &&
    _safeString(value['receiverDeviceId']) &&
    _safeString(value['peerDeviceId']);

bool _validIosSigningAttestation(Map<String, Object?> value) =>
    value['appSigningAvailable'] == true &&
    value['signingProbeSucceeded'] == true &&
    value['apnsEnvironment'] == 'development' &&
    value['signingEntitlementEnvironment'] == 'development' &&
    value['bundleId'] == 'com.mknoon.app' &&
    _sha256String(value['signingIdentitySha256']);

bool _validIosProviderRequest(
  Map<String, Object?> request,
  Map<String, Object?>? staging,
) {
  if (staging == null ||
      request.keys.toSet().difference(_iosProviderRequestKeys).isNotEmpty ||
      _iosProviderRequestKeys.difference(request.keys.toSet()).isNotEmpty ||
      request['schema'] !=
          'mknoon.sims.ios-payload-fast-path-provider-request.v1' ||
      !_isAsciiFixtureText(request['expectedTitle'], maxLength: 30) ||
      !_isAsciiFixtureText(request['expectedBody'], maxLength: 512) ||
      !_isAsciiFixtureText(request['expectedMessageText'], maxLength: 140) ||
      request['receiverDeviceId'] != staging['receiverDeviceId'] ||
      request['peerDeviceId'] != staging['peerDeviceId']) {
    return false;
  }
  final messageText = request['expectedMessageText']! as String;
  return !(request['expectedTitle']! as String).contains(messageText) &&
      !(request['expectedBody']! as String).contains(messageText);
}

const Set<String> _iosProviderRequestKeys = <String>{
  'schema',
  'expectedTitle',
  'expectedBody',
  'expectedMessageText',
  'receiverDeviceId',
  'peerDeviceId',
};

bool _safeString(Object? value, {int maxLength = 256}) =>
    value is String &&
    value.trim().isNotEmpty &&
    value.length <= maxLength &&
    !value.contains(RegExp(r'[\r\n]'));

bool _isAsciiFixtureText(Object? value, {required int maxLength}) =>
    value is String &&
    value.isNotEmpty &&
    value == value.trim() &&
    value.length <= maxLength &&
    value.codeUnits.every((unit) => unit >= 0x20 && unit <= 0x7e);

bool _sha256String(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isRegularFile(String path) =>
    path.isNotEmpty &&
    FileSystemEntity.typeSync(path, followLinks: true) ==
        FileSystemEntityType.file;

bool _isExecutableRegularFile(String path) {
  if (!_isRegularFile(path)) return false;
  if (Platform.isWindows) return true;
  return Process.runSync('test', <String>['-x', path]).exitCode == 0;
}

bool _isOwnerOnlyRegularFile(String path) {
  if (path.isEmpty ||
      FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.file) {
    return false;
  }
  try {
    return (File(path).statSync().mode & 0x3f) == 0;
  } on FileSystemException {
    return false;
  }
}

bool _fileMatchesSha256(String path, Object? expected) {
  if (!_isRegularFile(path) || !_sha256String(expected)) return false;
  try {
    return sha256.convert(File(path).readAsBytesSync()).toString() == expected;
  } on FileSystemException {
    return false;
  }
}

String? _fcmCredentialIssue(Map<String, String> environment) {
  final configured =
      environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']?.trim().isNotEmpty ==
          true
      ? environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']!.trim()
      : environment['FIREBASE_SERVICE_ACCOUNT']?.trim();
  if (configured == null || configured.isEmpty) {
    return 'FIREBASE_SERVICE_ACCOUNT (or '
        'SIMS_PROVIDER_FCM_CREDENTIAL_PATH) is required for the real FCM '
        'proof boundary.';
  }
  final credential = File(configured);
  if (FileSystemEntity.typeSync(credential.path, followLinks: true) !=
      FileSystemEntityType.file) {
    return 'The configured FCM credential is not a readable regular file.';
  }
  try {
    final decoded = jsonDecode(credential.readAsStringSync());
    if (decoded is Map && '${decoded['project_id'] ?? ''}'.trim().isNotEmpty) {
      return null;
    }
  } on Object {
    // The generic message below deliberately avoids reflecting credential
    // contents or an environment-provided secret path into the report.
  }
  return 'The configured FCM credential is not valid service-account JSON '
      'with project_id.';
}

String _resolvedResourceName(String original, String? deviceId) {
  if (deviceId == null) return original;
  if (original.startsWith('device-control:')) {
    return 'device-control:$deviceId';
  }
  if (original.startsWith('device:')) return 'device:$deviceId';
  return original;
}

void _mergeWithoutConflict(
  Map<String, String> destination,
  Map<String, String> source,
) {
  for (final entry in source.entries) {
    final previous = destination[entry.key];
    if (previous != null && previous != entry.value) {
      throw StateError(
        'Conflicting live-device assignment for ${entry.key}: '
        '$previous vs ${entry.value}',
      );
    }
    destination[entry.key] = entry.value;
  }
}
